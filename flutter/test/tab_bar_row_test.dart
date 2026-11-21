import 'package:branchi/models/repo_tab.dart';
import 'package:branchi/widgets/tab_bar_row.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('middle-click closes a tab', (tester) async {
    int? closed;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TabBarRow(
          tabs: [RepoTab(id: 0, title: 'One'), RepoTab(id: 1, title: 'Two')],
          activeIndex: 0,
          onSelect: (_) {},
          onClose: (i) => closed = i,
          onAddTab: () {},
        ),
      ),
    ));
    await tester.tap(find.text('Two'), buttons: kMiddleMouseButton);
    await tester.pump();
    expect(closed, 1);
  });
}
