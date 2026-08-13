import 'package:flutter/material.dart';

import '../models/gc_status.dart';

/// 显示仓库距离 Git 自动 GC 还有多远的小型进度指示器。
class GcStatusIndicator extends StatelessWidget {
  const GcStatusIndicator({super.key, required this.status});

  final GcStatus? status;

  @override
  Widget build(BuildContext context) {
    final status = this.status;
    final progress = status?.progress ?? 0.0;

    final Color color;
    if (status == null || status.autoGcDisabled) {
      color = const Color(0xFF9DA29A);
    } else if (status.exceeds) {
      color = const Color(0xFFBA1A1A);
    } else if (progress >= 0.7) {
      color = const Color(0xFFE29735);
    } else {
      color = const Color(0xFF27A56D);
    }

    final label = switch (status) {
      null => '—',
      final s when s.autoGcDisabled => '已禁用',
      final s => '${(s.progress * 100).round()}%',
    };

    return Tooltip(
      message: status?.tooltip ?? '尚未获取 Git GC 状态',
      child: Container(
        width: 150,
        margin: const EdgeInsets.only(left: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.auto_fix_high,
                  size: 13,
                  color: Color(0xFF70766E),
                ),
                const SizedBox(width: 5),
                const Expanded(
                  child: Text(
                    '距离自动 GC',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF70766E),
                    ),
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(2.5),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: const Color(0xFFE8E8E2),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
