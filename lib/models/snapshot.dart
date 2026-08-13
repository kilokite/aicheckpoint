import 'gc_status.dart';

class Snapshot {
  const Snapshot({
    required this.id,
    required this.repositoryPath,
    required this.commitHash,
    required this.indexTreeHash,
    required this.baseHash,
    required this.branch,
    required this.title,
    required this.createdAt,
    required this.fileCount,
    required this.insertions,
    required this.deletions,
  });

  final String id;
  final String repositoryPath;
  final String commitHash;
  final String indexTreeHash;
  final String baseHash;
  final String branch;
  final String title;
  final DateTime createdAt;
  final int fileCount;
  final int insertions;
  final int deletions;

  Snapshot copyWith({String? title}) => Snapshot(
    id: id,
    repositoryPath: repositoryPath,
    commitHash: commitHash,
    indexTreeHash: indexTreeHash,
    baseHash: baseHash,
    branch: branch,
    title: title ?? this.title,
    createdAt: createdAt,
    fileCount: fileCount,
    insertions: insertions,
    deletions: deletions,
  );

  factory Snapshot.fromJson(Map<String, dynamic> json) => Snapshot(
    id: json['id'] as String,
    repositoryPath: json['repositoryPath'] as String,
    commitHash: json['commitHash'] as String,
    indexTreeHash: json['indexTreeHash'] as String,
    baseHash: json['baseHash'] as String,
    branch: json['branch'] as String? ?? 'detached HEAD',
    title: json['title'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    fileCount: json['fileCount'] as int? ?? 0,
    insertions: json['insertions'] as int? ?? 0,
    deletions: json['deletions'] as int? ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'repositoryPath': repositoryPath,
    'commitHash': commitHash,
    'indexTreeHash': indexTreeHash,
    'baseHash': baseHash,
    'branch': branch,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'fileCount': fileCount,
    'insertions': insertions,
    'deletions': deletions,
  };
}

class RepositoryInfo {
  const RepositoryInfo({
    required this.path,
    required this.name,
    required this.branch,
    required this.headHash,
    required this.changedFileCount,
    this.gcStatus,
  });

  final String path;
  final String name;
  final String branch;
  final String headHash;
  final int changedFileCount;

  /// 距离 Git 自动 GC 的距离，由界面层单独获取后合并，不随 inspectRepository 返回。
  final GcStatus? gcStatus;

  bool get isDirty => changedFileCount > 0;

  RepositoryInfo copyWith({GcStatus? gcStatus}) => RepositoryInfo(
    path: path,
    name: name,
    branch: branch,
    headHash: headHash,
    changedFileCount: changedFileCount,
    gcStatus: gcStatus,
  );
}
