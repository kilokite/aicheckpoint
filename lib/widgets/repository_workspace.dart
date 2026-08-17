import 'package:flutter/material.dart';

import '../models/snapshot.dart';
import 'repository_header.dart';
import 'snapshot_details.dart';
import 'snapshot_list.dart';

class RepositoryWorkspace extends StatelessWidget {
  const RepositoryWorkspace({
    super.key,
    required this.repository,
    required this.snapshots,
    required this.selectedSnapshot,
    required this.busy,
    required this.onRefresh,
    required this.onCheckSnapshots,
    required this.onGarbageCollect,
    required this.onCreate,
    required this.onSelected,
    required this.onRestore,
    required this.onRename,
    required this.onDelete,
    required this.onCopyHash,
    required this.onShowDiff,
  });

  final RepositoryInfo repository;
  final List<Snapshot> snapshots;
  final Snapshot? selectedSnapshot;
  final bool busy;
  final VoidCallback onRefresh;
  final VoidCallback onCheckSnapshots;
  final VoidCallback onGarbageCollect;
  final VoidCallback onCreate;
  final ValueChanged<Snapshot> onSelected;
  final ValueChanged<Snapshot> onRestore;
  final ValueChanged<Snapshot> onRename;
  final ValueChanged<Snapshot> onDelete;
  final ValueChanged<Snapshot> onCopyHash;
  final ValueChanged<Snapshot> onShowDiff;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      RepositoryHeader(
        repository: repository,
        busy: busy,
        onRefresh: onRefresh,
        onCheckSnapshots: onCheckSnapshots,
        onGarbageCollect: onGarbageCollect,
        onCreate: onCreate,
      ),
      if (busy) const LinearProgressIndicator(minHeight: 2),
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SnapshotListPane(
                  snapshots: snapshots,
                  selectedId: selectedSnapshot?.id,
                  busy: busy,
                  onSelected: onSelected,
                  onShowDiff: onShowDiff,
                  onRestore: onRestore,
                  onCreate: onCreate,
                ),
              ),
              if (constraints.maxWidth >= 830)
                SizedBox(
                  width: 330,
                  child: SnapshotDetailsPane(
                    snapshot: selectedSnapshot,
                    busy: busy,
                    onRestore: onRestore,
                    onRename: onRename,
                    onDelete: onDelete,
                    onCopyHash: onCopyHash,
                    onShowDiff: onShowDiff,
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}

class EmptyRepositoryView extends StatelessWidget {
  const EmptyRepositoryView({
    super.key,
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
