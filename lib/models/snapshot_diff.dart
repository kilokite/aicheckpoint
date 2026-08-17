enum SnapshotDiffMode { currentWorkspace, previousSnapshot }

enum SnapshotDiffStatus {
  added,
  modified,
  deleted,
  renamed,
  copied,
  typeChanged,
  unmerged,
  unknown,
}

class SnapshotDiffFile {
  const SnapshotDiffFile({
    required this.status,
    required this.path,
    this.oldPath,
    this.insertions,
    this.deletions,
    this.similarity,
  });

  final SnapshotDiffStatus status;
  final String path;
  final String? oldPath;
  final int? insertions;
  final int? deletions;
  final int? similarity;

  bool get isBinary => insertions == null || deletions == null;

  String get displayPath => switch (oldPath) {
    final old? when old != path => '$old → $path',
    _ => path,
  };
}
