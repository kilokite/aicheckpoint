import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/snapshot.dart';

class SnapshotStore {
  Future<File> get _file async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'Checkpoint'));
    await directory.create(recursive: true);
    return File(p.join(directory.path, 'snapshots.json'));
  }

  Future<List<Snapshot>> load() async {
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

  Future<void> save(List<Snapshot> snapshots) async {
    final file = await _file;
    final temp = File('${file.path}.tmp');
    const encoder = JsonEncoder.withIndent('  ');
    await temp.writeAsString(
      encoder.convert(snapshots.map((snapshot) => snapshot.toJson()).toList()),
    );
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }
}
