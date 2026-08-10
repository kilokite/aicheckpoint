import 'dart:io';

import 'package:checkpoint/services/git_snapshot_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporaryDirectory;
  late GitSnapshotService service;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'checkpoint_test_',
    );
    service = GitSnapshotService();
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
      p.join(temporaryDirectory.path, 'staged.txt'),
    ).writeAsString('base staged\n');
    await File(
      p.join(temporaryDirectory.path, 'working.txt'),
    ).writeAsString('base working\n');
    await _git(temporaryDirectory.path, ['add', '.']);
    await _git(temporaryDirectory.path, ['commit', '-m', 'base']);
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test(
    'create is invisible to refs and index, restore recovers full state',
    () async {
      final stagedFile = File(p.join(temporaryDirectory.path, 'staged.txt'));
      final workingFile = File(p.join(temporaryDirectory.path, 'working.txt'));
      final untrackedFile = File(p.join(temporaryDirectory.path, 'new.txt'));
      await stagedFile.writeAsString('snapshot staged\n');
      await _git(temporaryDirectory.path, ['add', 'staged.txt']);
      await workingFile.writeAsString('snapshot working\n');
      await untrackedFile.writeAsString('snapshot untracked\n');

      final headBefore = await _git(temporaryDirectory.path, [
        'rev-parse',
        'HEAD',
      ]);
      final indexBefore = await _git(temporaryDirectory.path, ['write-tree']);
      final stashBefore = await _git(temporaryDirectory.path, [
        'stash',
        'list',
      ]);
      final repository = await service.inspectRepository(
        temporaryDirectory.path,
      );
      final snapshot = await service.createSnapshot(
        repository,
        title: 'test snapshot',
      );

      expect(
        await _git(temporaryDirectory.path, ['rev-parse', 'HEAD']),
        headBefore,
      );
      expect(await _git(temporaryDirectory.path, ['write-tree']), indexBefore);
      expect(
        await _git(temporaryDirectory.path, ['stash', 'list']),
        stashBefore,
      );
      expect(snapshot.commitHash, isNot(headBefore));

      await stagedFile.writeAsString('later\n');
      await workingFile.delete();
      await untrackedFile.delete();
      final extraFile = File(p.join(temporaryDirectory.path, 'extra.txt'));
      await extraFile.writeAsString('remove me\n');

      await service.restoreSnapshot(snapshot);

      expect(await stagedFile.readAsString(), 'snapshot staged\n');
      expect(await workingFile.readAsString(), 'snapshot working\n');
      expect(await untrackedFile.readAsString(), 'snapshot untracked\n');
      expect(await extraFile.exists(), isFalse);
      expect(await _git(temporaryDirectory.path, ['write-tree']), indexBefore);
      expect(
        await _git(temporaryDirectory.path, ['rev-parse', 'HEAD']),
        headBefore,
      );
      expect(
        await _git(temporaryDirectory.path, ['stash', 'list']),
        stashBefore,
      );
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
