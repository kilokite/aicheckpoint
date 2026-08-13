import 'package:flutter/material.dart';

import '../models/snapshot.dart';
import 'gc_status_indicator.dart';

class RepositoryHeader extends StatelessWidget {
  const RepositoryHeader({
    super.key,
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
        GcStatusIndicator(status: repository.gcStatus),
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
