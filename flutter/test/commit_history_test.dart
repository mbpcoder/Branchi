import 'package:branchi/repo/commit_detail.dart';
import 'package:branchi/repo/commit_list.dart';
import 'package:branchi/repo/models.dart';
import 'package:branchi/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

CommitEntry _commit(String id, String summary) => CommitEntry(
      id: id.padRight(40, '0'),
      summary: summary,
      author: 'Test User',
      email: 'test@example.com',
      time: DateTime.utc(2026, 11, 20),
      parentIds: const [],
    );

DiffFileEntry _file(String path) => DiffFileEntry(
      path: path,
      status: FileChangeStatus.modified,
      additions: 1,
      deletions: 0,
      patch: '+line\n',
    );

Widget _app(Widget child) => MaterialApp(
      theme: AppTheme.light(Colors.blue),
      home: Scaffold(body: child),
    );

void main() {
  group('CommitList selection', () {
    final commits = [
      _commit('a', 'Fourth'),
      _commit('b', 'Third'),
      _commit('c', 'Second'),
      _commit('d', 'First'),
    ];

    Future<List<String>> Function(String, {List<LogicalKeyboardKey> keys})
        harness(WidgetTester tester) {
      var selected = <String>{commits.first.id};
      var last = <String>[];
      Future<void> pump() => tester.pumpWidget(_app(
            StatefulBuilder(
              builder: (context, setState) => CommitList(
                commits: commits,
                selectedIds: selected,
                onSelect: (selection) => setState(() {
                  last = [for (final c in selection) c.summary];
                  selected = {for (final c in selection) c.id};
                }),
              ),
            ),
          ));
      return (summary, {keys = const []}) async {
        if (last.isEmpty && selected.length == 1) await pump();
        for (final key in keys) {
          await tester.sendKeyDownEvent(key);
        }
        await tester.tap(find.text(summary));
        for (final key in keys.reversed) {
          await tester.sendKeyUpEvent(key);
        }
        await tester.pump();
        return last;
      };
    }

    testWidgets('click selects one, Shift+click a range, Ctrl+click toggles',
        (tester) async {
      final click = harness(tester);
      expect(await click('Third'), ['Third']);
      expect(
        await click('First', keys: [LogicalKeyboardKey.shiftLeft]),
        ['Third', 'Second', 'First'],
      );
      expect(
        await click('Second', keys: [LogicalKeyboardKey.controlLeft]),
        ['Third', 'First'],
      );
      expect(
        await click('Fourth', keys: [LogicalKeyboardKey.controlLeft]),
        ['Fourth', 'Third', 'First'],
      );
      expect(await click('Second'), ['Second']);
    });
  });

  group('CommitDetail file list', () {
    final files = [
      _file('app/Http/Controllers/PaymentController.php'),
      _file('app/Models/Payment.php'),
      _file('lang/fa.json'),
      _file('README.md'),
    ];

    Widget detail({
      required bool asTree,
      List<CommitEntry>? commits,
      ValueChanged<bool>? onAsTreeChanged,
    }) =>
        _app(CommitDetail(
          commits: commits ?? [_commit('a', 'Only commit')],
          diffFiles: files,
          isLoading: false,
          error: null,
          selectedFilePath: null,
          filesAsTree: asTree,
          onSelectFile: (_) {},
          onOpenFile: (_) {},
          onFilesAsTreeChanged: onAsTreeChanged ?? (_) {},
        ));

    testWidgets('tree groups files by directory, joining single-child chains',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      await tester.pumpWidget(detail(asTree: true));

      expect(find.text('4 files changed'), findsOneWidget);
      expect(find.text('app'), findsOneWidget);
      expect(find.text('3 files'), findsNothing);
      expect(find.text('2 files'), findsOneWidget);
      expect(find.text('Http/Controllers'), findsOneWidget);
      expect(find.text('PaymentController.php'), findsOneWidget);
      expect(find.text('Models'), findsOneWidget);
      expect(find.text('lang'), findsOneWidget);

      // Collapsing a folder hides its files (8 rows become 4, so the rest
      // are now within the visible part of the list).
      await tester.tap(find.text('app'));
      await tester.pump();
      expect(find.text('PaymentController.php'), findsNothing);
      expect(find.text('Payment.php'), findsNothing);
      expect(find.text('fa.json'), findsOneWidget);
      expect(find.text('README.md'), findsOneWidget);
    });

    testWidgets('flat list shows full paths; the toggle reports the switch',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      bool? asTree;
      await tester.pumpWidget(
        detail(asTree: false, onAsTreeChanged: (value) => asTree = value),
      );
      expect(find.text('app/Models/Payment.php'), findsOneWidget);
      expect(find.text('app'), findsNothing);

      await tester.tap(find.byTooltip('Group by directory'));
      expect(asTree, isTrue);
    });

    testWidgets('several commits get a range header', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      await tester.pumpWidget(detail(
        asTree: true,
        commits: [_commit('a', 'Newest'), _commit('b', 'Oldest')],
      ));
      expect(find.text('2 commits selected'), findsOneWidget);
      expect(find.text('Newest'), findsNothing);
    });
  });
}
