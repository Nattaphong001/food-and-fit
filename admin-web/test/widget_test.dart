import 'package:flutter_test/flutter_test.dart';

import 'package:myapp_admin/main.dart';

void main() {
  testWidgets('App boots to AuthGate without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();
    expect(find.byType(AuthGate), findsOneWidget);
  });
}
