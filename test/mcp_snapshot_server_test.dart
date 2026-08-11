import 'dart:convert';
import 'dart:io';

import 'package:checkpoint/services/git_snapshot_service.dart';
import 'package:checkpoint/services/mcp_snapshot_server.dart';
import 'package:checkpoint/services/snapshot_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporaryDirectory;
  late Directory repositoryDirectory;
  late McpSnapshotServer server;
  late SnapshotStore store;
  late HttpClient client;
  late String serverUrl;

  Future<String> runGit(List<String> arguments) async {
    final result = await Process.run(
      'git',
      arguments,
      workingDirectory: repositoryDirectory.path,
    );
    if (result.exitCode != 0) throw StateError(result.stderr.toString());
    return result.stdout.toString().trim();
  }

  Future<HttpClientResponse> postMcp(
    Map<String, dynamic> body, {
    String? sessionId,
  }) async {
    final request = await client.postUrl(Uri.parse(serverUrl));
    request.headers.contentType = ContentType.json;
    request.headers.set('Accept', 'application/json, text/event-stream');
    request.headers.set('MCP-Protocol-Version', '2025-06-18');
    if (sessionId != null) request.headers.set('mcp-session-id', sessionId);
    request.write(jsonEncode(body));
    return request.close().timeout(const Duration(seconds: 5));
  }

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'checkpoint_mcp_test_',
    );
    repositoryDirectory = Directory(
      p.join(temporaryDirectory.path, 'repository'),
    );
    await repositoryDirectory.create();
    await runGit(['init']);
    await runGit(['config', 'user.name', 'Checkpoint Test']);
    await runGit(['config', 'user.email', 'checkpoint@example.test']);
    await runGit(['config', 'core.autocrlf', 'false']);
    await File(
      p.join(repositoryDirectory.path, 'tracked.txt'),
    ).writeAsString('base\n');
    await runGit(['add', '.']);
    await runGit(['commit', '-m', 'base']);
    await File(
      p.join(repositoryDirectory.path, 'tracked.txt'),
    ).writeAsString('changed\n');
    await File(
      p.join(repositoryDirectory.path, 'new.txt'),
    ).writeAsString('new\n');

    store = SnapshotStore(
      directory: Directory(p.join(temporaryDirectory.path, 'data')),
    );
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final testPort = socket.port;
    await socket.close();
    server = McpSnapshotServer(
      git: GitSnapshotService(),
      store: store,
      listenPort: testPort,
    );
    serverUrl = server.serverUrl;
    client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    await server.start();
  });

  tearDown(() async {
    client.close(force: true);
    server.close();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test(
    'exposes create plus read-only latest lookup and no mutation tools',
    () async {
      final headBefore = await runGit(['rev-parse', 'HEAD']);
      final stashBefore = await runGit(['stash', 'list']);
      final initialized = await postMcp({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {
          'protocolVersion': '2025-06-18',
          'capabilities': <String, Object?>{},
          'clientInfo': {'name': 'checkpoint-test', 'version': '1.0.0'},
        },
      });
      final sessionId = initialized.headers.value('mcp-session-id');
      expect(sessionId, isNotNull);

      await postMcp({
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      }, sessionId: sessionId);
      final toolsResponse = await postMcp({
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/list',
        'params': <String, Object?>{},
      }, sessionId: sessionId);
      final toolsJson =
          jsonDecode(await utf8.decoder.bind(toolsResponse).join())
              as Map<String, dynamic>;
      final tools =
          (toolsJson['result'] as Map<String, dynamic>)['tools']
              as List<dynamic>;
      final toolNames = tools
          .map((tool) => (tool as Map<String, dynamic>)['name'])
          .toSet();
      expect(toolNames, {
        'checkpoint_create_snapshot',
        'checkpoint_get_latest_snapshot',
      });
      expect(
        toolNames.any(
          (name) => RegExp(
            r'delete|remove|rename|restore|update',
          ).hasMatch(name.toString()),
        ),
        isFalse,
      );

      final callResponse = await postMcp({
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'tools/call',
        'params': {
          'name': 'checkpoint_create_snapshot',
          'arguments': {
            'project_path': repositoryDirectory.path,
            'title': '模型创建',
          },
        },
      }, sessionId: sessionId);
      final callJson =
          jsonDecode(await utf8.decoder.bind(callResponse).join())
              as Map<String, dynamic>;
      expect(callJson['error'], isNull);
      final snapshots = await store.load();
      expect(snapshots, hasLength(1));
      expect(snapshots.single.title, '模型创建');

      final latestResponse = await postMcp({
        'jsonrpc': '2.0',
        'id': 4,
        'method': 'tools/call',
        'params': {
          'name': 'checkpoint_get_latest_snapshot',
          'arguments': {'project_path': repositoryDirectory.path},
        },
      }, sessionId: sessionId);
      final latestJson =
          jsonDecode(await utf8.decoder.bind(latestResponse).join())
              as Map<String, dynamic>;
      final latest = latestJson['result'] as Map<String, dynamic>;
      expect(latest['structuredContent']['found'], isTrue);
      expect(latest['structuredContent']['hash'], snapshots.single.commitHash);
      expect(await runGit(['rev-parse', 'HEAD']), headBefore);
      expect(await runGit(['stash', 'list']), stashBefore);
    },
  );
}
