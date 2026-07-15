import 'package:flutter_test/flutter_test.dart';

import 'package:onfoot_app/main.dart';

void main() {
  testWidgets('OnFoot app builds', (WidgetTester tester) async {
    await tester.pumpWidget(const OnFootApp());

    expect(find.byType(OnFootApp), findsOneWidget);
  });
}
