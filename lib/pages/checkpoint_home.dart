import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models/snapshot.dart';
import '../services/git_snapshot_service.dart';
import '../services/mcp_snapshot_server.dart';
import '../services/plugin_install_service.dart';
import '../services/snapshot_store.dart';
import '../widgets/checkpoint_sidebar.dart';
import '../widgets/plugin_install_dialog.dart';
import '../widgets/repository_workspace.dart';
import '../widgets/window_title_bar.dart';

class CheckpointHome extends StatefulWidget {
  const CheckpointHome({
    super.key,
    this.initialPath,
    this.silentInitialFailure = false,
    this.enableMcp = true,
  });

  final String? initialPath;
  final bool silentInitialFailure;
  final bool enableMcp;

  @override
  State<CheckpointHome> createState() => _CheckpointHomeState();
}

class _CheckpointHomeState extends State<CheckpointHome> {
  final _git = GitSnapshotService();
  final _store = SnapshotStore();
  final _pluginInstaller = PluginInstallService();

  List<Snapshot> _allSnapshots = [];
  RepositoryInfo? _repository;
  String? _selectedId;
  bool _busy = false;
  String? _error;
  McpSnapshotServer? _mcpServer;
  bool _mcpOnline = false;
  String? _mcpError;

  List<Snapshot> get _snapshots {
    final repository = _repository;
    if (repository == null) return [];
    final normalized = p.normalize(repository.path).toLowerCase();
    return _allSnapshots
        .where(
          (snapshot) =>
              p.normalize(snapshot.repositoryPath).toLowerCase() == normalized,
        )
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Snapshot? get _selectedSnapshot {
    final snapshots = _snapshots;
    if (snapshots.isEmpty) return null;
    return snapshots.where((item) => item.id == _selectedId).firstOrNull ??
        snapshots.first;
  }

  List<String> get _recentRepositories {
    final paths = <String>[];
    for (final snapshot in _allSnapshots) {
      if (!paths.any(
        (item) => item.toLowerCase() == snapshot.repositoryPath.toLowerCase(),
      )) {
        paths.add(snapshot.repositoryPath);
      }
    }
    return paths.take(6).toList();
  }

  @override
  void initState() {
    super.initState();
    _initialize();
    if (widget.enableMcp) _startMcpServer();
  }

  Future<void> _startMcpServer() async {
    final server = McpSnapshotServer(
      git: _git,
      store: _store,
      onSnapshotsChanged: (snapshots) {
        if (mounted) setState(() => _allSnapshots = snapshots);
      },
    );
    _mcpServer = server;
    try {
      await server.start();
      if (mounted) setState(() => _mcpOnline = true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _mcpOnline = false;
          _mcpError = error.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _mcpServer?.close();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      final snapshots = await _store.load();
      if (!mounted) return;
      setState(() => _allSnapshots = snapshots);
      final initialPath = widget.initialPath;
      if (initialPath != null && initialPath.trim().isNotEmpty) {
        if (widget.silentInitialFailure) {
          try {
            final repository = await _git.inspectRepository(initialPath);
            if (mounted) setState(() => _repository = repository);
          } on Object {
            // A GUI launch commonly inherits a non-repository working directory.
          }
        } else {
          await _openRepository(initialPath);
        }
      }
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> _pickRepository() async {
    final path = await getDirectoryPath(confirmButtonText: '打开仓库');
    if (path != null) await _openRepository(path);
  }

  Future<void> _openRepository(String path) async {
    await _runBusy(() async {
      final repository = await _git.inspectRepository(path);
      if (!mounted) return;
      setState(() {
        _repository = repository;
        _selectedId = null;
      });
    });
  }

  Future<void> _refresh() async {
    final repository = _repository;
    if (repository != null) await _openRepository(repository.path);
  }

  Future<void> _createSnapshot() async {
    final repository = _repository;
    if (repository == null || _busy) return;
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建快照'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: '名称（可选）',
              hintText: '例如：重构解析器之前',
            ),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null) return;

    await _runBusy(() async {
      final freshRepository = await _git.inspectRepository(repository.path);
      final snapshot = await _git.createSnapshot(freshRepository, title: title);
      final snapshots = await _store.add(snapshot);
      if (!mounted) return;
      setState(() {
        _allSnapshots = snapshots;
        _repository = freshRepository;
        _selectedId = snapshot.id;
      });
      _showMessage('快照已创建');
    });
  }

  Future<void> _restoreSnapshot(Snapshot snapshot) async {
    RepositoryInfo repository;
    try {
      repository = await _git.inspectRepository(snapshot.repositoryPath);
    } catch (error) {
      _setError(error);
      return;
    }
    if (!mounted) return;

    final baseMismatch = repository.headHash != snapshot.baseHash;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: baseMismatch ? const Color(0xFFFFF1F0) : null,
        icon: Icon(
          baseMismatch ? Icons.warning_amber_rounded : Icons.history,
          color: baseMismatch ? const Color(0xFFBA1A1A) : null,
        ),
        title: Text(
          baseMismatch ? '你确定要恢复到这个状态吗' : '还原到“${snapshot.title}”？',
          style: baseMismatch
              ? const TextStyle(color: Color(0xFF8C1D18))
              : null,
        ),
        content: SizedBox(
          width: 440,
          child: Text(
            baseMismatch
                ? '该快照基准提交与当前提交不一致，可以正确恢复，但请确认你的行为。\n\n'
                      '当前未提交修改和未跟踪文件将被该快照替换。HEAD、分支和 stash 列表不会改变。'
                : '当前未提交修改和未跟踪文件将被该快照替换。HEAD、分支和 stash 列表不会改变。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: baseMismatch
                ? FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFBA1A1A),
                    foregroundColor: Colors.white,
                  )
                : null,
            child: const Text('确认还原'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _runBusy(() async {
      await _git.restoreSnapshot(snapshot);
      final repository = await _git.inspectRepository(snapshot.repositoryPath);
      if (!mounted) return;
      setState(() => _repository = repository);
      _showMessage('已还原到“${snapshot.title}”');
    });
  }

  Future<void> _renameSnapshot(Snapshot snapshot) async {
    final controller = TextEditingController(text: snapshot.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名快照'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 80,
            decoration: const InputDecoration(labelText: '名称'),
            onSubmitted: (value) => Navigator.pop(context, value.trim()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.isEmpty || title == snapshot.title) return;

    final snapshots = await _store.rename(snapshot.id, title);
    if (mounted) setState(() => _allSnapshots = snapshots);
  }

  Future<void> _deleteSnapshot(Snapshot snapshot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除快照记录？'),
        content: Text('“${snapshot.title}”将从列表中移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final snapshots = await _store.remove(snapshot.id);
    if (!mounted) return;
    setState(() {
      _allSnapshots = snapshots;
      _selectedId = null;
    });
  }

  Future<void> _copyHash(Snapshot snapshot) async {
    await Clipboard.setData(ClipboardData(text: snapshot.commitHash));
    _showMessage('已复制快照哈希');
  }

  Future<List<Snapshot>> _findUnavailableSnapshots() async {
    final results = await Future.wait(
      _snapshots.map((snapshot) async {
        final available = await _git.isSnapshotAvailable(snapshot);
        return available ? null : snapshot;
      }),
    );
    return results.whereType<Snapshot>().toList();
  }

  Future<void> _checkUnavailableSnapshots() async {
    await _runBusy(() async {
      final unavailable = await _findUnavailableSnapshots();
      if (!mounted) return;

      if (unavailable.isEmpty) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.check_circle_outline),
            title: const Text('所有快照均可用'),
            content: const Text('未发现被 Git GC 回收的快照。'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
        return;
      }

      final shouldDelete = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.error_outline, color: Color(0xFFBA1A1A)),
          title: Text('发现 ${unavailable.length} 个失效快照'),
          content: const SizedBox(
            width: 440,
            child: Text('这些快照的 Git 对象已被回收，无法再恢复。是否从列表中删除它们？'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('保留记录'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除失效记录'),
            ),
          ],
        ),
      );
      if (shouldDelete == true) await _removeSnapshots(unavailable);
    });
  }

  Future<void> _runGarbageCollection() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFFF1F0),
        icon: const Icon(Icons.warning_amber_rounded, color: Color(0xFFBA1A1A)),
        title: const Text(
          '确定要执行 Git GC 吗？',
          style: TextStyle(color: Color(0xFF8C1D18)),
        ),
        content: const SizedBox(
          width: 440,
          child: Text(
            '该操作会立即清理不可达的 Git 对象，可能使快照永久无法恢复。'
            '执行完成后，已被回收的快照记录会自动从列表删除。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFBA1A1A),
              foregroundColor: Colors.white,
            ),
            child: const Text('执行 GC'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _runBusy(() async {
      await _git.runGarbageCollection(_repository!.path);
      final unavailable = await _findUnavailableSnapshots();
      if (unavailable.isNotEmpty) await _removeSnapshots(unavailable);
      _showMessage('Git GC 已完成，删除了 ${unavailable.length} 个失效快照记录');
    });
  }

  Future<void> _removeSnapshots(List<Snapshot> snapshots) async {
    final removedIds = snapshots.map((item) => item.id).toSet();
    final remaining = await _store.removeMany(removedIds);
    if (!mounted) return;
    setState(() {
      _allSnapshots = remaining;
      if (removedIds.contains(_selectedId)) _selectedId = null;
    });
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      _setError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setError(Object error) {
    if (!mounted) return;
    final message = error is GitSnapshotException
        ? error.message
        : error.toString();
    setState(() => _error = message);
    _showMessage(message, error: true);
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error
              ? const Color(0xFF9D2B2B)
              : const Color(0xFF252824),
        ),
      );
  }

  Future<void> _showPluginInstaller() => showDialog<void>(
    context: context,
    builder: (context) => PluginInstallDialog(service: _pluginInstaller),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const WindowTitleBar(),
          Expanded(
            child: Row(
              children: [
                CheckpointSidebar(
                  repository: _repository,
                  recentRepositories: _recentRepositories,
                  snapshotCount: _snapshots.length,
                  mcpOnline: _mcpOnline,
                  mcpError: _mcpError,
                  onOpen: _pickRepository,
                  onSelectRecent: _openRepository,
                  onInstallPlugin: _showPluginInstaller,
                  onCopyMcpUrl: () async {
                    await Clipboard.setData(
                      const ClipboardData(text: McpSnapshotServer.url),
                    );
                    _showMessage('已复制 MCP 地址');
                  },
                ),
                Expanded(
                  child: _repository == null
                      ? EmptyRepositoryView(
                          onOpen: _pickRepository,
                          busy: _busy,
                          error: _error,
                        )
                      : RepositoryWorkspace(
                          repository: _repository!,
                          snapshots: _snapshots,
                          selectedSnapshot: _selectedSnapshot,
                          busy: _busy,
                          onRefresh: _refresh,
                          onCheckSnapshots: _checkUnavailableSnapshots,
                          onGarbageCollect: _runGarbageCollection,
                          onCreate: _createSnapshot,
                          onSelected: (snapshot) =>
                              setState(() => _selectedId = snapshot.id),
                          onRestore: _restoreSnapshot,
                          onRename: _renameSnapshot,
                          onDelete: _deleteSnapshot,
                          onCopyHash: _copyHash,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
