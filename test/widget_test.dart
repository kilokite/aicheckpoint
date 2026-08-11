import 'package:checkpoint/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the Checkpoint shell', (tester) async {
    await tester.pumpWidget(const CheckpointApp(enableMcp: false));
    expect(find.text('Checkpoint'), findsOneWidget);
    expect(find.text('尚未打开仓库'), findsOneWidget);
  });
}
