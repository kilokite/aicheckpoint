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

  test('detects snapshots removed by garbage collection', () async {
    final workingFile = File(p.join(temporaryDirectory.path, 'working.txt'));
    await workingFile.writeAsString('snapshot only\n');
    final repository = await service.inspectRepository(temporaryDirectory.path);
    final snapshot = await service.createSnapshot(
      repository,
      title: 'garbage collection test',
    );

    expect(await service.isSnapshotAvailable(snapshot), isTrue);

    await service.runGarbageCollection(temporaryDirectory.path);

    expect(await service.isSnapshotAvailable(snapshot), isFalse);
  });

  test('inspects garbage collection distance with default thresholds',
      () async {
    final status = await service.inspectGarbageCollection(
      temporaryDirectory.path,
    );

    // 未配置 gc.auto / gc.autoPackLimit 时使用 Git 默认值。
    expect(status.autoThreshold, 6700);
    expect(status.packLimit, 50);
    expect(status.looseObjectCount, greaterThanOrEqualTo(0));
    expect(status.packCount, greaterThanOrEqualTo(0));
    expect(status.progress, inInclusiveRange(0.0, 1.0));
    expect(status.remainingDescription, isNotEmpty);

    // 创建快照会产生新的松散对象，GC 距离应随之缩短。
    final repository = await service.inspectRepository(
      temporaryDirectory.path,
    );
    final before = await service.inspectGarbageCollection(
      temporaryDirectory.path,
    );
    await service.createSnapshot(repository, title: 'gc distance');
    final after = await service.inspectGarbageCollection(
      temporaryDirectory.path,
    );
    expect(after.looseObjectCount, greaterThanOrEqualTo(before.looseObjectCount));
  });

  test('inspects garbage collection with configured thresholds', () async {
    await _git(temporaryDirectory.path, ['config', 'gc.auto', '0']);
    final disabled = await service.inspectGarbageCollection(
      temporaryDirectory.path,
    );
    expect(disabled.autoThreshold, 0);
    expect(disabled.autoGcDisabled, isTrue);
    expect(disabled.remainingDescription, contains('禁用'));

    await _git(temporaryDirectory.path, ['config', 'gc.autoPackLimit', '1']);
    // 显式 git gc 会把松散对象打包成一个 pack 文件，从而触及 packLimit。
    await _git(temporaryDirectory.path, ['gc']);
    final configured = await service.inspectGarbageCollection(
      temporaryDirectory.path,
    );
    expect(configured.packLimit, 1);
    expect(configured.packCount, greaterThanOrEqualTo(1));
    expect(configured.exceeds, isTrue);
  });
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
