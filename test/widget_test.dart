import 'package:checkpoint/main.dart';
import 'package:checkpoint/models/snapshot.dart';
import 'package:checkpoint/models/snapshot_diff.dart';
import 'package:checkpoint/pages/snapshot_diff_page.dart';
import 'package:checkpoint/services/snapshot_diff_service.dart';
import 'package:checkpoint/widgets/snapshot_details.dart';
import 'package:checkpoint/widgets/snapshot_list.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the Checkpoint shell', (tester) async {
    await tester.pumpWidget(const CheckpointApp(enableMcp: false));
    expect(find.text('Checkpoint'), findsOneWidget);
    expect(find.text('尚未打开仓库'), findsOneWidget);
    expect(find.text('Coding Agent 插件'), findsOneWidget);
  });

  testWidgets('offers install actions grouped by coding agent', (tester) async {
    await tester.pumpWidget(const CheckpointApp(enableMcp: false));
    await tester.tap(find.text('Coding Agent 插件'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('install-plugin-direct')), findsOneWidget);
    expect(find.byKey(const Key('export-plugin-for-codex')), findsOneWidget);
    expect(find.byKey(const Key('install-pi-extension')), findsOneWidget);
  });

  testWidgets('snapshot details exposes the Diff preview action', (
    tester,
  ) async {
    final snapshot = Snapshot(
      id: 'snapshot-id',
      repositoryPath: r'C:\repo',
      commitHash: 'a' * 40,
      indexTreeHash: 'b' * 40,
      baseHash: 'c' * 40,
      branch: 'main',
      title: '测试快照',
      createdAt: DateTime(2026, 8, 17, 12),
      fileCount: 2,
      insertions: 3,
      deletions: 1,
    );
    var requested = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 330,
            height: 720,
            child: SnapshotDetailsPane(
              snapshot: snapshot,
              busy: false,
              onRestore: (_) {},
              onRename: (_) {},
              onDelete: (_) {},
              onCopyHash: (_) {},
              onShowDiff: (_) => requested = true,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('查看 Diff'));
    expect(requested, isTrue);
  });

  testWidgets('snapshot row opens Diff with one click', (tester) async {
    final snapshot = _snapshot(id: 'direct-diff', title: '直接查看');
    Snapshot? requested;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 720,
            height: 300,
            child: SnapshotListPane(
              snapshots: [snapshot],
              selectedId: null,
              busy: false,
              onSelected: (_) {},
              onShowDiff: (value) => requested = value,
              onRestore: (_) {},
              onCreate: () {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('查看 Diff'));
    expect(requested, same(snapshot));
  });

  testWidgets(
    'Diff page defaults to previous snapshot with a compact toolbar',
    (tester) async {
      final selected = _snapshot(id: 'selected', title: '选中的快照');
      final previous = _snapshot(id: 'previous', title: '上一个快照');

      await tester.pumpWidget(
        MaterialApp(
          home: SnapshotDiffPage(
            snapshot: selected,
            previousSnapshot: previous,
            service: _FailingDiffService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byKey(const Key('snapshot-diff-toolbar'))).height,
        48,
      );
      final pageContext = tester.element(
        find.byKey(const Key('snapshot-diff-page')),
      );
      expect(Theme.of(pageContext).brightness, Brightness.dark);

      final segmented = tester.widget<SegmentedButton<SnapshotDiffMode>>(
        find.byType(SegmentedButton<SnapshotDiffMode>),
      );
      expect(segmented.selected, {SnapshotDiffMode.previousSnapshot});
      expect(segmented.segments.last.enabled, isTrue);
    },
  );

  testWidgets('oldest snapshot falls back to current workspace comparison', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SnapshotDiffPage(
          snapshot: _snapshot(id: 'oldest', title: '最早快照'),
          previousSnapshot: null,
          service: _FailingDiffService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final segmented = tester.widget<SegmentedButton<SnapshotDiffMode>>(
      find.byType(SegmentedButton<SnapshotDiffMode>),
    );
    expect(segmented.selected, {SnapshotDiffMode.currentWorkspace});
    expect(segmented.segments.last.enabled, isFalse);
  });

  testWidgets('Diff status badges show Chinese descriptions on hover', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SnapshotDiffStatusBadge(status: SnapshotDiffStatus.added),
              SnapshotDiffStatusBadge(status: SnapshotDiffStatus.modified),
              SnapshotDiffStatusBadge(status: SnapshotDiffStatus.deleted),
              SnapshotDiffStatusBadge(status: SnapshotDiffStatus.renamed),
            ],
          ),
        ),
      ),
    );

    final messages = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .map((tooltip) => tooltip.message);
    expect(messages, containsAll(['新增', '修改', '删除', '重命名']));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.text('A')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('新增'), findsOneWidget);
    await mouse.removePointer();
  });
}

Snapshot _snapshot({required String id, required String title}) => Snapshot(
  id: id,
  repositoryPath: r'C:\repo',
  commitHash: 'a' * 40,
  indexTreeHash: 'b' * 40,
  baseHash: 'c' * 40,
  branch: 'main',
  title: title,
  createdAt: DateTime(2026, 8, 17, 12),
  fileCount: 2,
  insertions: 3,
  deletions: 1,
);

class _FailingDiffService extends SnapshotDiffService {
  @override
  Future<SnapshotDiffSession> compareWithCurrentWorkspace(Snapshot snapshot) =>
      Future.error(const SnapshotDiffException('测试终止加载'));

  @override
  Future<SnapshotDiffSession> compareWithPreviousSnapshot({
    required Snapshot snapshot,
    required Snapshot previousSnapshot,
  }) => Future.error(const SnapshotDiffException('测试终止加载'));
}
