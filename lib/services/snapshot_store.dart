import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/snapshot.dart';
import '../models/snapshot_timeline.dart';

class SnapshotStore {
  SnapshotStore({Directory? directory}) : _directory = directory;

  final Directory? _directory;
  Future<void> _pendingOperation = Future.value();

  Future<File> get _file async {
    final support = _directory ?? await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'Checkpoint'));
    await directory.create(recursive: true);
    return File(p.join(directory.path, 'snapshots.json'));
  }

  Future<List<Snapshot>> load() =>
      _exclusive(() async => (await _loadStateUnlocked()).snapshots);

  Future<SnapshotTimeline> loadTimeline() =>
      _exclusive(() async => (await _loadStateUnlocked()).timeline);

  Future<List<Snapshot>> add(Snapshot snapshot) => _exclusive(() async {
    final state = await _loadStateUnlocked();
    final snapshots = state.snapshots;
    final key = SnapshotTimeline.repositoryKey(snapshot.repositoryPath);
    final parentId = state.pointers[key];
    final linked = snapshot.withParent(
      parentId,
      fromRestore: parentId != null && state.pendingRestores[key] == parentId,
    );
    snapshots.removeWhere((item) => item.id == snapshot.id);
    snapshots.insert(0, linked);
    state.pointers[key] = linked.id;
    state.pendingRestores.remove(key);
    await _saveStateUnlocked(state);
    return snapshots;
  });

  Future<void> recordRestore(String id) => _exclusive(() async {
    final state = await _loadStateUnlocked();
    final snapshot = state.snapshots.where((item) => item.id == id).firstOrNull;
    if (snapshot == null) throw StateError('快照记录已不存在');
    final key = SnapshotTimeline.repositoryKey(snapshot.repositoryPath);
    final previous = state.pointers[key];
    if (previous != null && previous != id) {
      state.lastRestores[key] = RestoreMove(fromId: previous, toId: id);
    } else {
      state.lastRestores.remove(key);
    }
    state.pointers[key] = id;
    state.pendingRestores[key] = id;
    await _saveStateUnlocked(state);
  });

  Future<List<Snapshot>> rename(String id, String title) =>
      _exclusive(() async {
        final state = await _loadStateUnlocked();
        final snapshots = state.snapshots;
        final index = snapshots.indexWhere((item) => item.id == id);
        if (index >= 0) {
          snapshots[index] = snapshots[index].copyWith(title: title);
        }
        await _saveStateUnlocked(state);
        return snapshots;
      });

  Future<List<Snapshot>> remove(String id) => _exclusive(() async {
    final state = await _loadStateUnlocked();
    final snapshots = state.snapshots;
    snapshots.removeWhere((item) => item.id == id);
    _pruneTimeline(state);
    await _saveStateUnlocked(state);
    return snapshots;
  });

  Future<List<Snapshot>> removeMany(Iterable<String> ids) =>
      _exclusive(() async {
        final state = await _loadStateUnlocked();
        final snapshots = state.snapshots;
        final idSet = ids.toSet();
        snapshots.removeWhere((item) => idSet.contains(item.id));
        _pruneTimeline(state);
        await _saveStateUnlocked(state);
        return snapshots;
      });

  Future<_SnapshotState> _loadStateUnlocked() async {
    final file = await _file;
    if (!await file.exists()) return _SnapshotState();

    try {
      final decoded = jsonDecode(await file.readAsString());
      final data = decoded is List ? null : decoded as Map<String, dynamic>;
      final snapshots =
          ((data?['snapshots'] ?? decoded) as List<dynamic>)
              .map((item) => Snapshot.fromJson(item as Map<String, dynamic>))
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return _SnapshotState(
        snapshots: snapshots,
        pointers: Map<String, String>.from(data?['pointers'] ?? {}),
        lastRestores: (data?['lastRestores'] as Map<String, dynamic>? ?? {})
            .map(
              (key, value) => MapEntry(
                key,
                RestoreMove.fromJson(value as Map<String, dynamic>),
              ),
            ),
        pendingRestores: Map<String, String>.from(
          data?['pendingRestores'] ?? {},
        ),
      );
    } on Object {
      await file.copy('${file.path}.invalid');
      return _SnapshotState();
    }
  }

  void _pruneTimeline(_SnapshotState state) {
    final ids = state.snapshots.map((item) => item.id).toSet();
    state.pointers.removeWhere((_, id) => !ids.contains(id));
    state.pendingRestores.removeWhere((_, id) => !ids.contains(id));
    state.lastRestores.removeWhere(
      (_, move) => !ids.contains(move.fromId) || !ids.contains(move.toId),
    );
  }

  Future<void> _saveStateUnlocked(_SnapshotState state) async {
    final file = await _file;
    final temp = File('${file.path}.tmp');
    const encoder = JsonEncoder.withIndent('  ');
    await temp.writeAsString(
      encoder.convert({
        'snapshots': state.snapshots.map((item) => item.toJson()).toList(),
        'pointers': state.pointers,
        'lastRestores': state.lastRestores.map(
          (key, move) => MapEntry(key, move.toJson()),
        ),
        'pendingRestores': state.pendingRestores,
      }),
    );
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }

  Future<T> _exclusive<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _pendingOperation = _pendingOperation.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

class _SnapshotState {
  _SnapshotState({
    List<Snapshot>? snapshots,
    Map<String, String>? pointers,
    Map<String, RestoreMove>? lastRestores,
    Map<String, String>? pendingRestores,
  }) : snapshots = snapshots ?? [],
       pointers = pointers ?? {},
       lastRestores = lastRestores ?? {},
       pendingRestores = pendingRestores ?? {};

  final List<Snapshot> snapshots;
  final Map<String, String> pointers;
  final Map<String, RestoreMove> lastRestores;
  final Map<String, String> pendingRestores;

  SnapshotTimeline get timeline => SnapshotTimeline(
    pointers: Map.unmodifiable(pointers),
    lastRestores: Map.unmodifiable(lastRestores),
  );
}
