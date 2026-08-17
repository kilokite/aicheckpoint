import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/snapshot.dart';
import '../models/snapshot_diff.dart';

class SnapshotDiffException implements Exception {
  const SnapshotDiffException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SnapshotDiffSession {
  SnapshotDiffSession._({
    required SnapshotDiffService service,
    required this.mode,
    required this.selectedSnapshot,
    required this.previousSnapshot,
    required this.files,
    required String fromTree,
    required String toTree,
    required Map<String, String> environment,
    Directory? temporaryDirectory,
  }) : _service = service,
       _fromTree = fromTree,
       _toTree = toTree,
       _environment = environment,
       _temporaryDirectory = temporaryDirectory;

  final SnapshotDiffService _service;
  final SnapshotDiffMode mode;
  final Snapshot selectedSnapshot;
  final Snapshot? previousSnapshot;
  final List<SnapshotDiffFile> files;
  final String _fromTree;
  final String _toTree;
  final Map<String, String> _environment;
  final Directory? _temporaryDirectory;
  final Set<Future<void>> _pendingPatches = {};
  bool _disposed = false;
  Future<void>? _disposeFuture;

  int get insertions =>
      files.fold(0, (total, file) => total + (file.insertions ?? 0));

  int get deletions =>
      files.fold(0, (total, file) => total + (file.deletions ?? 0));

  Future<String> loadPatch(SnapshotDiffFile file) {
    if (_disposed) {
      throw const SnapshotDiffException('Diff 会话已经关闭，请重新打开预览。');
    }
    final patch = _service._loadPatch(
      selectedSnapshot.repositoryPath,
      _fromTree,
      _toTree,
      file,
      _environment,
    );
    final completion = patch.then<void>((_) {}, onError: (_, _) {});
    _pendingPatches.add(completion);
    unawaited(
      completion.whenComplete(() => _pendingPatches.remove(completion)),
    );
    return patch;
  }

  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    if (_pendingPatches.isNotEmpty) {
      await Future.wait(_pendingPatches.toList(growable: false));
    }
    final directory = _temporaryDirectory;
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

class SnapshotDiffService {
  static const int _maximumPatchBytes = 1024 * 1024;

  Future<SnapshotDiffSession> compareWithCurrentWorkspace(
    Snapshot snapshot,
  ) async {
    await _ensureSnapshotAvailable(snapshot);
    final lease = await _captureCurrentTree(snapshot.repositoryPath);
    try {
      final files = await _loadFiles(
        snapshot.repositoryPath,
        lease.treeHash,
        snapshot.commitHash,
        lease.environment,
      );
      return SnapshotDiffSession._(
        service: this,
        mode: SnapshotDiffMode.currentWorkspace,
        selectedSnapshot: snapshot,
        previousSnapshot: null,
        files: files,
        fromTree: lease.treeHash,
        toTree: snapshot.commitHash,
        environment: lease.environment,
        temporaryDirectory: lease.directory,
      );
    } catch (_) {
      await lease.dispose();
      rethrow;
    }
  }

  Future<SnapshotDiffSession> compareWithPreviousSnapshot({
    required Snapshot snapshot,
    required Snapshot previousSnapshot,
  }) async {
    if (p.normalize(snapshot.repositoryPath).toLowerCase() !=
        p.normalize(previousSnapshot.repositoryPath).toLowerCase()) {
      throw const SnapshotDiffException('只能比较同一个仓库中的检查点。');
    }
    await _ensureSnapshotAvailable(previousSnapshot);
    await _ensureSnapshotAvailable(snapshot);
    final files = await _loadFiles(
      snapshot.repositoryPath,
      previousSnapshot.commitHash,
      snapshot.commitHash,
      const {},
    );
    return SnapshotDiffSession._(
      service: this,
      mode: SnapshotDiffMode.previousSnapshot,
      selectedSnapshot: snapshot,
      previousSnapshot: previousSnapshot,
      files: files,
      fromTree: previousSnapshot.commitHash,
      toTree: snapshot.commitHash,
      environment: const {},
    );
  }

  Future<void> _ensureSnapshotAvailable(Snapshot snapshot) async {
    final result = await _git(snapshot.repositoryPath, [
      'cat-file',
      '-e',
      '${snapshot.commitHash}^{commit}',
    ], allowFailure: true);
    if (result.exitCode != 0) {
      throw SnapshotDiffException('快照“${snapshot.title}”已被 Git GC 回收，无法预览。');
    }
  }

  Future<_WorkspaceTreeLease> _captureCurrentTree(String root) async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'checkpoint_diff_',
    );
    final temporaryIndex = File(p.join(temporaryDirectory.path, 'index'));
    final temporaryObjects = Directory(
      p.join(temporaryDirectory.path, 'objects'),
    );
    await temporaryObjects.create(recursive: true);

    try {
      final indexPath = _decodeText(
        (await _git(root, [
          'rev-parse',
          '--path-format=absolute',
          '--git-path',
          'index',
        ])).stdout,
      ).trim();
      final objectPath = _decodeText(
        (await _git(root, [
          'rev-parse',
          '--path-format=absolute',
          '--git-path',
          'objects',
        ])).stdout,
      ).trim();
      final existingAlternates =
          Platform.environment['GIT_ALTERNATE_OBJECT_DIRECTORIES'];
      final alternates = <String>[
        objectPath,
        ...existingAlternates == null || existingAlternates.trim().isEmpty
            ? const []
            : [existingAlternates],
      ].join(Platform.isWindows ? ';' : ':');
      final environment = <String, String>{
        'GIT_INDEX_FILE': temporaryIndex.path,
        'GIT_OBJECT_DIRECTORY': temporaryObjects.path,
        'GIT_ALTERNATE_OBJECT_DIRECTORIES': alternates,
      };

      final sourceIndex = File(indexPath);
      if (await sourceIndex.exists()) {
        await sourceIndex.copy(temporaryIndex.path);
      } else {
        await _git(root, ['read-tree', 'HEAD'], environment: environment);
      }
      await _git(root, ['add', '-A', '--', '.'], environment: environment);
      final treeHash = _decodeText(
        (await _git(root, ['write-tree'], environment: environment)).stdout,
      ).trim();
      return _WorkspaceTreeLease(
        directory: temporaryDirectory,
        treeHash: treeHash,
        environment: environment,
      );
    } catch (_) {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
      rethrow;
    }
  }

  Future<List<SnapshotDiffFile>> _loadFiles(
    String root,
    String fromTree,
    String toTree,
    Map<String, String> environment,
  ) async {
    final results = await Future.wait([
      _git(root, [
        'diff',
        '--name-status',
        '-z',
        '--find-renames',
        fromTree,
        toTree,
        '--',
      ], environment: environment),
      _git(root, [
        'diff',
        '--numstat',
        '-z',
        '--find-renames',
        fromTree,
        toTree,
        '--',
      ], environment: environment),
    ]);
    final statuses = _parseNameStatus(results[0].stdout);
    final stats = _parseNumstat(results[1].stdout);
    final statsByKey = {for (final item in stats) item.key: item};

    return statuses
        .map((item) {
          final stat = statsByKey[item.key];
          return SnapshotDiffFile(
            status: item.status,
            path: item.path,
            oldPath: item.oldPath,
            insertions: stat?.insertions,
            deletions: stat?.deletions,
            similarity: item.similarity,
          );
        })
        .toList(growable: false);
  }

  Future<String> _loadPatch(
    String root,
    String fromTree,
    String toTree,
    SnapshotDiffFile file,
    Map<String, String> environment,
  ) async {
    final paths = <String>{?file.oldPath, file.path};
    final result = await _git(root, [
      'diff',
      '--no-color',
      '--no-ext-diff',
      '--no-textconv',
      '--unified=3',
      '--find-renames',
      fromTree,
      toTree,
      '--',
      ...paths,
    ], environment: environment);
    final truncated = result.stdout.length > _maximumPatchBytes;
    final bytes = truncated
        ? result.stdout.sublist(0, _maximumPatchBytes)
        : result.stdout;
    final patch = _decodeText(bytes);
    if (!truncated) return patch.isEmpty ? '该文件没有可显示的文本差异。' : patch;
    return '$patch\n\n…… Diff 超过 1 MB，已截断显示。';
  }

  List<_DiffEntry> _parseNameStatus(List<int> bytes) {
    final fields = _nulFields(bytes);
    final entries = <_DiffEntry>[];
    var index = 0;
    while (index < fields.length) {
      final rawStatus = _decodeText(fields[index++]);
      if (rawStatus.isEmpty || index >= fields.length) break;
      final code = rawStatus[0];
      final similarity = rawStatus.length > 1
          ? int.tryParse(rawStatus.substring(1))
          : null;
      String? oldPath;
      late String path;
      if ((code == 'R' || code == 'C') && index + 1 < fields.length) {
        oldPath = _decodeText(fields[index++]);
        path = _decodeText(fields[index++]);
      } else {
        path = _decodeText(fields[index++]);
      }
      entries.add(
        _DiffEntry(
          status: _statusFromCode(code),
          path: path,
          oldPath: oldPath,
          similarity: similarity,
        ),
      );
    }
    return entries;
  }

  List<_NumstatEntry> _parseNumstat(List<int> bytes) {
    final entries = <_NumstatEntry>[];
    var offset = 0;
    while (offset < bytes.length) {
      final insertionField = _readUntil(bytes, offset, 0x09);
      if (insertionField == null) break;
      offset = insertionField.nextOffset;
      final deletionField = _readUntil(bytes, offset, 0x09);
      if (deletionField == null) break;
      offset = deletionField.nextOffset;

      String? oldPath;
      late String path;
      if (offset < bytes.length && bytes[offset] == 0) {
        offset++;
        final oldField = _readUntil(bytes, offset, 0);
        if (oldField == null) break;
        oldPath = _decodeText(oldField.bytes);
        offset = oldField.nextOffset;
        final pathField = _readUntil(bytes, offset, 0);
        if (pathField == null) break;
        path = _decodeText(pathField.bytes);
        offset = pathField.nextOffset;
      } else {
        final pathField = _readUntil(bytes, offset, 0);
        if (pathField == null) break;
        path = _decodeText(pathField.bytes);
        offset = pathField.nextOffset;
      }

      final insertionText = _decodeText(insertionField.bytes);
      final deletionText = _decodeText(deletionField.bytes);
      entries.add(
        _NumstatEntry(
          path: path,
          oldPath: oldPath,
          insertions: int.tryParse(insertionText),
          deletions: int.tryParse(deletionText),
        ),
      );
    }
    return entries;
  }

  List<List<int>> _nulFields(List<int> bytes) {
    final fields = <List<int>>[];
    var start = 0;
    for (var index = 0; index < bytes.length; index++) {
      if (bytes[index] != 0) continue;
      fields.add(bytes.sublist(start, index));
      start = index + 1;
    }
    if (start < bytes.length) fields.add(bytes.sublist(start));
    return fields;
  }

  _ByteField? _readUntil(List<int> bytes, int offset, int delimiter) {
    if (offset >= bytes.length) return null;
    final end = bytes.indexOf(delimiter, offset);
    if (end < 0) return null;
    return _ByteField(bytes.sublist(offset, end), end + 1);
  }

  SnapshotDiffStatus _statusFromCode(String code) => switch (code) {
    'A' => SnapshotDiffStatus.added,
    'M' => SnapshotDiffStatus.modified,
    'D' => SnapshotDiffStatus.deleted,
    'R' => SnapshotDiffStatus.renamed,
    'C' => SnapshotDiffStatus.copied,
    'T' => SnapshotDiffStatus.typeChanged,
    'U' => SnapshotDiffStatus.unmerged,
    _ => SnapshotDiffStatus.unknown,
  };

  Future<_GitOutput> _git(
    String workingDirectory,
    List<String> arguments, {
    Map<String, String> environment = const {},
    bool allowFailure = false,
  }) async {
    ProcessResult result;
    try {
      result = await Process.run(
        'git',
        arguments,
        workingDirectory: workingDirectory,
        environment: {...Platform.environment, ...environment},
        runInShell: false,
        stdoutEncoding: null,
        stderrEncoding: null,
      );
    } on ProcessException catch (error) {
      throw SnapshotDiffException('无法启动 Git：${error.message}');
    }

    final stdout = result.stdout as List<int>;
    final stderr = result.stderr as List<int>;
    if (result.exitCode != 0 && !allowFailure) {
      final detail = _decodeText(stderr).trim();
      throw SnapshotDiffException(detail.isEmpty ? 'Git Diff 执行失败。' : detail);
    }
    return _GitOutput(result.exitCode, stdout);
  }

  static String _decodeText(List<int> bytes) =>
      utf8.decode(bytes, allowMalformed: true);
}

class _WorkspaceTreeLease {
  const _WorkspaceTreeLease({
    required this.directory,
    required this.treeHash,
    required this.environment,
  });

  final Directory directory;
  final String treeHash;
  final Map<String, String> environment;

  Future<void> dispose() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

class _GitOutput {
  const _GitOutput(this.exitCode, this.stdout);

  final int exitCode;
  final List<int> stdout;
}

class _ByteField {
  const _ByteField(this.bytes, this.nextOffset);

  final List<int> bytes;
  final int nextOffset;
}

class _DiffEntry {
  const _DiffEntry({
    required this.status,
    required this.path,
    required this.oldPath,
    required this.similarity,
  });

  final SnapshotDiffStatus status;
  final String path;
  final String? oldPath;
  final int? similarity;

  String get key => '${oldPath ?? ''}\u0000$path';
}

class _NumstatEntry {
  const _NumstatEntry({
    required this.path,
    required this.oldPath,
    required this.insertions,
    required this.deletions,
  });

  final String path;
  final String? oldPath;
  final int? insertions;
  final int? deletions;

  String get key => '${oldPath ?? ''}\u0000$path';
}
