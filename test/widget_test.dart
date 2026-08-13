import 'package:checkpoint/main.dart';
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
}
