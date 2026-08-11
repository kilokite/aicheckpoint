import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/snapshot.dart';

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

  Future<List<Snapshot>> load() => _exclusive(_loadUnlocked);

  Future<List<Snapshot>> add(Snapshot snapshot) => _exclusive(() async {
    final snapshots = await _loadUnlocked();
    snapshots.removeWhere((item) => item.id == snapshot.id);
    snapshots.insert(0, snapshot);
    await _saveUnlocked(snapshots);
    return snapshots;
  });

  Future<List<Snapshot>> rename(String id, String title) =>
      _exclusive(() async {
        final snapshots = await _loadUnlocked();
        final index = snapshots.indexWhere((item) => item.id == id);
        if (index >= 0) {
          snapshots[index] = snapshots[index].copyWith(title: title);
        }
        await _saveUnlocked(snapshots);
        return snapshots;
      });

  Future<List<Snapshot>> remove(String id) => _exclusive(() async {
    final snapshots = await _loadUnlocked();
    snapshots.removeWhere((item) => item.id == id);
    await _saveUnlocked(snapshots);
    return snapshots;
  });

  Future<List<Snapshot>> removeMany(Iterable<String> ids) =>
      _exclusive(() async {
        final snapshots = await _loadUnlocked();
        final idSet = ids.toSet();
        snapshots.removeWhere((item) => idSet.contains(item.id));
        await _saveUnlocked(snapshots);
        return snapshots;
      });

  Future<List<Snapshot>> _loadUnlocked() async {
    final file = await _file;
    if (!await file.exists()) return [];

    try {
      final decoded = jsonDecode(await file.readAsString()) as List<dynamic>;
      return decoded
          .map((item) => Snapshot.fromJson(item as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } on Object {
      await file.copy('${file.path}.invalid');
      return [];
    }
  }

  Future<void> _saveUnlocked(List<Snapshot> snapshots) async {
    final file = await _file;
    final temp = File('${file.path}.tmp');
    const encoder = JsonEncoder.withIndent('  ');
    await temp.writeAsString(
      encoder.convert(snapshots.map((snapshot) => snapshot.toJson()).toList()),
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
