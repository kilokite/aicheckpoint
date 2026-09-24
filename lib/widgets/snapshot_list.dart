import 'package:flutter/material.dart';

import '../models/snapshot.dart';
import '../models/snapshot_timeline.dart';

class SnapshotListPane extends StatefulWidget {
  const SnapshotListPane({
    super.key,
    required this.snapshots,
    this.timeline = const SnapshotTimeline(),
    this.repositoryPath,
    required this.selectedId,
    required this.busy,
    required this.onSelected,
    required this.onShowDiff,
    required this.onRestore,
    required this.onCreate,
  });

  final List<Snapshot> snapshots;
  final SnapshotTimeline timeline;
  final String? repositoryPath;
  final String? selectedId;
  final bool busy;
  final ValueChanged<Snapshot> onSelected;
  final ValueChanged<Snapshot> onShowDiff;
  final ValueChanged<Snapshot> onRestore;
  final VoidCallback onCreate;

  @override
  State<SnapshotListPane> createState() => _SnapshotListPaneState();
}

class _SnapshotListPaneState extends State<SnapshotListPane> {
  double _trajectoryFraction = 0.18;

  @override
  Widget build(BuildContext context) {
    final snapshots = widget.snapshots;
    if (snapshots.isEmpty) return _EmptySnapshots(onCreate: widget.onCreate);
    final path = widget.repositoryPath ?? snapshots.first.repositoryPath;
    final pointer = widget.timeline.pointerFor(path);
    final active = widget.timeline.ancestryFor(path, snapshots);
    final indices = {
      for (var index = 0; index < snapshots.length; index++)
        snapshots[index].id: index,
    };
    final oldestActive = active
        .map((id) => indices[id]!)
        .fold<int>(
          -1,
          (previous, index) => index > previous ? index : previous,
        );
    final firstActive = active
        .map((id) => indices[id]!)
        .fold<int>(
          snapshots.length,
          (previous, index) => index < previous ? index : previous,
        );
    final move = widget.timeline.lastRestoreFor(path);
    final restore =
        move != null &&
            indices.containsKey(move.fromId) &&
            indices.containsKey(move.toId)
        ? (indices[move.fromId]!, indices[move.toId]!)
        : null;
    final branches = <(int, int)>[
      for (var index = 0; index < snapshots.length; index++)
        if (snapshots[index].fromRestore &&
            indices.containsKey(snapshots[index].parentId))
          (indices[snapshots[index].parentId]!, index),
    ];
    final routes = _assignRoutes(restore, branches);
    final laneCount = routes.fold<int>(
      0,
      (count, route) => route.lane + 1 > count ? route.lane + 1 : count,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final minimumWidth = 64.0 + (laneCount - 1).clamp(0, 100) * 22;
        final maximumWidth = (constraints.maxWidth - 260).clamp(
          minimumWidth,
          constraints.maxWidth,
        );
        final trajectoryWidth = (_trajectoryFraction * constraints.maxWidth)
            .clamp(minimumWidth, maximumWidth);
        return Stack(
          children: [
            ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: snapshots.length,
              itemBuilder: (context, index) {
                final snapshot = snapshots[index];
                return Container(
                  height: 85,
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFEDEEEA)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Tooltip(
                        message: snapshot.id == pointer
                            ? '上次由 Checkpoint 创建或恢复到此处；不保证工作区未被外部修改'
                            : active.contains(snapshot.id)
                            ? '当前轨迹上的快照'
                            : index <= oldestActive
                            ? '已被当前轨迹跨过，仍可恢复'
                            : '轨迹记录之前的快照',
                        child: SizedBox(
                          key: const Key('trajectory-area'),
                          width: trajectoryWidth,
                          height: 85,
                          child: CustomPaint(
                            painter: _TrajectoryPainter(
                              index: index,
                              active: active.contains(snapshot.id),
                              skipped:
                                  index <= oldestActive &&
                                  !active.contains(snapshot.id),
                              firstActive: firstActive,
                              lastActive: oldestActive,
                              pointer: snapshot.id == pointer,
                              routes: routes,
                              laneCount: laneCount,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: _SnapshotRow(
                          snapshot: snapshot,
                          selected: snapshot.id == widget.selectedId,
                          pointer: snapshot.id == pointer,
                          skipped:
                              index <= oldestActive &&
                              !active.contains(snapshot.id),
                          busy: widget.busy,
                          onTap: () => widget.onSelected(snapshot),
                          onShowDiff: () => widget.onShowDiff(snapshot),
                          onRestore: () => widget.onRestore(snapshot),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            Positioned(
              left: trajectoryWidth - 5,
              top: 0,
              bottom: 0,
              child: Tooltip(
                message: '拖动调整轨迹宽度',
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: GestureDetector(
                    key: const Key('trajectory-divider'),
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (details) => setState(() {
                      _trajectoryFraction =
                          (trajectoryWidth + details.delta.dx) /
                          constraints.maxWidth;
                    }),
                    child: SizedBox(
                      width: 10,
                      child: Center(
                        child: Container(
                          width: 2,
                          color: const Color(0xFFD8DED8),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TrackRoute {
  const _TrackRoute(this.start, this.end, this.lane, this.color);

  final int start;
  final int end;
  final int lane;
  final Color color;
}

List<_TrackRoute> _assignRoutes(
  (int, int)? restore,
  List<(int, int)> branches,
) {
  final routes = <_TrackRoute>[];
  if (restore != null && restore.$1 != restore.$2) {
    routes.add(_TrackRoute(restore.$1, restore.$2, 0, const Color(0xFFC3473E)));
  }
  final laneEnds = <int>[];
  final ordered = [...branches]
    ..sort(
      (a, b) =>
          (a.$1 < a.$2 ? a.$1 : a.$2).compareTo(b.$1 < b.$2 ? b.$1 : b.$2),
    );
  for (final (start, end) in ordered) {
    if (start == end) continue;
    final first = start < end ? start : end;
    final last = start > end ? start : end;
    var lane = laneEnds.indexWhere((lastEnd) => lastEnd < first);
    if (lane < 0) {
      lane = laneEnds.length;
      laneEnds.add(last);
    } else {
      laneEnds[lane] = last;
    }
    routes.add(
      _TrackRoute(
        start,
        end,
        lane + (restore == null ? 0 : 1),
        const Color(0xFF3779BE),
      ),
    );
  }
  return routes;
}

class _TrajectoryPainter extends CustomPainter {
  const _TrajectoryPainter({
    required this.index,
    required this.active,
    required this.skipped,
    required this.firstActive,
    required this.lastActive,
    required this.pointer,
    required this.routes,
    required this.laneCount,
  });

  final int index;
  final bool active;
  final bool skipped;
  final int firstActive;
  final int lastActive;
  final bool pointer;
  final List<_TrackRoute> routes;
  final int laneCount;

  @override
  void paint(Canvas canvas, Size size) {
    const center = 42.5;
    if (skipped || (index >= firstActive && index <= lastActive)) {
      final paint = Paint()
        ..color = skipped ? const Color(0xFFB8BDB6) : const Color(0xFF16855B)
        ..strokeWidth = 2;
      final top = index == firstActive && firstActive == 0 ? center : 0.0;
      final bottom = index == lastActive ? center : size.height;
      if (skipped) {
        for (var position = top; position < bottom; position += 9) {
          canvas.drawLine(
            Offset(14, position),
            Offset(14, (position + 5).clamp(top, bottom)),
            paint,
          );
        }
      } else {
        canvas.drawLine(Offset(14, top), Offset(14, bottom), paint);
      }
    }

    for (final route in routes) {
      final lane = laneCount == 1
          ? 44.0
          : 44 + route.lane * (size.width - 60) / (laneCount - 1);
      _drawMove(canvas, size, route, lane);
    }

    final dot = Paint()
      ..color = pointer
          ? const Color(0xFF16855B)
          : active
          ? const Color(0xFF80B49A)
          : const Color(0xFFC8CCC6);
    canvas.drawCircle(const Offset(14, center), pointer ? 6 : 4, dot);
    if (pointer) {
      canvas.drawCircle(
        const Offset(14, center),
        2,
        Paint()..color = Colors.white,
      );
    }
  }

  void _drawMove(Canvas canvas, Size size, _TrackRoute route, double lane) {
    final start = route.start;
    final end = route.end;
    if (start == end ||
        index < (start < end ? start : end) ||
        index > (start > end ? start : end)) {
      return;
    }
    final paint = Paint()
      ..color = route.color
      ..strokeWidth = 2;
    final top = index == start || index == end ? 42.5 : 0.0;
    final bottom = index == start || index == end ? 42.5 : size.height;
    if (index == start) {
      final edge = start < end ? size.height : 0.0;
      canvas.drawLine(Offset(lane, 42.5), Offset(lane, edge), paint);
      canvas.drawCircle(Offset(lane, 42.5), 3, Paint()..color = route.color);
    } else if (index == end) {
      final edge = start < end ? 0.0 : size.height;
      canvas.drawLine(Offset(lane, edge), Offset(lane, 42.5), paint);
      canvas.drawLine(Offset(lane, 42.5), Offset(lane + 8, 42.5), paint);
      canvas.drawLine(Offset(lane + 8, 42.5), Offset(lane + 3, 38.5), paint);
      canvas.drawLine(Offset(lane + 8, 42.5), Offset(lane + 3, 46.5), paint);
    } else {
      canvas.drawLine(Offset(lane, top), Offset(lane, bottom), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TrajectoryPainter oldDelegate) => true;
}

class _SnapshotRow extends StatelessWidget {
  const _SnapshotRow({
    required this.snapshot,
    required this.selected,
    required this.pointer,
    required this.skipped,
    required this.busy,
    required this.onTap,
    required this.onShowDiff,
    required this.onRestore,
  });

  final Snapshot snapshot;
  final bool selected;
  final bool pointer;
  final bool skipped;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onShowDiff;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? const Color(0xFFE8F3ED) : Colors.transparent,
    child: ListTile(
      onTap: onTap,
      selected: selected,
      selectedColor: const Color(0xFF16855B),
      selectedTileColor: const Color(0xFFE8F3ED),
      contentPadding: const EdgeInsets.only(left: 6, right: 18),
      minTileHeight: 84,
      title: Row(
        children: [
          Flexible(
            child: Text(
              snapshot.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected
                    ? const Color(0xFF155F45)
                    : const Color(0xFF272A26),
              ),
            ),
          ),
          if (pointer || skipped) ...[
            const SizedBox(width: 8),
            Text(
              pointer ? '指针' : '已跳过',
              style: TextStyle(
                fontSize: 10,
                color: pointer
                    ? const Color(0xFF16855B)
                    : const Color(0xFF858A82),
              ),
            ),
          ],
        ],
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
        width: 176,
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
              onPressed: busy ? null : onShowDiff,
              tooltip: '查看 Diff',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.difference_outlined, size: 19),
            ),
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

String _formatDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}
