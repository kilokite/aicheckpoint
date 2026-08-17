import 'dart:io';

import 'package:checkpoint/models/snapshot_diff.dart';
import 'package:checkpoint/services/git_snapshot_service.dart';
import 'package:checkpoint/services/snapshot_diff_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporaryDirectory;
  late GitSnapshotService snapshotService;
  late SnapshotDiffService diffService;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'checkpoint_diff_test_',
    );
    snapshotService = GitSnapshotService();
    diffService = SnapshotDiffService();
    await _git(temporaryDirectory.path, ['init']);
    await _git(temporaryDirectory.path, [
      'config',
      'user.name',
      'Checkpoint Test',
    ]);
    await _git(temporaryDirectory.path, [
      'config',
      'user.email',
      'checkpoint@example.test',
    ]);
    await _git(temporaryDirectory.path, ['config', 'core.autocrlf', 'false']);
    await File(
      p.join(temporaryDirectory.path, 'tracked.txt'),
    ).writeAsString('base tracked\n');
    await File(
      p.join(temporaryDirectory.path, 'working.txt'),
    ).writeAsString('base working\n');
    await File(
      p.join(temporaryDirectory.path, 'removed-in-current.txt'),
    ).writeAsString('snapshot keeps this\n');
    await _git(temporaryDirectory.path, ['add', '.']);
    await _git(temporaryDirectory.path, ['commit', '-m', 'base']);
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test(
    'workspace comparison includes every file state without mutating Git',
    () async {
      final tracked = File(p.join(temporaryDirectory.path, 'tracked.txt'));
      final working = File(p.join(temporaryDirectory.path, 'working.txt'));
      final removed = File(
        p.join(temporaryDirectory.path, 'removed-in-current.txt'),
      );
      final snapshotOnly = File(
        p.join(temporaryDirectory.path, 'snapshot-only.txt'),
      );
      final binary = File(p.join(temporaryDirectory.path, 'binary.dat'));

      await tracked.writeAsString('snapshot tracked\n');
      await _git(temporaryDirectory.path, ['add', 'tracked.txt']);
      await working.writeAsString('snapshot working\n');
      await snapshotOnly.writeAsString('snapshot only\n');
      await binary.writeAsBytes([0, 1, 2]);
      final repository = await snapshotService.inspectRepository(
        temporaryDirectory.path,
      );
      final snapshot = await snapshotService.createSnapshot(
        repository,
        title: 'selected snapshot',
      );

      await tracked.writeAsString('current tracked\n');
      await working.writeAsString('current working\n');
      await removed.delete();
      await snapshotOnly.delete();
      await binary.writeAsBytes([0, 1, 3]);
      await File(
        p.join(temporaryDirectory.path, 'current-only.txt'),
      ).writeAsString('current only\n');

      final headBefore = await _git(temporaryDirectory.path, [
        'rev-parse',
        'HEAD',
      ]);
      final indexBefore = await _git(temporaryDirectory.path, ['write-tree']);
      final refsBefore = await _git(temporaryDirectory.path, ['show-ref']);
      final stashBefore = await _git(temporaryDirectory.path, [
        'stash',
        'list',
      ]);
      final objectsBefore = await _looseObjectCount(temporaryDirectory.path);

      final session = await diffService.compareWithCurrentWorkspace(snapshot);
      addTearDown(session.dispose);
      final files = {for (final file in session.files) file.path: file};

      expect(session.mode, SnapshotDiffMode.currentWorkspace);
      expect(files['tracked.txt']?.status, SnapshotDiffStatus.modified);
      expect(files['working.txt']?.status, SnapshotDiffStatus.modified);
      expect(files['removed-in-current.txt']?.status, SnapshotDiffStatus.added);
      expect(files['snapshot-only.txt']?.status, SnapshotDiffStatus.added);
      expect(files['current-only.txt']?.status, SnapshotDiffStatus.deleted);
      expect(files['binary.dat']?.isBinary, isTrue);

      final patch = await session.loadPatch(files['tracked.txt']!);
      expect(patch, contains('-current tracked'));
      expect(patch, contains('+snapshot tracked'));

      expect(
        await _git(temporaryDirectory.path, ['rev-parse', 'HEAD']),
        headBefore,
      );
      expect(await _git(temporaryDirectory.path, ['write-tree']), indexBefore);
      expect(await _git(temporaryDirectory.path, ['show-ref']), refsBefore);
      expect(
        await _git(temporaryDirectory.path, ['stash', 'list']),
        stashBefore,
      );
      expect(await _looseObjectCount(temporaryDirectory.path), objectsBefore);
      expect(await tracked.readAsString(), 'current tracked\n');
      expect(
        await File(
          p.join(temporaryDirectory.path, 'current-only.txt'),
        ).readAsString(),
        'current only\n',
      );
    },
  );

  test(
    'previous comparison detects changes and renames in chronological order',
    () async {
      final tracked = File(p.join(temporaryDirectory.path, 'tracked.txt'));
      final oldName = File(p.join(temporaryDirectory.path, 'old-name.txt'));
      await tracked.writeAsString('first checkpoint\n');
      await oldName.writeAsString(List.filled(20, 'same line').join('\n'));
      final firstRepository = await snapshotService.inspectRepository(
        temporaryDirectory.path,
      );
      final first = await snapshotService.createSnapshot(
        firstRepository,
        title: 'first',
      );

      await tracked.writeAsString('second checkpoint\n');
      await oldName.rename(p.join(temporaryDirectory.path, 'new-name.txt'));
      final secondRepository = await snapshotService.inspectRepository(
        temporaryDirectory.path,
      );
      final second = await snapshotService.createSnapshot(
        secondRepository,
        title: 'second',
      );

      final session = await diffService.compareWithPreviousSnapshot(
        snapshot: second,
        previousSnapshot: first,
      );
      addTearDown(session.dispose);

      expect(session.mode, SnapshotDiffMode.previousSnapshot);
      final trackedDiff = session.files.singleWhere(
        (file) => file.path == 'tracked.txt',
      );
      final rename = session.files.singleWhere(
        (file) => file.status == SnapshotDiffStatus.renamed,
      );
      expect(rename.oldPath, 'old-name.txt');
      expect(rename.path, 'new-name.txt');
      expect(rename.similarity, 100);

      final patch = await session.loadPatch(trackedDiff);
      expect(patch, contains('-first checkpoint'));
      expect(patch, contains('+second checkpoint'));
    },
  );
}

Future<String> _git(String directory, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: directory,
  );
  if (result.exitCode != 0) {
    throw StateError(result.stderr.toString());
  }
  return result.stdout.toString().trim();
}

Future<int> _looseObjectCount(String directory) async {
  final output = await _git(directory, ['count-objects', '-v']);
  final countLine = output
      .split('\n')
      .firstWhere((line) => line.startsWith('count:'));
  return int.parse(countLine.substring('count:'.length).trim());
}
