import 'package:flutter/material.dart';

import '../models/snapshot.dart';

class SnapshotListPane extends StatelessWidget {
  const SnapshotListPane({
    super.key,
    required this.snapshots,
    required this.selectedId,
    required this.busy,
    required this.onSelected,
    required this.onShowDiff,
    required this.onRestore,
    required this.onCreate,
  });

  final List<Snapshot> snapshots;
  final String? selectedId;
  final bool busy;
  final ValueChanged<Snapshot> onSelected;
  final ValueChanged<Snapshot> onShowDiff;
  final ValueChanged<Snapshot> onRestore;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    if (snapshots.isEmpty) return _EmptySnapshots(onCreate: onCreate);
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
                onShowDiff: () => onShowDiff(snapshot),
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
    required this.onShowDiff,
    required this.onRestore,
  });

  final Snapshot snapshot;
  final bool selected;
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

Color _colorFromHash(String hash) {
  final prefixLength = hash.length < 8 ? hash.length : 8;
  final seed = int.tryParse(hash.substring(0, prefixLength), radix: 16) ?? 0;
  return HSLColor.fromAHSL(1, (seed % 360).toDouble(), 0.58, 0.46).toColor();
}

String _formatDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}
