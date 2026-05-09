import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:local_helper/main.dart';

void main() {
  testWidgets('shows Local Helper auth screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: AuthScreen()));

    expect(find.text('Local Helper'), findsOneWidget);
    expect(find.text('User'), findsOneWidget);
    expect(find.text('Worker'), findsOneWidget);
  });
}
