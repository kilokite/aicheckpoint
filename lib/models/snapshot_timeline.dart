import 'snapshot.dart';

class RestoreMove {
  const RestoreMove({required this.fromId, required this.toId});

  final String fromId;
  final String toId;

  factory RestoreMove.fromJson(Map<String, dynamic> json) => RestoreMove(
    fromId: json['fromId'] as String,
    toId: json['toId'] as String,
  );

  Map<String, dynamic> toJson() => {'fromId': fromId, 'toId': toId};
}

class SnapshotTimeline {
  const SnapshotTimeline({
    this.pointers = const {},
    this.lastRestores = const {},
  });

  final Map<String, String> pointers;
  final Map<String, RestoreMove> lastRestores;

  static String repositoryKey(String path) =>
      path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '').toLowerCase();

  String? pointerFor(String path) => pointers[repositoryKey(path)];

  RestoreMove? lastRestoreFor(String path) => lastRestores[repositoryKey(path)];

  Set<String> ancestryFor(String path, List<Snapshot> snapshots) {
    final byId = {for (final snapshot in snapshots) snapshot.id: snapshot};
    final active = <String>{};
    var id = pointerFor(path);
    while (id != null && active.add(id)) {
      id = byId[id]?.parentId;
    }
    return active.intersection(byId.keys.toSet());
  }
}
