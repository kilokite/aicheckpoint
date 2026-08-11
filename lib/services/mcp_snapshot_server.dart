import 'dart:async';

import 'package:mcp_server/mcp_server.dart';

import '../models/snapshot.dart';
import 'git_snapshot_service.dart';
import 'snapshot_store.dart';

typedef SnapshotsChanged = FutureOr<void> Function(List<Snapshot> snapshots);

class McpSnapshotServer {
  McpSnapshotServer({
    required GitSnapshotService git,
    required SnapshotStore store,
    this.onSnapshotsChanged,
    this.listenPort = port,
  }) : _git = git,
       _store = store;

  static const int port = 47173;
  static const String endpoint = '/mcp';
  static const String url = 'http://127.0.0.1:$port$endpoint';

  final GitSnapshotService _git;
  final SnapshotStore _store;
  final SnapshotsChanged? onSnapshotsChanged;
  final int listenPort;

  String get serverUrl => 'http://127.0.0.1:$listenPort$endpoint';

  Server? _server;
  StreamableHttpServerTransport? _transport;

  Future<void> start() async {
    if (_server != null) return;

    final transport = StreamableHttpServerTransport(
      config: StreamableHttpServerConfig(
        host: '127.0.0.1',
        port: listenPort,
        endpoint: endpoint,
        fallbackPorts: [],
        isJsonResponseEnabled: true,
      ),
    );
    final server = Server(
      name: 'Checkpoint',
      version: '1.0.0',
      capabilities: ServerCapabilities.simple(tools: true),
    );

    server.addTool(
      name: 'checkpoint_create_snapshot',
      title: '创建项目快照',
      description:
          '为指定的本地 Git 项目创建一个只增不改的 Checkpoint 快照。'
          '此工具不会移动 HEAD、修改分支或写入 refs/stash。',
      inputSchema: const {
        'type': 'object',
        'additionalProperties': false,
        'properties': {
          'project_path': {
            'type': 'string',
            'minLength': 1,
            'description': '项目的绝对路径，路径内必须是一个已有提交的 Git 仓库。',
          },
          'title': {
            'type': 'string',
            'maxLength': 80,
            'description': '可选的快照名称，用于说明当前工作阶段。',
          },
        },
        'required': ['project_path'],
      },
      handler: (arguments) async {
        final path = arguments['project_path'];
        final requestedTitle = arguments['title'];
        if (path is! String || path.trim().isEmpty) {
          return const CallToolResult(
            content: [TextContent(text: 'project_path 必须是非空字符串。')],
            isError: true,
          );
        }
        if (requestedTitle != null && requestedTitle is! String) {
          return const CallToolResult(
            content: [TextContent(text: 'title 必须是字符串。')],
            isError: true,
          );
        }

        try {
          final repository = await _git.inspectRepository(path.trim());
          final snapshot = await _git.createSnapshot(
            repository,
            title: (requestedTitle as String?)?.trim() ?? 'MCP 快照',
          );
          final snapshots = await _store.add(snapshot);
          await onSnapshotsChanged?.call(snapshots);
          return CallToolResult(
            content: [
              TextContent(
                text:
                    '快照已创建：${snapshot.title}\n'
                    '项目：${snapshot.repositoryPath}\n'
                    '哈希：${snapshot.commitHash}',
              ),
            ],
            structuredContent: {
              'created': true,
              'snapshot_id': snapshot.id,
              'title': snapshot.title,
              'project_path': snapshot.repositoryPath,
              'hash': snapshot.commitHash,
              'created_at': snapshot.createdAt.toIso8601String(),
            },
          );
        } catch (error) {
          final message = error is GitSnapshotException
              ? error.message
              : error.toString();
          return CallToolResult(
            content: [TextContent(text: '创建快照失败：$message')],
            isError: true,
          );
        }
      },
    );

    server.addTool(
      name: 'checkpoint_get_latest_snapshot',
      title: '查询最新项目快照',
      description: '只读查询指定 Git 项目的最新 Checkpoint 快照，用于确认当前状态是否已经保存。',
      inputSchema: const {
        'type': 'object',
        'additionalProperties': false,
        'properties': {
          'project_path': {
            'type': 'string',
            'minLength': 1,
            'description': 'Git 项目的绝对路径。',
          },
        },
        'required': ['project_path'],
      },
      handler: (arguments) async {
        final path = arguments['project_path'];
        if (path is! String || path.trim().isEmpty) {
          return const CallToolResult(
            content: [TextContent(text: 'project_path 必须是非空字符串。')],
            isError: true,
          );
        }

        try {
          final repository = await _git.inspectRepository(path.trim());
          final snapshots = await _store.load();
          final repositoryPath = repository.path.toLowerCase();
          final matches =
              snapshots
                  .where(
                    (snapshot) =>
                        snapshot.repositoryPath.toLowerCase() == repositoryPath,
                  )
                  .toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          if (matches.isEmpty) {
            return const CallToolResult(
              content: [TextContent(text: '该项目还没有快照。')],
              structuredContent: {'found': false},
            );
          }

          final latest = matches.first;
          return CallToolResult(
            content: [
              TextContent(
                text:
                    '最新快照：${latest.title}\n'
                    '哈希：${latest.commitHash}\n'
                    '时间：${latest.createdAt.toIso8601String()}',
              ),
            ],
            structuredContent: {
              'found': true,
              'snapshot_id': latest.id,
              'title': latest.title,
              'project_path': latest.repositoryPath,
              'hash': latest.commitHash,
              'created_at': latest.createdAt.toIso8601String(),
            },
          );
        } catch (error) {
          final message = error is GitSnapshotException
              ? error.message
              : error.toString();
          return CallToolResult(
            content: [TextContent(text: '查询快照失败：$message')],
            isError: true,
          );
        }
      },
    );

    try {
      server.connect(transport);
      await transport.start();
      _transport = transport;
      _server = server;
    } catch (_) {
      server.dispose();
      transport.close();
      rethrow;
    }
  }

  void close() {
    _server?.dispose();
    _transport?.close();
    _server = null;
    _transport = null;
  }
}
