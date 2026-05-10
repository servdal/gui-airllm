import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_desktop/main.dart';

void main() {
  testWidgets('renders local coding app shell', (tester) async {
    await tester.pumpWidget(const LocalAiDesktopApp());

    expect(find.text('Coding Assistant'), findsOneWidget);
    expect(find.text('Git Actions'), findsOneWidget);
  });
}
