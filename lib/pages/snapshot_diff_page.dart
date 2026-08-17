import 'dart:async';

import 'package:flutter/material.dart';

import '../models/snapshot.dart';
import '../models/snapshot_diff.dart';
import '../services/snapshot_diff_service.dart';
import '../widgets/window_title_bar.dart';

class SnapshotDiffPage extends StatefulWidget {
  const SnapshotDiffPage({
    super.key,
    required this.snapshot,
    required this.previousSnapshot,
    required this.service,
  });

  final Snapshot snapshot;
  final Snapshot? previousSnapshot;
  final SnapshotDiffService service;

  @override
  State<SnapshotDiffPage> createState() => _SnapshotDiffPageState();
}

class _SnapshotDiffPageState extends State<SnapshotDiffPage> {
  late SnapshotDiffMode _mode;
  SnapshotDiffSession? _session;
  SnapshotDiffFile? _selectedFile;
  String? _patch;
  String? _error;
  String? _patchError;
  bool _loading = true;
  bool _patchLoading = false;
  int _loadGeneration = 0;
  int _patchGeneration = 0;
  final _verticalController = ScrollController();
  final _horizontalController = ScrollController();

  @override
  void initState() {
    super.initState();
    _mode = widget.previousSnapshot == null
        ? SnapshotDiffMode.currentWorkspace
        : SnapshotDiffMode.previousSnapshot;
    unawaited(_reload());
  }

  @override
  void dispose() {
    _loadGeneration++;
    _patchGeneration++;
    final session = _session;
    if (session != null) unawaited(session.dispose());
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final generation = ++_loadGeneration;
    _patchGeneration++;
    final oldSession = _session;
    setState(() {
      _loading = true;
      _error = null;
      _patchError = null;
      _session = null;
      _selectedFile = null;
      _patch = null;
    });
    if (oldSession != null) await oldSession.dispose();

    try {
      final session = switch (_mode) {
        SnapshotDiffMode.currentWorkspace =>
          await widget.service.compareWithCurrentWorkspace(widget.snapshot),
        SnapshotDiffMode.previousSnapshot =>
          await widget.service.compareWithPreviousSnapshot(
            snapshot: widget.snapshot,
            previousSnapshot: widget.previousSnapshot!,
          ),
      };
      if (!mounted || generation != _loadGeneration) {
        await session.dispose();
        return;
      }
      setState(() {
        _session = session;
        _loading = false;
      });
      if (session.files.isNotEmpty) {
        await _selectFile(session.files.first);
      }
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = _messageFor(error);
      });
    }
  }

  Future<void> _selectFile(SnapshotDiffFile file) async {
    final session = _session;
    if (session == null) return;
    final generation = ++_patchGeneration;
    setState(() {
      _selectedFile = file;
      _patchLoading = true;
      _patchError = null;
      _patch = null;
    });
    try {
      final patch = await session.loadPatch(file);
      if (!mounted || generation != _patchGeneration) return;
      setState(() {
        _patch = patch;
        _patchLoading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _patchGeneration) return;
        if (_verticalController.hasClients) _verticalController.jumpTo(0);
        if (_horizontalController.hasClients) _horizontalController.jumpTo(0);
      });
    } catch (error) {
      if (!mounted || generation != _patchGeneration) return;
      setState(() {
        _patchLoading = false;
        _patchError = _messageFor(error);
      });
    }
  }

  void _changeMode(Set<SnapshotDiffMode> selection) {
    final mode = selection.firstOrNull;
    if (mode == null || mode == _mode) return;
    setState(() => _mode = mode);
    unawaited(_reload());
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF16855B);
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
      surface: const Color(0xFF1B1E1A),
    );
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF141613),
      fontFamily: 'Microsoft YaHei UI',
      dividerColor: const Color(0xFF363A35),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 350),
      ),
    );
    return Theme(
      data: theme,
      child: Builder(
        builder: (context) => Scaffold(
          key: const Key('snapshot-diff-page'),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const WindowTitleBar(),
              _buildHeader(context),
              const Divider(height: 1),
              Expanded(child: _buildContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: SizedBox(
      key: const Key('snapshot-diff-toolbar'),
      height: 48,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              tooltip: '返回快照列表',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_back, size: 20),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.difference_outlined,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                widget.snapshot.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            SegmentedButton<SnapshotDiffMode>(
              segments: [
                const ButtonSegment(
                  value: SnapshotDiffMode.currentWorkspace,
                  label: Text('当前工作区'),
                  icon: Icon(Icons.folder_open_outlined, size: 16),
                ),
                ButtonSegment(
                  value: SnapshotDiffMode.previousSnapshot,
                  label: const Text('上一个检查点'),
                  icon: const Icon(Icons.bookmarks_outlined, size: 16),
                  enabled: widget.previousSnapshot != null,
                ),
              ],
              selected: {_mode},
              showSelectedIcon: false,
              onSelectionChanged: _changeMode,
              style: const ButtonStyle(
                visualDensity: VisualDensity(horizontal: -2, vertical: -2),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: _loading ? null : () => unawaited(_reload()),
              tooltip: '重新生成 Diff',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.refresh, size: 19),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildContent() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text('正在生成文件树并计算差异……'),
          ],
        ),
      );
    }
    if (_error case final error?) {
      return _ErrorView(message: error, onRetry: () => unawaited(_reload()));
    }
    final session = _session;
    if (session == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ComparisonSummary(session: session),
        const Divider(height: 1),
        Expanded(
          child: session.files.isEmpty
              ? const _EmptyDiffView()
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 292,
                      child: _FileList(
                        files: session.files,
                        selectedFile: _selectedFile,
                        onSelected: (file) => unawaited(_selectFile(file)),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: _buildPatch()),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildPatch() {
    if (_patchLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_patchError case final error?) {
      return _ErrorView(
        message: error,
        onRetry: _selectedFile == null
            ? null
            : () => unawaited(_selectFile(_selectedFile!)),
      );
    }
    final patch = _patch;
    if (patch == null) {
      return const Center(child: Text('选择一个文件查看详细差异'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 34,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          color: const Color(0xFF20231F),
          child: Text(
            _selectedFile?.displayPath ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFD7DAD5),
              fontSize: 11,
              fontFamily: 'Consolas',
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ColoredBox(
            color: const Color(0xFF0E100E),
            child: Scrollbar(
              controller: _verticalController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _verticalController,
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  controller: _horizontalController,
                  scrollDirection: Axis.horizontal,
                  child: SelectableText.rich(
                    TextSpan(children: _patchSpans(patch)),
                    style: const TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 12,
                      height: 1.5,
                      color: Color(0xFFD8DEE9),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<InlineSpan> _patchSpans(String patch) => patch
      .split('\n')
      .map((line) {
        final TextStyle style;
        if (line.startsWith('@@')) {
          style = const TextStyle(
            color: Color(0xFF9CDCFE),
            backgroundColor: Color(0xFF0D2A43),
          );
        } else if (line.startsWith('+') && !line.startsWith('+++')) {
          style = const TextStyle(
            color: Color(0xFF85E89D),
            backgroundColor: Color(0xFF102A19),
          );
        } else if (line.startsWith('-') && !line.startsWith('---')) {
          style = const TextStyle(
            color: Color(0xFFFFA198),
            backgroundColor: Color(0xFF35171B),
          );
        } else if (line.startsWith('diff --git') || line.startsWith('index ')) {
          style = const TextStyle(
            color: Color(0xFFF0F6FC),
            fontWeight: FontWeight.w700,
          );
        } else if (line.startsWith('+++') || line.startsWith('---')) {
          style = const TextStyle(color: Color(0xFFFFD866));
        } else {
          style = const TextStyle();
        }
        return TextSpan(text: '$line\n', style: style);
      })
      .toList(growable: false);

  String _messageFor(Object error) => switch (error) {
    SnapshotDiffException diff => diff.message,
    _ => error.toString(),
  };
}

class _ComparisonSummary extends StatelessWidget {
  const _ComparisonSummary({required this.session});

  final SnapshotDiffSession session;

  @override
  Widget build(BuildContext context) {
    final previous = session.previousSnapshot;
    final scheme = Theme.of(context).colorScheme;
    final source = session.mode == SnapshotDiffMode.currentWorkspace
        ? '当前工作区'
        : previous!.title;
    final crossBranch =
        previous != null && previous.branch != session.selectedSnapshot.branch;
    return Material(
      color: scheme.surfaceContainerLow,
      child: SizedBox(
        height: 38,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        source,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Icons.arrow_forward,
                        size: 14,
                        color: scheme.primary,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        session.selectedSnapshot.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (crossBranch) ...[
                      const SizedBox(width: 10),
                      const Tooltip(
                        message: '两个检查点来自不同分支，差异可能较大。',
                        child: Icon(
                          Icons.warning_amber_rounded,
                          size: 17,
                          color: Color(0xFFE29735),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                '${session.files.length} 个文件',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 14),
              Text(
                '+${session.insertions}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF72C997),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '-${session.deletions}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE58B86),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileList extends StatelessWidget {
  const _FileList({
    required this.files,
    required this.selectedFile,
    required this.onSelected,
  });

  final List<SnapshotDiffFile> files;
  final SnapshotDiffFile? selectedFile;
  final ValueChanged<SnapshotDiffFile> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: ListView.separated(
        itemCount: files.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final file = files[index];
          final selected = identical(file, selectedFile);
          return Material(
            color: selected ? scheme.secondaryContainer : Colors.transparent,
            child: InkWell(
              onTap: () => onSelected(file),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 11,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SnapshotDiffStatusBadge(status: file.status),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.displayPath,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: selected
                                  ? scheme.onSecondaryContainer
                                  : scheme.onSurface,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            file.isBinary
                                ? '二进制文件'
                                : '+${file.insertions}  -${file.deletions}',
                            style: TextStyle(
                              fontSize: 10,
                              color: selected
                                  ? scheme.onSecondaryContainer.withValues(
                                      alpha: 0.72,
                                    )
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class SnapshotDiffStatusBadge extends StatelessWidget {
  const SnapshotDiffStatusBadge({super.key, required this.status});

  final SnapshotDiffStatus status;

  @override
  Widget build(BuildContext context) {
    final style = _statusStyle(status);
    return Tooltip(
      message: style.description,
      waitDuration: const Duration(milliseconds: 350),
      child: Container(
        width: 24,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: style.color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          style.label,
          style: TextStyle(
            color: style.color,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _EmptyDiffView extends StatelessWidget {
  const _EmptyDiffView();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, size: 42, color: scheme.primary),
          const SizedBox(height: 14),
          const Text('文件内容完全一致', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text(
            '当前比较的两个状态之间没有内容差异。',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 38, color: scheme.error),
            const SizedBox(height: 14),
            SelectableText(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

({String label, String description, Color color}) _statusStyle(
  SnapshotDiffStatus status,
) => switch (status) {
  SnapshotDiffStatus.added => (
    label: 'A',
    description: '新增',
    color: const Color(0xFF72C997),
  ),
  SnapshotDiffStatus.modified => (
    label: 'M',
    description: '修改',
    color: const Color(0xFFE6B566),
  ),
  SnapshotDiffStatus.deleted => (
    label: 'D',
    description: '删除',
    color: const Color(0xFFE58B86),
  ),
  SnapshotDiffStatus.renamed => (
    label: 'R',
    description: '重命名',
    color: const Color(0xFFB9A4E3),
  ),
  SnapshotDiffStatus.copied => (
    label: 'C',
    description: '复制',
    color: const Color(0xFF85B5D8),
  ),
  SnapshotDiffStatus.typeChanged => (
    label: 'T',
    description: '类型变更',
    color: const Color(0xFFD8A36E),
  ),
  SnapshotDiffStatus.unmerged => (
    label: 'U',
    description: '存在冲突',
    color: const Color(0xFFE58B86),
  ),
  SnapshotDiffStatus.unknown => (
    label: '?',
    description: '未知状态',
    color: const Color(0xFF9DA29A),
  ),
};
