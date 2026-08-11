import 'package:checkpoint/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the Checkpoint shell', (tester) async {
    await tester.pumpWidget(const CheckpointApp(enableMcp: false));
    expect(find.text('Checkpoint'), findsOneWidget);
    expect(find.text('尚未打开仓库'), findsOneWidget);
    expect(find.text('安装 Codex 插件'), findsOneWidget);
  });

  testWidgets('offers both plugin installation methods', (tester) async {
    await tester.pumpWidget(const CheckpointApp(enableMcp: false));
    await tester.tap(find.text('安装 Codex 插件'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('install-plugin-direct')), findsOneWidget);
    expect(find.byKey(const Key('export-plugin-for-codex')), findsOneWidget);
  });
}
