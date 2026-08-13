import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../models/gc_status.dart';
import '../models/snapshot.dart';

class GitSnapshotException implements Exception {
  const GitSnapshotException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GitSnapshotService {
  Future<RepositoryInfo> inspectRepository(String requestedPath) async {
    final input = Directory(requestedPath).absolute.path;
    final root = await _git(input, ['rev-parse', '--show-toplevel']);
    final rootPath = p.normalize(root.stdout.trim());
    final head = await _git(rootPath, ['rev-parse', '--verify', 'HEAD']);
    final branchResult = await _git(rootPath, ['branch', '--show-current']);
    final status = await _git(rootPath, ['status', '--porcelain=v1', '-z']);
    final branch = branchResult.stdout.trim();

    return RepositoryInfo(
      path: rootPath,
      name: p.basename(rootPath),
      branch: branch.isEmpty ? 'detached HEAD' : branch,
      headHash: head.stdout.trim(),
      changedFileCount: _nulSeparatedCount(status.stdout),
    );
  }

  Future<Snapshot> createSnapshot(
    RepositoryInfo repository, {
    required String title,
  }) async {
    final root = repository.path;
    final indexTree = await _git(root, ['write-tree']);
    final indexPathResult = await _git(root, [
      'rev-parse',
      '--path-format=absolute',
      '--git-path',
      'index',
    ]);
    final indexPath = indexPathResult.stdout.trim();
    final tempDirectory = await Directory.systemTemp.createTemp('checkpoint_');
    final tempIndex = File(p.join(tempDirectory.path, 'index'));

    try {
      final sourceIndex = File(indexPath);
      if (await sourceIndex.exists()) {
        await sourceIndex.copy(tempIndex.path);
      } else {
        await _git(
          root,
          ['read-tree', 'HEAD'],
          extraEnvironment: {'GIT_INDEX_FILE': tempIndex.path},
        );
      }

      final environment = {'GIT_INDEX_FILE': tempIndex.path};
      await _git(root, ['add', '-A', '--', '.'], extraEnvironment: environment);
      final created = await _git(root, [
        'stash',
        'create',
        'Checkpoint snapshot',
      ], extraEnvironment: environment);
      final hash = created.stdout.trim().isEmpty
          ? repository.headHash
          : created.stdout.trim();
      final stats = await _diffStats(root, repository.headHash, hash);
      final now = DateTime.now();

      return Snapshot(
        id: '${now.microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}',
        repositoryPath: root,
        commitHash: hash,
        indexTreeHash: indexTree.stdout.trim(),
        baseHash: repository.headHash,
        branch: repository.branch,
        title: title.trim().isEmpty ? _defaultTitle(now) : title.trim(),
        createdAt: now,
        fileCount: stats.$1,
        insertions: stats.$2,
        deletions: stats.$3,
      );
    } finally {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    }
  }

  Future<void> restoreSnapshot(Snapshot snapshot) async {
    final root = snapshot.repositoryPath;
    await _git(root, ['cat-file', '-e', '${snapshot.commitHash}^{commit}']);
    await _git(root, ['cat-file', '-e', '${snapshot.indexTreeHash}^{tree}']);

    // Neither read-tree call updates HEAD or refs. The second call restores
    // the staged/unstaged split while leaving the restored worktree untouched.
    await _git(root, ['clean', '-fd']);
    await _git(root, ['read-tree', '--reset', '-u', snapshot.commitHash]);
    await _git(root, ['read-tree', '--reset', snapshot.indexTreeHash]);
  }

  Future<bool> isSnapshotAvailable(Snapshot snapshot) async {
    final commitExists = await _objectExists(
      snapshot.repositoryPath,
      '${snapshot.commitHash}^{commit}',
    );
    if (!commitExists) return false;
    return _objectExists(
      snapshot.repositoryPath,
      '${snapshot.indexTreeHash}^{tree}',
    );
  }

  Future<void> runGarbageCollection(String repositoryPath) async {
    await _git(repositoryPath, ['gc', '--prune=now']);
  }

  /// 读取仓库距离自动 GC 还有多远：松散对象 / pack 数量与阈值配置。
  Future<GcStatus> inspectGarbageCollection(String repositoryPath) async {
    final auto = await _git(
      repositoryPath,
      ['config', '--get', 'gc.auto'],
      allowFailure: true,
    );
    final packLimit = await _git(
      repositoryPath,
      ['config', '--get', 'gc.autoPackLimit'],
      allowFailure: true,
    );
    final counted = await _git(repositoryPath, ['count-objects', '-v']);
    final autoThreshold = int.tryParse(auto.stdout.trim()) ?? 6700;
    final autoPackLimit = int.tryParse(packLimit.stdout.trim()) ?? 50;

    var loose = 0;
    var packs = 0;
    for (final line in counted.stdout.split('\n')) {
      final trimmed = line.trim();
      final colon = trimmed.indexOf(':');
      if (colon <= 0) continue;
      final key = trimmed.substring(0, colon);
      final value = int.tryParse(trimmed.substring(colon + 1).trim()) ?? 0;
      if (key == 'count') loose = value;
      if (key == 'packs') packs = value;
    }

    return GcStatus(
      looseObjectCount: loose,
      packCount: packs,
      autoThreshold: autoThreshold,
      packLimit: autoPackLimit,
    );
  }

  Future<(int, int, int)> _diffStats(
    String root,
    String base,
    String snapshot,
  ) async {
    final result = await _git(root, ['diff', '--numstat', base, snapshot]);
    var files = 0;
    var insertions = 0;
    var deletions = 0;
    for (final line in result.stdout.split('\n')) {
      if (line.trim().isEmpty) continue;
      final fields = line.split('\t');
      if (fields.length < 3) continue;
      files++;
      insertions += int.tryParse(fields[0]) ?? 0;
      deletions += int.tryParse(fields[1]) ?? 0;
    }
    return (files, insertions, deletions);
  }

  Future<_GitResult> _git(
    String workingDirectory,
    List<String> arguments, {
    Map<String, String> extraEnvironment = const {},
    bool allowFailure = false,
  }) async {
    ProcessResult result;
    try {
      result = await Process.run(
        'git',
        arguments,
        workingDirectory: workingDirectory,
        environment: {...Platform.environment, ...extraEnvironment},
        runInShell: false,
      );
    } on ProcessException catch (error) {
      throw GitSnapshotException('无法启动 Git：${error.message}');
    }

    final stdout = result.stdout.toString();
    final stderr = result.stderr.toString().trim();
    if (result.exitCode != 0 && !allowFailure) {
      final detail = stderr.isEmpty ? stdout.trim() : stderr;
      throw GitSnapshotException(detail.isEmpty ? 'Git 命令执行失败' : detail);
    }
    return _GitResult(stdout);
  }

  Future<bool> _objectExists(String workingDirectory, String object) async {
    ProcessResult result;
    try {
      result = await Process.run(
        'git',
        ['cat-file', '-e', object],
        workingDirectory: workingDirectory,
        runInShell: false,
      );
    } on ProcessException catch (error) {
      throw GitSnapshotException('无法启动 Git：${error.message}');
    }
    return result.exitCode == 0;
  }

  int _nulSeparatedCount(String value) {
    if (value.isEmpty) return 0;
    return value.split('\x00').where((item) => item.isNotEmpty).length;
  }

  static String _defaultTitle(DateTime dateTime) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '快照 ${two(dateTime.month)}-${two(dateTime.day)} '
        '${two(dateTime.hour)}:${two(dateTime.minute)}';
  }
}

class _GitResult {
  const _GitResult(this.stdout);

  final String stdout;
}
