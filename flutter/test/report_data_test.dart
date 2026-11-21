import 'package:branchi/l10n/app_calendar.dart';
import 'package:branchi/report/report_data.dart';
import 'package:flutter_test/flutter_test.dart';

ReportCommit commit(
  String id,
  String email,
  DateTime time, {
  List<FileChange> files = const [],
  bool merge = false,
}) =>
    ReportCommit(
      id: id.padRight(40, '0'),
      summary: 'commit $id',
      author: email.split('@').first,
      email: email,
      time: time,
      isMerge: merge,
      additions: files.fold(0, (s, f) => s + f.additions),
      deletions: files.fold(0, (s, f) => s + f.deletions),
      files: files,
    );

void main() {
  const greg = AppCalendar(CalendarKind.gregorian, 'en');
  const jalali = AppCalendar(CalendarKind.jalali, 'fa');
  final now = DateTime(2026, 11, 21, 15);

  test('presets', () {
    final p30 = ReportPeriod.fromPreset(PeriodPreset.last30Days, greg, now: now);
    expect(p30.from, DateTime(2026, 10, 23));
    expect(p30.to, DateTime(2026, 11, 21));
    expect(p30.days, 30);

    final month = ReportPeriod.fromPreset(PeriodPreset.thisMonth, jalali, now: now);
    expect(month.from, DateTime(2026, 10, 23)); // 1 Aban 1405
    final last = ReportPeriod.fromPreset(PeriodPreset.lastMonth, jalali, now: now);
    expect(last.from, DateTime(2026, 9, 23)); // 1 Mehr 1405
    expect(last.to, DateTime(2026, 10, 22));

    final all = ReportPeriod.fromPreset(PeriodPreset.all, greg, now: now);
    expect(all.isAll, isTrue);
    expect(all.sinceSeconds, 0);

    final custom = ReportPeriod.custom(DateTime(2026, 9, 10), DateTime(2026, 9, 1));
    expect(custom.from, DateTime(2026, 9, 1));
    expect(custom.days, 10);
  });

  test('repo and author summaries', () {
    final period = ReportPeriod.custom(DateTime(2026, 11, 1), DateTime(2026, 11, 14));
    final data = ReportData(
      period: period,
      commits: [
        commit('a', 'ann@x.io', DateTime(2026, 11, 2, 10),
            files: const [FileChange('app/A.php', 10, 2), FileChange('README.md', 1, 0)]),
        commit('b', 'ANN@x.io', DateTime(2026, 11, 2, 11),
            files: const [FileChange('app/A.php', 4, 4)]),
        commit('c', 'bob@x.io', DateTime(2026, 11, 9, 22),
            files: const [FileChange('README.md', 2, 1)]),
        commit('d', 'bob@x.io', DateTime(2026, 11, 13, 9), merge: true),
      ],
      previousCount: 2,
      authors: {
        'ann@x.io': AuthorSpan(name: 'Ann', email: 'ann@x.io',
            first: DateTime(2025, 1, 1), last: DateTime(2026, 11, 2), commits: 50),
        'bob@x.io': AuthorSpan(name: 'Bob', email: 'bob@x.io',
            first: DateTime(2026, 11, 9), last: DateTime(2026, 11, 13), commits: 2),
      },
      baseBranch: 'main',
      branches: [
        BranchStat(name: 'main', isHead: true, lastCommitTime: DateTime(2026, 11, 13),
            lastAuthor: 'Bob', lastEmail: 'bob@x.io', ahead: 0, behind: 0, merged: false),
        BranchStat(name: 'old', isHead: false, lastCommitTime: DateTime(2026, 8, 1),
            lastAuthor: 'Ann', lastEmail: 'ann@x.io', ahead: 3, behind: 40, merged: false),
        BranchStat(name: 'done', isHead: false, lastCommitTime: DateTime(2026, 8, 1),
            lastAuthor: 'Ann', lastEmail: 'Ann@x.io', ahead: 0, behind: 9, merged: true),
      ],
    );

    final repo = ReportSummary.compute(data, calendar: greg, now: now);
    expect(repo.commits.length, 4);
    expect(repo.additions, 17);
    expect(repo.deletions, 7);
    expect(repo.activeDays, 3);
    expect(repo.periodDays, 14);
    expect(repo.contributors.map((c) => c.name), ['Ann', 'Bob']);
    expect(repo.newContributors, 1);
    expect(repo.hotspots.first.path, 'app/A.php');
    expect(repo.heatmap[DateTime(2026, 11, 2).weekday][10], 1);
    expect(repo.bucketSize, BucketSize.day);
    expect(repo.buckets.length, 14);
    expect(repo.buckets[1].count, 2);
    expect(repo.staleBranches, 1);
    expect(repo.mergedBranches, 1);

    final ann = ReportSummary.compute(data, authorKey: 'ann@x.io', calendar: greg, now: now);
    expect(ann.commits.length, 2);
    expect(ann.shareOfCommits, 0.5);
    expect(ann.filesTouched, 2);
    expect(ann.filesOnlyThey, 1); // app/A.php; Bob also changed README.md
    expect(ann.authorFiles.first.path, 'app/A.php');
    expect(ann.authorFiles.first.ownership, Ownership.only);
    expect(ann.authorFiles.last.ownership, Ownership.shared);
    expect(ann.areas.first.directory, 'app');
    expect(ann.recentCommits.first.id.startsWith('b'), isTrue);
    expect(ann.branches.map((b) => b.name), ['old', 'done']);
  });

  test('long periods bucket by month in the chosen calendar', () {
    final period = ReportPeriod.custom(DateTime(2025, 3, 21), DateTime(2026, 11, 21));
    final data = ReportData(
      period: period,
      commits: [commit('a', 'a@x.io', DateTime(2025, 4, 20, 9))],
      previousCount: 0,
      authors: const {},
      baseBranch: null,
      branches: const [],
    );
    final s = ReportSummary.compute(data, calendar: jalali, now: now);
    expect(s.bucketSize, BucketSize.month);
    expect(s.buckets.first.start, DateTime(2025, 3, 21)); // 1 Farvardin 1404
    expect(s.buckets.first.count, 1); // 31 Farvardin
    expect(s.buckets[1].start, DateTime(2025, 4, 21));
  });
}
