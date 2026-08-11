import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import 'models/snapshot.dart';
import 'services/git_snapshot_service.dart';
import 'services/mcp_snapshot_server.dart';
import 'services/plugin_install_service.dart';
import 'services/snapshot_store.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(1280, 720),
    minimumSize: Size(900, 560),
    center: true,
    title: 'Checkpoint',
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  final argumentPath = arguments
      .where((item) => !item.startsWith('-'))
      .firstOrNull;
  runApp(
    CheckpointApp(
      initialPath: argumentPath ?? Directory.current.path,
      silentInitialFailure: argumentPath == null,
    ),
  );
}

class CheckpointApp extends StatelessWidget {
  const CheckpointApp({
    super.key,
    this.initialPath,
    this.silentInitialFailure = false,
    this.enableMcp = true,
  });

  final String? initialPath;
  final bool silentInitialFailure;
  final bool enableMcp;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF16855B);
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
      surface: const Color(0xFFF7F7F5),
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Checkpoint',
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFFF7F7F5),
        fontFamily: 'Microsoft YaHei UI',
        dividerColor: const Color(0xFFE3E3DE),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
        dialogTheme: const DialogThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
        tooltipTheme: const TooltipThemeData(
          waitDuration: Duration(milliseconds: 450),
        ),
      ),
      home: CheckpointHome(
        initialPath: initialPath,
        silentInitialFailure: silentInitialFailure,
        enableMcp: enableMcp,
      ),
    );
  }
}

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
    builder: (context) => _PluginInstallDialog(service: _pluginInstaller),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const _WindowTitleBar(),
          Expanded(
            child: Row(
              children: [
                _Sidebar(
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
                      ? _EmptyView(
                          onOpen: _pickRepository,
                          busy: _busy,
                          error: _error,
                        )
                      : _buildWorkspace(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkspace() {
    final repository = _repository!;
    final snapshots = _snapshots;
    return Column(
      children: [
        _RepositoryHeader(
          repository: repository,
          busy: _busy,
          onRefresh: _refresh,
          onCheckSnapshots: _checkUnavailableSnapshots,
          onGarbageCollect: _runGarbageCollection,
          onCreate: _createSnapshot,
        ),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final selected = _selectedSnapshot;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _SnapshotList(
                      snapshots: snapshots,
                      selectedId: selected?.id,
                      busy: _busy,
                      onSelected: (snapshot) =>
                          setState(() => _selectedId = snapshot.id),
                      onRestore: _restoreSnapshot,
                      onCreate: _createSnapshot,
                    ),
                  ),
                  if (constraints.maxWidth >= 830)
                    SizedBox(
                      width: 330,
                      child: _SnapshotDetails(
                        snapshot: selected,
                        busy: _busy,
                        onRestore: _restoreSnapshot,
                        onRename: _renameSnapshot,
                        onDelete: _deleteSnapshot,
                        onCopyHash: _copyHash,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _WindowTitleBar extends StatelessWidget {
  const _WindowTitleBar();

  @override
  Widget build(BuildContext context) => Container(
    height: 38,
    color: const Color(0xFF20231F),
    child: Row(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
            child: const DragToMoveArea(
              child: Padding(
                padding: EdgeInsets.only(left: 14),
                child: Row(
                  children: [
                    Icon(
                      Icons.bookmark_rounded,
                      color: Color(0xFF58C994),
                      size: 17,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Checkpoint',
                      style: TextStyle(
                        color: Color(0xFFD7DAD5),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _WindowButton(
          tooltip: '最小化',
          icon: Icons.remove,
          onPressed: windowManager.minimize,
        ),
        _WindowButton(
          tooltip: '最大化',
          icon: Icons.crop_square,
          onPressed: () async {
            if (await windowManager.isMaximized()) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          },
        ),
        _WindowButton(
          tooltip: '关闭',
          icon: Icons.close,
          closeButton: true,
          onPressed: windowManager.close,
        ),
      ],
    ),
  );
}

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.closeButton = false,
  });

  final String tooltip;
  final IconData icon;
  final Future<void> Function() onPressed;
  final bool closeButton;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: widget.tooltip,
    child: MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onPressed,
        child: SizedBox(
          width: 48,
          height: 38,
          child: ColoredBox(
            color: _hovered
                ? widget.closeButton
                      ? const Color(0xFFC42B1C)
                      : const Color(0xFF363A35)
                : Colors.transparent,
            child: Icon(widget.icon, size: 16, color: const Color(0xFFD7DAD5)),
          ),
        ),
      ),
    ),
  );
}

class _PluginInstallDialog extends StatefulWidget {
  const _PluginInstallDialog({required this.service});

  final PluginInstallService service;

  @override
  State<_PluginInstallDialog> createState() => _PluginInstallDialogState();
}

class _PluginInstallDialogState extends State<_PluginInstallDialog> {
  bool _busy = false;
  String? _status;
  String? _error;
  Directory? _exportDirectory;
  String? _installPrompt;

  Future<void> _installDirect() async {
    await _run(() async {
      final result = await widget.service.installDirect();
      if (!mounted) return;
      setState(() {
        _status = '插件已安装到 ${result.pluginDirectory.path}。重启 Codex 后生效。';
        _exportDirectory = null;
        _installPrompt = null;
      });
    });
  }

  Future<void> _export() async {
    await _run(() async {
      final result = await widget.service.exportForCodex();
      if (!mounted) return;
      setState(() {
        _exportDirectory = result.pluginDirectory;
        _installPrompt = widget.service.buildInstallPrompt(
          result.pluginDirectory,
        );
        _status = '插件源码已导出，可把下面的提示词交给 Codex。';
      });
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyPrompt() async {
    final prompt = _installPrompt;
    if (prompt == null) return;
    await Clipboard.setData(ClipboardData(text: prompt));
    if (mounted) setState(() => _status = '安装提示词已复制。');
  }

  Future<void> _openExportDirectory() async {
    final directory = _exportDirectory;
    if (directory == null) return;
    try {
      await Process.start('explorer.exe', [directory.path]);
    } catch (error) {
      if (mounted) setState(() => _error = '无法打开目录：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.extension_outlined, size: 22),
          SizedBox(width: 10),
          Text('安装 Codex 插件'),
        ],
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '直接安装',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 5),
              const Text(
                '复制插件到当前用户的 personal marketplace 并启用。不会覆盖其他插件配置。',
                style: TextStyle(fontSize: 12, color: Color(0xFF666B64)),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  key: const Key('install-plugin-direct'),
                  onPressed: _busy ? null : _installDirect,
                  icon: const Icon(Icons.install_desktop, size: 19),
                  label: const Text('直接安装到 Codex'),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Divider(height: 1),
              ),
              const Text(
                '让 Codex 安装',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 5),
              const Text(
                '把插件源码导出到应用数据目录，再生成一段带绝对路径的安装提示词。',
                style: TextStyle(fontSize: 12, color: Color(0xFF666B64)),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const Key('export-plugin-for-codex'),
                  onPressed: _busy ? null : _export,
                  icon: const Icon(Icons.folder_copy_outlined, size: 19),
                  label: const Text('导出并生成提示词'),
                ),
              ),
              if (_installPrompt case final prompt?) ...[
                const SizedBox(height: 14),
                Container(
                  constraints: const BoxConstraints(maxHeight: 150),
                  padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F1EE),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: SelectableText(
                            prompt,
                            style: const TextStyle(fontSize: 12, height: 1.45),
                          ),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: _copyPrompt,
                            tooltip: '复制安装提示词',
                            icon: const Icon(Icons.copy, size: 18),
                          ),
                          IconButton(
                            onPressed: _openExportDirectory,
                            tooltip: '打开插件目录',
                            icon: const Icon(Icons.folder_open, size: 18),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              if (_busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(minHeight: 2),
              ],
              if (_status case final status?) ...[
                const SizedBox(height: 14),
                Text(
                  status,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF16855B),
                  ),
                ),
              ],
              if (_error case final error?) ...[
                const SizedBox(height: 14),
                Text(
                  error,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9D2B2B),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.repository,
    required this.recentRepositories,
    required this.snapshotCount,
    required this.mcpOnline,
    required this.mcpError,
    required this.onOpen,
    required this.onSelectRecent,
    required this.onInstallPlugin,
    required this.onCopyMcpUrl,
  });

  final RepositoryInfo? repository;
  final List<String> recentRepositories;
  final int snapshotCount;
  final bool mcpOnline;
  final String? mcpError;
  final VoidCallback onOpen;
  final ValueChanged<String> onSelectRecent;
  final VoidCallback onInstallPlugin;
  final VoidCallback onCopyMcpUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 248,
      color: const Color(0xFF20231F),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 24, 12, 0),
              child: OutlinedButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('打开目录'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF4C504A)),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 15,
                  ),
                ),
              ),
            ),
            if (repository != null) ...[
              const SizedBox(height: 22),
              const _SidebarLabel('当前仓库'),
              _RepositoryTile(
                path: repository!.path,
                selected: true,
                trailing: snapshotCount.toString(),
                onTap: () {},
              ),
            ],
            if (recentRepositories.isNotEmpty) ...[
              const SizedBox(height: 22),
              const _SidebarLabel('最近打开'),
              for (final path in recentRepositories)
                if (repository == null ||
                    p.normalize(path) != p.normalize(repository!.path))
                  _RepositoryTile(
                    path: path,
                    onTap: () => onSelectRecent(path),
                  ),
            ],
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextButton.icon(
                onPressed: onInstallPlugin,
                icon: const Icon(Icons.extension_outlined, size: 18),
                label: const Text('安装 Codex 插件'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFD7DAD5),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 13,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 8, 14),
              child: Tooltip(
                message: mcpError ?? '复制 MCP 地址',
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: mcpOnline
                            ? const Color(0xFF58C994)
                            : const Color(0xFFCC655C),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'MCP · 127.0.0.1:47173',
                        style: TextStyle(
                          color: Color(0xFFADB1AA),
                          fontSize: 11,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onCopyMcpUrl,
                      tooltip: '复制 MCP 地址',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.copy,
                        size: 15,
                        color: Color(0xFFADB1AA),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarLabel extends StatelessWidget {
  const _SidebarLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Color(0xFF8D928A),
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _RepositoryTile extends StatelessWidget {
  const _RepositoryTile({
    required this.path,
    required this.onTap,
    this.selected = false,
    this.trailing,
  });

  final String path;
  final VoidCallback onTap;
  final bool selected;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
    child: Material(
      color: selected ? const Color(0xFF30362F) : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.folder_outlined,
                size: 17,
                color: selected
                    ? const Color(0xFF58C994)
                    : const Color(0xFFADB1AA),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  p.basename(path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFFD0D3CD),
                    fontSize: 13,
                  ),
                ),
              ),
              if (trailing != null)
                Text(
                  trailing!,
                  style: const TextStyle(
                    color: Color(0xFF8D928A),
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _RepositoryHeader extends StatelessWidget {
  const _RepositoryHeader({
    required this.repository,
    required this.busy,
    required this.onRefresh,
    required this.onCheckSnapshots,
    required this.onGarbageCollect,
    required this.onCreate,
  });

  final RepositoryInfo repository;
  final bool busy;
  final VoidCallback onRefresh;
  final VoidCallback onCheckSnapshots;
  final VoidCallback onGarbageCollect;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Container(
    height: 86,
    padding: const EdgeInsets.symmetric(horizontal: 28),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: Color(0xFFE3E3DE))),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                repository.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF20231F),
                ),
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  const Icon(
                    Icons.account_tree_outlined,
                    size: 14,
                    color: Color(0xFF70766E),
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      repository.branch,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF60665E),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: repository.isDirty
                          ? const Color(0xFFE29735)
                          : const Color(0xFF27A56D),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    repository.isDirty
                        ? '${repository.changedFileCount} 个变更'
                        : '工作区干净',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF60665E),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Tooltip(
          message: '刷新仓库状态',
          child: IconButton(
            onPressed: busy ? null : onRefresh,
            icon: const Icon(Icons.refresh),
          ),
        ),
        Tooltip(
          message: '检查失效快照',
          child: IconButton(
            onPressed: busy ? null : onCheckSnapshots,
            icon: const Icon(Icons.fact_check_outlined),
          ),
        ),
        Tooltip(
          message: '执行 Git GC',
          child: IconButton(
            onPressed: busy ? null : onGarbageCollect,
            icon: const Icon(Icons.cleaning_services_outlined),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: busy ? null : onCreate,
          icon: const Icon(Icons.add, size: 19),
          label: const Text('创建快照'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          ),
        ),
      ],
    ),
  );
}

class _SnapshotList extends StatelessWidget {
  const _SnapshotList({
    required this.snapshots,
    required this.selectedId,
    required this.busy,
    required this.onSelected,
    required this.onRestore,
    required this.onCreate,
  });

  final List<Snapshot> snapshots;
  final String? selectedId;
  final bool busy;
  final ValueChanged<Snapshot> onSelected;
  final ValueChanged<Snapshot> onRestore;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    if (snapshots.isEmpty) {
      return _EmptySnapshots(onCreate: onCreate);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(top: 10, bottom: 24),
            itemCount: snapshots.length,
            separatorBuilder: (context, index) =>
                const Divider(height: 1, indent: 28, endIndent: 18),
            itemBuilder: (context, index) {
              final snapshot = snapshots[index];
              return _SnapshotRow(
                snapshot: snapshot,
                selected: snapshot.id == selectedId,
                busy: busy,
                onTap: () => onSelected(snapshot),
                onRestore: () => onRestore(snapshot),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SnapshotRow extends StatelessWidget {
  const _SnapshotRow({
    required this.snapshot,
    required this.selected,
    required this.busy,
    required this.onTap,
    required this.onRestore,
  });

  final Snapshot snapshot;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? const Color(0xFFE8F3ED) : Colors.transparent,
    child: ListTile(
      onTap: onTap,
      selected: selected,
      selectedColor: const Color(0xFF16855B),
      selectedTileColor: const Color(0xFFE8F3ED),
      contentPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 7),
      minTileHeight: 70,
      leading: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: _colorFromHash(snapshot.baseHash),
          shape: BoxShape.circle,
        ),
      ),
      title: Text(
        snapshot.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: selected ? const Color(0xFF155F45) : const Color(0xFF272A26),
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '${_formatDate(snapshot.createdAt)}  ·  ${snapshot.branch}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: Color(0xFF747A72)),
        ),
      ),
      trailing: SizedBox(
        width: 138,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                '${snapshot.fileCount} 文件  +${snapshot.insertions}  -${snapshot.deletions}',
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Color(0xFF747A72)),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              onPressed: busy ? null : onRestore,
              tooltip: '恢复快照',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.restore, size: 19),
            ),
          ],
        ),
      ),
    ),
  );
}

Color _colorFromHash(String hash) {
  final prefixLength = hash.length < 8 ? hash.length : 8;
  final seed = int.tryParse(hash.substring(0, prefixLength), radix: 16) ?? 0;
  return HSLColor.fromAHSL(1, (seed % 360).toDouble(), 0.58, 0.46).toColor();
}

class _SnapshotDetails extends StatelessWidget {
  const _SnapshotDetails({
    required this.snapshot,
    required this.busy,
    required this.onRestore,
    required this.onRename,
    required this.onDelete,
    required this.onCopyHash,
  });

  final Snapshot? snapshot;
  final bool busy;
  final ValueChanged<Snapshot> onRestore;
  final ValueChanged<Snapshot> onRename;
  final ValueChanged<Snapshot> onDelete;
  final ValueChanged<Snapshot> onCopyHash;

  @override
  Widget build(BuildContext context) {
    final item = snapshot;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: Color(0xFFE3E3DE))),
      ),
      child: item == null
          ? const Center(
              child: Text('未选择快照', style: TextStyle(color: Color(0xFF858A82))),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '快照详情',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF555B53),
                        ),
                      ),
                    ),
                    Tooltip(
                      message: '重命名',
                      child: IconButton(
                        onPressed: busy ? null : () => onRename(item),
                        icon: const Icon(Icons.edit_outlined, size: 19),
                      ),
                    ),
                    Tooltip(
                      message: '删除记录',
                      child: IconButton(
                        onPressed: busy ? null : () => onDelete(item),
                        icon: const Icon(Icons.delete_outline, size: 19),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF252824),
                  ),
                ),
                const SizedBox(height: 24),
                _DetailLine(label: '创建时间', value: _formatDate(item.createdAt)),
                _DetailLine(label: '所在分支', value: item.branch),
                _DetailLine(label: '基准提交', value: _shortHash(item.baseHash)),
                _DetailLine(label: '文件变化', value: '${item.fileCount} 个文件'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _Stat(
                      value: '+${item.insertions}',
                      color: const Color(0xFF16855B),
                    ),
                    const SizedBox(width: 8),
                    _Stat(
                      value: '-${item.deletions}',
                      color: const Color(0xFFB43A3A),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                const Text(
                  '对象哈希',
                  style: TextStyle(fontSize: 11, color: Color(0xFF777D75)),
                ),
                const SizedBox(height: 7),
                Container(
                  height: 38,
                  padding: const EdgeInsets.only(left: 11),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F3F0),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _shortHash(item.commitHash),
                          style: const TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Tooltip(
                        message: '复制完整哈希',
                        child: IconButton(
                          onPressed: () => onCopyHash(item),
                          icon: const Icon(Icons.copy, size: 16),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: busy ? null : () => onRestore(item),
                  icon: const Icon(Icons.history, size: 19),
                  label: const Text('还原到此快照'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ],
            ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 13),
    child: Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF777D75)),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12, color: Color(0xFF30332F)),
          ),
        ),
      ],
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.color});
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      value,
      style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
    ),
  );
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({
    required this.onOpen,
    required this.busy,
    required this.error,
  });
  final VoidCallback onOpen;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_open, size: 46, color: Color(0xFF9DA29A)),
            const SizedBox(height: 18),
            const Text(
              '尚未打开仓库',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF343833),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: busy ? null : onOpen,
              icon: const Icon(Icons.folder_open),
              label: const Text('打开目录'),
            ),
            if (error != null) ...[
              const SizedBox(height: 18),
              SizedBox(
                width: 460,
                child: Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF9D2B2B),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      if (busy) const LinearProgressIndicator(minHeight: 2),
    ],
  );
}

class _EmptySnapshots extends StatelessWidget {
  const _EmptySnapshots({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.bookmarks_outlined,
          size: 42,
          color: Color(0xFF9DA29A),
        ),
        const SizedBox(height: 16),
        const Text(
          '还没有快照',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF343833),
          ),
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: onCreate,
          icon: const Icon(Icons.add),
          label: const Text('创建第一个快照'),
        ),
      ],
    ),
  );
}

String _shortHash(String hash) =>
    hash.length > 12 ? hash.substring(0, 12) : hash;

String _formatDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}
