import 'package:branchi/repo/branch_sidebar.dart';
import 'package:branchi/repo/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  BranchEntry b(String name, [int? day]) => BranchEntry(
        name: name,
        isHead: false,
        isRemote: false,
        lastCommitTime: day == null ? null : DateTime.utc(2026, 1, day),
      );

  test('sorts by name, case-insensitively', () {
    final sorted = sortBranches([b('main'), b('Feature'), b('dev')], BranchSort.name);
    expect(sorted.map((e) => e.name), ['dev', 'Feature', 'main']);
  });

  test('sorts by last commit, newest first, unknown last', () {
    final sorted = sortBranches(
      [b('old', 1), b('none'), b('new', 9), b('alsoNew', 9)],
      BranchSort.lastCommit,
    );
    expect(sorted.map((e) => e.name), ['alsoNew', 'new', 'old', 'none']);
  });
}
