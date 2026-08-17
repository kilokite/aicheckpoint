import 'package:flutter/material.dart';

import '../models/snapshot.dart';

class SnapshotDetailsPane extends StatelessWidget {
  const SnapshotDetailsPane({
    super.key,
    required this.snapshot,
    required this.busy,
    required this.onRestore,
    required this.onRename,
    required this.onDelete,
    required this.onCopyHash,
    required this.onShowDiff,
  });

  final Snapshot? snapshot;
  final bool busy;
  final ValueChanged<Snapshot> onRestore;
  final ValueChanged<Snapshot> onRename;
  final ValueChanged<Snapshot> onDelete;
  final ValueChanged<Snapshot> onCopyHash;
  final ValueChanged<Snapshot> onShowDiff;

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
                OutlinedButton.icon(
                  onPressed: busy ? null : () => onShowDiff(item),
                  icon: const Icon(Icons.difference_outlined, size: 19),
                  label: const Text('查看 Diff'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 10),
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

String _shortHash(String hash) =>
    hash.length > 12 ? hash.substring(0, 12) : hash;

String _formatDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}
