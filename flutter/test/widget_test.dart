import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rustgit/main.dart';

void main() {
  testWidgets('App builds', (WidgetTester tester) async {
    await tester.pumpWidget(const RustGitApp());
    expect(find.byType(RustGitApp), findsOneWidget);
  });
}
