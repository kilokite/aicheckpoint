import 'dart:convert';
import 'dart:io';

import 'package:checkpoint/models/snapshot.dart';
import 'package:checkpoint/services/snapshot_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  late SnapshotStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('checkpoint_timeline_');
    store = SnapshotStore(directory: directory);
  });

  tearDown(() async => directory.delete(recursive: true));

  test(
    'restore moves pointer and new snapshot branches without deleting siblings',
    () async {
      await store.add(_snapshot('A', 1));
      await store.add(_snapshot('B', 2));
      await store.add(_snapshot('C', 3));
      await store.recordRestore('A');
      expect((await store.loadTimeline()).pointerFor(r'C:\repo'), 'A');
      expect(
        (await store.loadTimeline()).ancestryFor(
          r'C:\repo',
          await store.load(),
        ),
        {'A'},
      );
      await store.add(_snapshot('D', 4));

      final snapshots = await store.load();
      final timeline = await SnapshotStore(directory: directory).loadTimeline();
      expect(timeline.pointerFor(r'C:\repo'), 'D');
      expect(timeline.lastRestoreFor(r'C:\repo')?.fromId, 'C');
      expect(timeline.lastRestoreFor(r'C:\repo')?.toId, 'A');
      expect(snapshots.first.parentId, 'A');
      expect(snapshots.first.fromRestore, isTrue);
      expect(timeline.ancestryFor(r'C:\repo', snapshots), {'A', 'D'});
      expect(snapshots.map((snapshot) => snapshot.id), containsAll(['B', 'C']));

      await store.add(_snapshot('E', 5));
      expect((await store.load()).first.fromRestore, isFalse);
      expect((await store.load()).first.parentId, 'D');
    },
  );

  test(
    'legacy array remains intact and starts without an assumed pointer',
    () async {
      final file = File(p.join(directory.path, 'Checkpoint', 'snapshots.json'));
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode([_snapshot('A', 1).toJson()]));

      expect((await store.load()).single.id, 'A');
      expect((await store.loadTimeline()).pointerFor(r'C:\repo'), isNull);
      await store.recordRestore('A');
      await store.add(_snapshot('B', 2));
      expect((await store.load()).first.parentId, 'A');
    },
  );

  test('deleting pointer clears it without inventing a replacement', () async {
    await store.add(_snapshot('A', 1));
    await store.add(_snapshot('B', 2));
    await store.remove('B');
    expect((await store.loadTimeline()).pointerFor(r'C:\repo'), isNull);
    expect((await store.load()).single.id, 'A');
  });

  test('pointers are independent for each repository', () async {
    await store.add(_snapshot('A', 1));
    await store.add(_snapshot('other', 2, path: r'D:\other'));
    await store.recordRestore('A');
    final timeline = await store.loadTimeline();
    expect(timeline.pointerFor(r'C:\repo'), 'A');
    expect(timeline.pointerFor(r'D:\other'), 'other');
  });
}

Snapshot _snapshot(String id, int minute, {String path = r'C:\repo'}) =>
    Snapshot(
      id: id,
      repositoryPath: path,
      commitHash: 'a' * 40,
      indexTreeHash: 'b' * 40,
      baseHash: 'c' * 40,
      branch: 'main',
      title: id,
      createdAt: DateTime(2026, 9, 24, 12, minute),
      fileCount: 1,
      insertions: 1,
      deletions: 0,
    );
