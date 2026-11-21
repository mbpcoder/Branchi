import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../l10n/app_calendar.dart';

/// Lines added/removed in one file by one commit.
class FileChange {
  const FileChange(this.path, this.additions, this.deletions);

  factory FileChange.fromJson(Map<String, dynamic> json) => FileChange(
    json['path'] as String,
    json['additions'] as int,
    json['deletions'] as int,
  );

  final String path;
  final int additions;
  final int deletions;
}

/// One commit with line counts. Merge commits have no files or lines.
class ReportCommit {
  const ReportCommit({
    required this.id,
    required this.summary,
    required this.author,
    required this.email,
    required this.time,
    required this.isMerge,
    required this.additions,
    required this.deletions,
    required this.files,
  });

  factory ReportCommit.fromJson(Map<String, dynamic> json) => ReportCommit(
    id: json['id'] as String,
    summary: json['summary'] as String,
    author: json['author'] as String,
    email: json['email'] as String,
    time: DateTime.parse(json['time'] as String).toLocal(),
    isMerge: json['is_merge'] as bool,
    additions: json['additions'] as int,
    deletions: json['deletions'] as int,
    files: (json['files'] as List<dynamic>)
        .map((f) => FileChange.fromJson(f as Map<String, dynamic>))
        .toList(),
  );

  final String id;
  final String summary;
  final String author;
  final String email;

  /// Author date, local time.
  final DateTime time;
  final bool isMerge;
  final int additions;
  final int deletions;
  final List<FileChange> files;

  /// Authors are identified by email, case-insensitively.
  String get authorKey => email.toLowerCase();
}

/// An author's span over the whole history.
class AuthorSpan {
  const AuthorSpan({
    required this.name,
    required this.email,
    required this.first,
    required this.last,
    required this.commits,
  });

  factory AuthorSpan.fromJson(Map<String, dynamic> json) => AuthorSpan(
    name: json['name'] as String,
    email: json['email'] as String,
    first: DateTime.parse(json['first'] as String).toLocal(),
    last: DateTime.parse(json['last'] as String).toLocal(),
    commits: json['commits'] as int,
  );

  final String name;
  final String email;
  final DateTime first;
  final DateTime last;
  final int commits;

  String get key => email.toLowerCase();
}

/// A local branch compared with the base branch.
class BranchStat {
  const BranchStat({
    required this.name,
    required this.isHead,
    required this.lastCommitTime,
    required this.lastAuthor,
    required this.lastEmail,
    required this.ahead,
    required this.behind,
    required this.merged,
  });

  factory BranchStat.fromJson(Map<String, dynamic> json) => BranchStat(
    name: json['name'] as String,
    isHead: json['is_head'] as bool,
    lastCommitTime: DateTime.parse(
      json['last_commit_time'] as String,
    ).toLocal(),
    lastAuthor: json['last_author'] as String,
    lastEmail: json['last_email'] as String,
    ahead: json['ahead'] as int,
    behind: json['behind'] as int,
    merged: json['merged'] as bool,
  );

  final String name;
  final bool isHead;
  final DateTime lastCommitTime;
  final String lastAuthor;
  final String lastEmail;
  final int ahead;
  final int behind;
  final bool merged;
}

/// The preset choices of the period control; [custom] is a picked range.
enum PeriodPreset {
  last7Days,
  last30Days,
  last90Days,
  lastYear,
  all,
  thisMonth,
  lastMonth,
  thisYear,
  custom,
}

/// The dates a report covers, inclusive, as local calendar days.
/// [from] is `null` for "all history".
class ReportPeriod {
  const ReportPeriod(this.preset, this.from, this.to);

  final PeriodPreset preset;
  final DateTime? from;
  final DateTime to;

  bool get isAll => from == null;

  /// Number of calendar days covered (only when [from] is set).
  int get days => from == null ? 0 : _daysBetween(from!, to) + 1;

  /// Unix seconds of the start of [from] (0 for all history).
  int get sinceSeconds =>
      from == null ? 0 : from!.millisecondsSinceEpoch ~/ 1000;

  /// Unix seconds of the end of [to].
  int get untilSeconds =>
      DateTime(to.year, to.month, to.day + 1).millisecondsSinceEpoch ~/ 1000 -
      1;

  /// Start of the equally long period right before this one.
  int get previousSinceSeconds => from == null
      ? 0
      : DateTime(
              from!.year,
              from!.month,
              from!.day - days,
            ).millisecondsSinceEpoch ~/
            1000;

  /// Builds [preset] ending today ([now]), in [calendar]'s months/years.
  static ReportPeriod fromPreset(
    PeriodPreset preset,
    AppCalendar calendar, {
    DateTime? now,
  }) {
    final today = _dateOnly(now ?? DateTime.now());
    DateTime back(int days) =>
        DateTime(today.year, today.month, today.day - days + 1);
    switch (preset) {
      case PeriodPreset.last7Days:
        return ReportPeriod(preset, back(7), today);
      case PeriodPreset.last30Days:
        return ReportPeriod(preset, back(30), today);
      case PeriodPreset.last90Days:
        return ReportPeriod(preset, back(90), today);
      case PeriodPreset.lastYear:
        return ReportPeriod(preset, back(365), today);
      case PeriodPreset.all:
        return ReportPeriod(preset, null, today);
      case PeriodPreset.thisMonth:
        return ReportPeriod(preset, calendar.startOfMonth(today), today);
      case PeriodPreset.lastMonth:
        final thisMonth = calendar.startOfMonth(today);
        final lastDay = DateTime(
          thisMonth.year,
          thisMonth.month,
          thisMonth.day - 1,
        );
        return ReportPeriod(preset, calendar.startOfMonth(lastDay), lastDay);
      case PeriodPreset.thisYear:
        return ReportPeriod(preset, calendar.startOfYear(today), today);
      case PeriodPreset.custom:
        return ReportPeriod(preset, back(30), today);
    }
  }

  static ReportPeriod custom(DateTime from, DateTime to) {
    final a = _dateOnly(from);
    final b = _dateOnly(to);
    return a.isAfter(b)
        ? ReportPeriod(PeriodPreset.custom, b, a)
        : ReportPeriod(PeriodPreset.custom, a, b);
  }
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

int _daysBetween(DateTime a, DateTime b) =>
    (DateTime.utc(
              b.year,
              b.month,
              b.day,
            ).difference(DateTime.utc(a.year, a.month, a.day)).inHours /
            24)
        .round();

/// Everything loaded for one period: the commits in it, the previous
/// period's commit count, every author's span and the branches.
class ReportData {
  const ReportData({
    required this.period,
    required this.commits,
    required this.previousCount,
    required this.authors,
    required this.baseBranch,
    required this.branches,
  });

  final ReportPeriod period;
  final List<ReportCommit> commits;
  final int previousCount;
  final Map<String, AuthorSpan> authors;
  final String? baseBranch;
  final List<BranchStat> branches;
}

/// How the activity chart groups commits.
enum BucketSize { day, week, month }

/// One bar of the activity chart.
class ActivityBucket {
  const ActivityBucket(this.start, this.count);

  final DateTime start;
  final int count;
}

class ContributorStat {
  ContributorStat(this.key, this.name, this.email);

  final String key;
  String name;
  final String email;
  int commits = 0;
  int additions = 0;
  int deletions = 0;
}

class FileStat {
  FileStat(this.path);

  final String path;

  /// Commits that changed this file.
  int times = 0;
  int lines = 0;
}

/// How much of a file's changes (in the period) one author made.
enum Ownership { only, mostly, shared }

class AuthorFileStat {
  const AuthorFileStat(this.path, this.times, this.ownership);

  final String path;
  final int times;
  final Ownership ownership;
}

class AreaStat {
  const AreaStat(this.directory, this.share);

  final String directory;

  /// Fraction (0-1) of the author's changed lines.
  final double share;
}

/// A local branch is stale when it isn't merged and has had no commit for
/// this long.
const Duration staleAfter = Duration(days: 30);

/// The numbers behind every panel, for the whole repository or (with
/// [authorKey]) one author.
class ReportSummary {
  ReportSummary._(this.data, this.authorKey, this.calendar, this.now);

  factory ReportSummary.compute(
    ReportData data, {
    String? authorKey,
    required AppCalendar calendar,
    DateTime? now,
  }) {
    final summary = ReportSummary._(
      data,
      authorKey,
      calendar,
      now ?? DateTime.now(),
    );
    summary._compute();
    return summary;
  }

  final ReportData data;
  final String? authorKey;
  final AppCalendar calendar;
  final DateTime now;

  late final List<ReportCommit> commits;
  late final int additions;
  late final int deletions;
  late final int activeDays;

  /// Calendar days in the period (for "all", from the first commit).
  late final int periodDays;
  late final List<ContributorStat> contributors;
  late final int newContributors;
  late final List<FileStat> hotspots;

  /// `[weekday 1-7][hour 0-23]`, index 0 unused.
  late final List<List<int>> heatmap;
  late final BucketSize bucketSize;
  late final List<ActivityBucket> buckets;
  late final List<BranchStat> branches;
  late final int staleBranches;
  late final int mergedBranches;

  // Author view only.
  late final double shareOfCommits;
  late final int filesTouched;
  late final int filesOnlyThey;
  late final int medianCommitSize;
  late final List<AreaStat> areas;
  late final List<AuthorFileStat> authorFiles;
  late final List<ReportCommit> recentCommits;

  bool isStale(BranchStat b) =>
      !b.merged &&
      b.name != data.baseBranch &&
      now.difference(b.lastCommitTime) > staleAfter;

  void _compute() {
    final all = data.commits;
    commits = authorKey == null
        ? all
        : all.where((c) => c.authorKey == authorKey).toList();

    additions = commits.fold(0, (sum, c) => sum + c.additions);
    deletions = commits.fold(0, (sum, c) => sum + c.deletions);
    activeDays = commits.map((c) => _dateOnly(c.time)).toSet().length;

    final from =
        data.period.from ??
        (all.isEmpty
            ? _dateOnly(data.period.to)
            : _dateOnly(
                all.map((c) => c.time).reduce((a, b) => a.isBefore(b) ? a : b),
              ));
    periodDays = _daysBetween(from, data.period.to) + 1;

    final byAuthor = <String, ContributorStat>{};
    for (final c in all) {
      final stat = byAuthor.putIfAbsent(
        c.authorKey,
        () => ContributorStat(c.authorKey, c.author, c.email),
      );
      stat.commits++;
      stat.additions += c.additions;
      stat.deletions += c.deletions;
    }
    for (final stat in byAuthor.values) {
      final span = data.authors[stat.key];
      if (span != null && span.name.isNotEmpty) stat.name = span.name;
    }
    contributors = byAuthor.values.toList()
      ..sort((a, b) => b.commits.compareTo(a.commits));
    final periodStart = data.period.from;
    newContributors = periodStart == null
        ? 0
        : byAuthor.keys
              .where(
                (k) => !(data.authors[k]?.first.isBefore(periodStart) ?? false),
              )
              .length;

    final files = <String, FileStat>{};
    for (final c in commits) {
      for (final f in c.files) {
        final stat = files.putIfAbsent(f.path, () => FileStat(f.path));
        stat.times++;
        stat.lines += f.additions + f.deletions;
      }
    }
    hotspots = files.values.toList()
      ..sort((a, b) {
        final byTimes = b.times.compareTo(a.times);
        return byTimes != 0 ? byTimes : b.lines.compareTo(a.lines);
      });

    heatmap = List.generate(8, (_) => List.filled(24, 0));
    for (final c in commits) {
      heatmap[c.time.weekday][c.time.hour]++;
    }

    _computeBuckets(from);

    branches = authorKey == null
        ? data.branches
        : data.branches
              .where((b) => b.lastEmail.toLowerCase() == authorKey)
              .toList();
    staleBranches = branches.where(isStale).length;
    mergedBranches = branches.where((b) => b.merged).length;

    if (authorKey != null) _computeAuthor(all, files);
  }

  void _computeBuckets(DateTime from) {
    final to = data.period.to;
    if (periodDays <= 31) {
      bucketSize = BucketSize.day;
    } else if (periodDays <= 366) {
      bucketSize = BucketSize.week;
    } else {
      bucketSize = BucketSize.month;
    }

    final starts = <DateTime>[];
    switch (bucketSize) {
      case BucketSize.day:
        for (var i = 0; i < periodDays; i++) {
          starts.add(DateTime(from.year, from.month, from.day + i));
        }
      case BucketSize.week:
        for (var i = 0; i < periodDays; i += 7) {
          starts.add(DateTime(from.year, from.month, from.day + i));
        }
      case BucketSize.month:
        var start = calendar.startOfMonth(from);
        while (!start.isAfter(to)) {
          starts.add(start);
          final c = calendar.fromDateTime(start);
          start = calendar.toDateTime(c.year, c.month + 1, 1);
        }
    }

    final counts = List.filled(starts.length, 0);
    for (final c in commits) {
      final day = _dateOnly(c.time);
      // Last bucket whose start is on or before the commit's day.
      var lo = 0, hi = starts.length - 1, found = -1;
      while (lo <= hi) {
        final mid = (lo + hi) ~/ 2;
        if (!starts[mid].isAfter(day)) {
          found = mid;
          lo = mid + 1;
        } else {
          hi = mid - 1;
        }
      }
      if (found >= 0) counts[found]++;
    }
    buckets = [
      for (var i = 0; i < starts.length; i++)
        ActivityBucket(starts[i], counts[i]),
    ];
  }

  void _computeAuthor(List<ReportCommit> all, Map<String, FileStat> mine) {
    shareOfCommits = all.isEmpty ? 0 : commits.length / all.length;
    filesTouched = mine.length;

    // Times each file was changed by anyone, and by someone else.
    final totalTimes = <String, int>{};
    final otherAuthors = <String>{};
    for (final c in all) {
      for (final f in c.files) {
        totalTimes[f.path] = (totalTimes[f.path] ?? 0) + 1;
        if (c.authorKey != authorKey) otherAuthors.add(f.path);
      }
    }
    filesOnlyThey = mine.keys.where((p) => !otherAuthors.contains(p)).length;

    final sizes =
        commits
            .where((c) => !c.isMerge)
            .map((c) => c.additions + c.deletions)
            .toList()
          ..sort();
    medianCommitSize = sizes.isEmpty ? 0 : sizes[sizes.length ~/ 2];

    final dirLines = <String, int>{};
    var totalLines = 0;
    for (final f in mine.values) {
      final dir = p.posix.dirname(f.path);
      final lines = math.max(f.lines, 1);
      dirLines[dir == '.' ? '/' : dir] =
          (dirLines[dir == '.' ? '/' : dir] ?? 0) + lines;
      totalLines += lines;
    }
    areas =
        (dirLines.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .map(
              (e) =>
                  AreaStat(e.key, totalLines == 0 ? 0 : e.value / totalLines),
            )
            .toList();

    authorFiles = hotspots.map((f) {
      final share = f.times / (totalTimes[f.path] ?? f.times);
      final ownership = !otherAuthors.contains(f.path)
          ? Ownership.only
          : share >= 0.6
          ? Ownership.mostly
          : Ownership.shared;
      return AuthorFileStat(f.path, f.times, ownership);
    }).toList();

    recentCommits = (commits.toList()..sort((a, b) => b.time.compareTo(a.time)))
        .take(10)
        .toList();
  }
}
