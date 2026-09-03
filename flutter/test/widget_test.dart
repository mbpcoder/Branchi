import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:branchi/main.dart';

void main() {
  testWidgets('App builds', (WidgetTester tester) async {
    await tester.pumpWidget(const BranchiApp());
    expect(find.byType(BranchiApp), findsOneWidget);
  });
}
