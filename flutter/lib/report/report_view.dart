import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_calendar.dart';
import '../l10n/app_locale.dart';
import '../theme/app_theme.dart';
import 'date_range_popover.dart';
import 'report_controller.dart';
import 'report_data.dart';

/// The Report section: activity of the whole repository or, once an
/// author is picked, of that author, over a chosen period.
class ReportView extends StatefulWidget {
  const ReportView({
    super.key,
    required this.controller,
    required this.onOpenCommit,
  });

  final ReportController controller;

  /// Shows a commit in History.
  final ValueChanged<ReportCommit> onOpenCommit;

  @override
  State<ReportView> createState() => _ReportViewState();
}

class _ReportViewState extends State<ReportView> {
  final GlobalKey _periodKey = GlobalKey();

  ReportController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.load();
    AppCalendarSettings.preference.addListener(_calendarChanged);
  }

  @override
  void dispose() {
    AppCalendarSettings.preference.removeListener(_calendarChanged);
    super.dispose();
  }

  /// Month/year presets depend on the calendar.
  void _calendarChanged() {
    if (!mounted) return;
    setState(() {});
    _c.load();
  }

  Future<void> _openCustomRange() async {
    final box = _periodKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final topLeft = box.localToGlobal(Offset.zero);
    final chosen = await showDateRangePopover(
      context,
      anchor: topLeft & box.size,
      current: _c.period,
    );
    if (chosen == null) return;
    if (chosen.preset == PeriodPreset.custom) {
      _c.setCustomPeriod(chosen.from!, chosen.to);
    } else {
      _c.setPreset(chosen.preset);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final calendar = AppCalendarSettings.current;
        final data = _c.data;
        final summary = data == null
            ? null
            : ReportSummary.compute(
                data,
                authorKey: _c.authorKey,
                calendar: calendar,
              );
        final all = data == null
            ? null
            : (_c.authorKey == null
                  ? summary
                  : ReportSummary.compute(data, calendar: calendar));

        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 920;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(context, calendar, data, all),
                  const SizedBox(height: 16),
                  if (_c.error != null)
                    _Message(text: _c.error!, isError: true)
                  else if (summary == null)
                    const _Loading()
                  else ...[
                    if (_c.isLoading) ...[
                      const LinearProgressIndicator(minHeight: 2),
                      const SizedBox(height: 8),
                    ],
                    if (_c.authorKey == null)
                      ..._repoPanels(summary, calendar, wide)
                    else
                      ..._authorPanels(summary, calendar, wide),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _header(
    BuildContext context,
    AppCalendar calendar,
    ReportData? data,
    ReportSummary? all,
  ) {
    final b = context.branchi;
    final period = _c.period;
    final range = period.isAll
        ? translate('report_preset_all')
        : '${calendar.formatDate(period.from!)} – ${calendar.formatDate(period.to)}';
    final author = _c.authorKey == null ? null : data?.authors[_c.authorKey];

    Widget title;
    if (_c.authorKey == null) {
      title = Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        children: [
          Text(
            translate('report'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: b.fg,
            ),
          ),
          Text(
            [
              if (data?.baseBranch != null) data!.baseBranch!,
              range,
            ].join(' · '),
            style: TextStyle(fontSize: 12, color: b.muted),
          ),
        ],
      );
    } else {
      final name = author?.name ?? _c.authorKey!;
      title = Row(
        children: [
          TextButton.icon(
            onPressed: () => _c.selectAuthor(null),
            icon: Icon(
              Directionality.of(context) == TextDirection.rtl
                  ? Icons.arrow_forward
                  : Icons.arrow_back,
              size: 16,
            ),
            label: Text(translate('report')),
          ),
          Text('/', style: TextStyle(color: b.muted)),
          const SizedBox(width: 10),
          CircleAvatar(
            radius: 16,
            backgroundColor: b.accent.withValues(alpha: 0.15),
            child: Text(
              _initials(name),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: b.accent,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: b.fg,
                  ),
                ),
                Text(
                  [
                    author?.email ?? _c.authorKey!,
                    if (author != null)
                      translate(
                        'report_first_commit',
                      ).replaceAll('{date}', calendar.formatDate(author.first)),
                    if (author != null)
                      translate(
                        'report_last_commit',
                      ).replaceAll('{date}', calendar.formatDate(author.last)),
                  ].join(' · '),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: b.muted),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 12,
      spacing: 12,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: title,
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PeriodControl(
              key: _periodKey,
              calendar: calendar,
              period: period,
              onPreset: _c.setPreset,
              onCustom: _openCustomRange,
            ),
            const SizedBox(width: 8),
            _AuthorMenu(
              contributors: all?.contributors ?? const [],
              selected: _c.authorKey,
              selectedName: author?.name,
              onSelected: _c.selectAuthor,
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: translate('report_refresh'),
              onPressed: _c.isLoading ? null : () => _c.load(force: true),
              icon: Icon(Icons.refresh, size: 18, color: b.muted),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- repo

  List<Widget> _repoPanels(ReportSummary s, AppCalendar cal, bool wide) {
    final b = context.branchi;
    final data = s.data;
    String? change;
    Color? changeColor;
    if (!data.period.isAll) {
      final prev = data.previousCount;
      if (prev == 0) {
        change = translate('report_previous_none');
      } else {
        final pct = ((s.commits.length - prev) / prev * 100).round();
        change = translate(
          'report_vs_previous',
        ).replaceAll('{pct}', _ltr('${pct >= 0 ? '+' : ''}${_fmt(pct)}%'));
        changeColor = pct >= 0 ? b.add : b.del;
      }
    }
    final localBranches = data.branches.length;

    return [
      _Tiles(
        children: [
          _Tile(
            label: translate('report_commits'),
            value: _fmt(s.commits.length),
            sub: change ?? '',
            subColor: changeColor,
          ),
          _Tile(
            label: translate('report_contributors'),
            value: _fmt(s.contributors.length),
            sub: data.period.isAll
                ? ''
                : translate(
                    'report_new_count',
                  ).replaceAll('{n}', _fmt(s.newContributors)),
          ),
          _Tile(
            label: translate('report_lines_changed'),
            value: _ltr('+${_compact(s.additions)}'),
            sub: translate(
              'report_removed',
            ).replaceAll('{n}', _ltr('−${_compact(s.deletions)}')),
          ),
          _Tile(
            label: translate('report_active_days'),
            value: _fmt(s.activeDays),
            sub: translate(
              'report_of_days',
            ).replaceAll('{n}', _fmt(s.periodDays)),
          ),
          _Tile(
            label: translate('report_branches'),
            value: _fmt(localBranches),
            sub: translate('report_stale_merged')
                .replaceAll('{stale}', _fmt(s.staleBranches))
                .replaceAll('{merged}', _fmt(s.mergedBranches)),
            subColor: s.staleBranches > 0 ? b.mod : null,
          ),
        ],
      ),
      const SizedBox(height: 12),
      _activityCard(s, cal),
      const SizedBox(height: 12),
      _pair(
        wide,
        _Card(
          title: translate('report_top_contributors'),
          hint: translate('report_hint_commits_lines'),
          child: s.contributors.isEmpty
              ? const _Empty()
              : Column(
                  children: [
                    for (final c in s.contributors.take(8))
                      _BarRow(
                        label: c.name.isEmpty ? c.email : c.name,
                        tooltip: c.email,
                        value: _fmt(c.commits),
                        fraction: c.commits / s.contributors.first.commits,
                        extra: _ltr(
                          '+${_compact(c.additions)} −${_compact(c.deletions)}',
                        ),
                        onTap: () => _c.selectAuthor(c.key),
                      ),
                  ],
                ),
        ),
        _Card(
          title: translate('report_most_changed_files'),
          hint: translate('report_hint_times_changed'),
          child: s.hotspots.isEmpty
              ? const _Empty()
              : Column(
                  children: [
                    for (final f in s.hotspots.take(8))
                      _BarRow(
                        label: f.path,
                        tooltip: f.path,
                        mono: true,
                        value: _fmt(f.times),
                        fraction: f.times / s.hotspots.first.times,
                      ),
                  ],
                ),
        ),
      ),
      const SizedBox(height: 12),
      _pair(
        wide,
        _heatmapCard(s, cal, translate('report_when_commits_happen')),
        _branchesCard(s, cal, translate('report_branches'), limit: 8),
      ),
    ];
  }

  // -------------------------------------------------------------- author

  List<Widget> _authorPanels(ReportSummary s, AppCalendar cal, bool wide) {
    final b = context.branchi;
    if (s.commits.isEmpty) {
      return [_Message(text: translate('report_author_no_commits'))];
    }
    return [
      _Tiles(
        children: [
          _Tile(
            label: translate('report_commits'),
            value: _fmt(s.commits.length),
            sub: translate('report_share_of_commits').replaceAll(
              '{pct}',
              _ltr('${_fmt((s.shareOfCommits * 100).round())}%'),
            ),
          ),
          _Tile(
            label: translate('report_lines_changed'),
            value: _ltr('+${_compact(s.additions)}'),
            sub: translate(
              'report_removed',
            ).replaceAll('{n}', _ltr('−${_compact(s.deletions)}')),
          ),
          _Tile(
            label: translate('report_active_days'),
            value: _fmt(s.activeDays),
            sub: translate('report_of_days_avg')
                .replaceAll('{n}', _fmt(s.periodDays))
                .replaceAll(
                  '{avg}',
                  AppCalendarSettings.current.digits(
                    (s.commits.length / math.max(s.activeDays, 1))
                        .toStringAsFixed(1),
                  ),
                ),
          ),
          _Tile(
            label: translate('report_files_touched'),
            value: _fmt(s.filesTouched),
            sub: translate(
              'report_only_they_changed',
            ).replaceAll('{n}', _fmt(s.filesOnlyThey)),
            subColor: s.filesOnlyThey > 0 ? b.mod : null,
          ),
          _Tile(
            label: translate('report_commit_size'),
            value: _fmt(s.medianCommitSize),
            sub: translate('report_median_lines'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _activityCard(s, cal),
      const SizedBox(height: 12),
      _pair(
        wide,
        _Card(
          title: translate('report_areas'),
          hint: translate('report_hint_share_of_changes'),
          child: s.areas.isEmpty
              ? const _Empty()
              : Column(
                  children: [
                    for (final a in s.areas.take(8))
                      _BarRow(
                        label: a.directory,
                        tooltip: a.directory,
                        mono: true,
                        value: _ltr('${_fmt((a.share * 100).round())}%'),
                        fraction: a.share / s.areas.first.share,
                      ),
                  ],
                ),
        ),
        _Card(
          title: translate('report_files_they_change'),
          hint: translate('report_hint_times_owner'),
          child: s.authorFiles.isEmpty
              ? const _Empty()
              : Column(
                  children: [
                    for (final f in s.authorFiles.take(8))
                      _BarRow(
                        label: p.posix.basename(f.path),
                        tooltip: f.path,
                        mono: true,
                        value: _fmt(f.times),
                        fraction: f.times / s.authorFiles.first.times,
                        extra: translate(
                          'report_ownership_${f.ownership.name}',
                        ),
                      ),
                  ],
                ),
        ),
      ),
      const SizedBox(height: 12),
      _pair(
        wide,
        _recentCommitsCard(s, cal),
        Column(
          children: [
            _heatmapCard(s, cal, translate('report_when_they_commit')),
            const SizedBox(height: 12),
            _branchesCard(s, cal, translate('report_their_branches')),
          ],
        ),
      ),
    ];
  }

  // -------------------------------------------------------------- panels

  Widget _activityCard(ReportSummary s, AppCalendar cal) {
    final title = switch (s.bucketSize) {
      BucketSize.day => translate('report_commits_per_day'),
      BucketSize.week => translate('report_commits_per_week'),
      BucketSize.month => translate('report_commits_per_month'),
    };
    return _Card(
      title: title,
      child: _ActivityChart(summary: s, calendar: cal),
    );
  }

  Widget _heatmapCard(ReportSummary s, AppCalendar cal, String title) => _Card(
    title: title,
    hint: translate('report_hint_weekday_hour'),
    child: _Heatmap(summary: s, calendar: cal),
  );

  Widget _branchesCard(
    ReportSummary s,
    AppCalendar cal,
    String title, {
    int limit = 6,
  }) {
    final b = context.branchi;
    final base = s.data.baseBranch;
    return _Card(
      title: title,
      hint: base == null
          ? translate('report_hint_last_commit')
          : translate('report_hint_vs_base').replaceAll('{base}', base),
      child: s.branches.isEmpty
          ? const _Empty()
          : Column(
              children: [
                for (final branch in s.branches.take(limit))
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(border: Border(top: b.hairline)),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            branch.name,
                            overflow: TextOverflow.ellipsis,
                            style: b.mono(fontSize: 12, color: b.fg),
                          ),
                        ),
                        if (branch.name == base)
                          _Tag(translate('report_tag_base'), b.muted)
                        else if (branch.merged)
                          _Tag(translate('report_tag_merged'), b.add)
                        else if (s.isStale(branch))
                          _Tag(translate('report_tag_stale'), b.mod),
                        SizedBox(
                          width: 90,
                          child: Text(
                            branch.name == base
                                ? ''
                                : _ltr(
                                    '↑${_fmt(branch.ahead)} ↓${_fmt(branch.behind)}',
                                  ),
                            textAlign: TextAlign.end,
                            style: b.mono(fontSize: 12, color: b.muted),
                          ),
                        ),
                        SizedBox(
                          width: 90,
                          child: Tooltip(
                            message: cal.formatDate(branch.lastCommitTime),
                            child: Text(
                              _ago(branch.lastCommitTime, cal),
                              textAlign: TextAlign.end,
                              style: TextStyle(fontSize: 12, color: b.muted),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (s.branches.length > limit)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      translate(
                        'report_more_count',
                      ).replaceAll('{n}', _fmt(s.branches.length - limit)),
                      style: TextStyle(fontSize: 12, color: b.muted),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _recentCommitsCard(ReportSummary s, AppCalendar cal) {
    final b = context.branchi;
    return _Card(
      title: translate('report_recent_commits'),
      hint: translate('report_hint_open_in_history'),
      child: Column(
        children: [
          for (final c in s.recentCommits)
            InkWell(
              onTap: () => widget.onOpenCommit(c),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(border: Border(top: b.hairline)),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        c.summary,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: b.fg),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 56,
                      child: Text(
                        c.isMerge ? '' : _ltr('+${_compact(c.additions)}'),
                        textAlign: TextAlign.end,
                        style: b.mono(fontSize: 12, color: b.add),
                      ),
                    ),
                    SizedBox(
                      width: 52,
                      child: Text(
                        c.isMerge ? '' : _ltr('−${_compact(c.deletions)}'),
                        textAlign: TextAlign.end,
                        style: b.mono(fontSize: 12, color: b.del),
                      ),
                    ),
                    SizedBox(
                      width: 74,
                      child: Text(
                        c.id.substring(0, 7),
                        textAlign: TextAlign.end,
                        style: b.mono(fontSize: 12, color: b.muted),
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      child: Tooltip(
                        message: cal.formatDate(c.time),
                        child: Text(
                          _ago(c.time, cal),
                          textAlign: TextAlign.end,
                          style: TextStyle(fontSize: 12, color: b.muted),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pair(bool wide, Widget a, Widget b) {
    if (!wide) {
      return Column(children: [a, const SizedBox(height: 12), b]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: a),
        const SizedBox(width: 12),
        Expanded(child: b),
      ],
    );
  }
}

// ------------------------------------------------------------- helpers

String _fmt(int n) => AppCalendarSettings.current.digits(n);

/// Keeps signs and arrows next to their numbers in right-to-left text.
String _ltr(String s) => '\u2066$s\u2069';

/// 950 -> "950", 12400 -> "12.4k", 2100000 -> "2.1M".
String _compact(int n) {
  String text;
  if (n < 1000) {
    text = '$n';
  } else if (n < 1000000) {
    text = '${(n / 1000).toStringAsFixed(n < 10000 ? 1 : 0)}k';
  } else {
    text = '${(n / 1000000).toStringAsFixed(1)}M';
  }
  return AppCalendarSettings.current.digits(text.replaceAll('.0k', 'k'));
}

String _ago(DateTime time, AppCalendar cal) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 60) {
    return translate(
      'report_ago_minutes',
    ).replaceAll('{n}', cal.digits(math.max(diff.inMinutes, 1)));
  }
  if (diff.inHours < 24) {
    return translate(
      'report_ago_hours',
    ).replaceAll('{n}', cal.digits(diff.inHours));
  }
  if (diff.inDays == 1) return translate('report_ago_yesterday');
  if (diff.inDays < 60) {
    return translate(
      'report_ago_days',
    ).replaceAll('{n}', cal.digits(diff.inDays));
  }
  return cal.formatDate(time);
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
  final letters = parts.take(2).map((s) => s.characters.first).join();
  return letters.isEmpty ? '?' : letters.toUpperCase();
}

// ------------------------------------------------------------- widgets

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(48),
    child: Center(
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Text(text, style: TextStyle(color: isError ? b.del : b.muted)),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      translate('report_nothing_in_period'),
      style: TextStyle(fontSize: 12, color: context.branchi.muted),
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.title, this.hint, required this.child});

  final String title;
  final String? hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: b.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: b.fg,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  hint ?? '',
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: b.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _Tiles extends StatelessWidget {
  const _Tiles({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final perRow = constraints.maxWidth >= 900
            ? children.length
            : constraints.maxWidth >= 560
            ? 3
            : 2;
        final width =
            (constraints.maxWidth - gap * (perRow - 1)) / perRow - 0.01;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.value,
    required this.sub,
    this.subColor,
  });

  final String label;
  final String value;
  final String sub;
  final Color? subColor;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: b.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: b.muted)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: b.fg,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: subColor ?? b.muted),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(end: 10),
    child: Text(text, style: TextStyle(fontSize: 11, color: color)),
  );
}

/// A labelled horizontal bar: name, bar, value, and optional extra text.
class _BarRow extends StatefulWidget {
  const _BarRow({
    required this.label,
    required this.value,
    required this.fraction,
    this.tooltip,
    this.extra,
    this.mono = false,
    this.onTap,
  });

  final String label;
  final String value;
  final double fraction;
  final String? tooltip;
  final String? extra;
  final bool mono;
  final VoidCallback? onTap;

  @override
  State<_BarRow> createState() => _BarRowState();
}

class _BarRowState extends State<_BarRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final labelColor = _hovered && widget.onTap != null ? b.accent : b.fg;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 190,
            child: Tooltip(
              message: widget.tooltip ?? '',
              child: Text(
                widget.label,
                overflow: TextOverflow.ellipsis,
                style: widget.mono
                    ? b.mono(fontSize: 12, color: labelColor)
                    : TextStyle(fontSize: 13, color: labelColor),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Align(
                alignment: AlignmentDirectional.centerStart,
                child: Container(
                  height: 8,
                  width: math.max(4, constraints.maxWidth * widget.fraction),
                  decoration: BoxDecoration(
                    color: b.accent.withValues(alpha: _hovered ? 0.9 : 0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              widget.value,
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: 12, color: b.fg),
            ),
          ),
          if (widget.extra != null)
            SizedBox(
              width: 100,
              child: Text(
                widget.extra!,
                textAlign: TextAlign.end,
                style: TextStyle(fontSize: 12, color: b.muted),
              ),
            ),
        ],
      ),
    );
    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: row,
      ),
    );
  }
}

/// Commits per day / week / month as bars, the latest bar emphasized.
class _ActivityChart extends StatelessWidget {
  const _ActivityChart({required this.summary, required this.calendar});

  final ReportSummary summary;
  final AppCalendar calendar;

  String _label(ActivityBucket bucket) => summary.bucketSize == BucketSize.month
      ? calendar.formatMonth(bucket.start, withYear: true)
      : calendar.formatDay(bucket.start);

  String _tooltip(int index) {
    final buckets = summary.buckets;
    final bucket = buckets[index];
    final count = translate(
      'report_n_commits',
    ).replaceAll('{n}', calendar.digits(bucket.count));
    switch (summary.bucketSize) {
      case BucketSize.day:
        return '${calendar.formatDate(bucket.start)}: $count';
      case BucketSize.week:
        final end = index + 1 < buckets.length
            ? buckets[index + 1].start.subtract(const Duration(days: 1))
            : summary.data.period.to;
        return '${calendar.formatDay(bucket.start)} – '
            '${calendar.formatDay(end)}: $count';
      case BucketSize.month:
        return '${calendar.formatMonth(bucket.start, withYear: true)}: $count';
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final buckets = summary.buckets;
    if (buckets.isEmpty) return const _Empty();
    final maxCount = buckets.map((x) => x.count).fold(0, math.max);
    final labelEvery = math.max(1, (buckets.length / 6).ceil());
    final maxIndex = buckets.indexWhere((x) => x.count == maxCount);

    return SizedBox(
      height: 160,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < buckets.length; i++)
            Expanded(
              child: Tooltip(
                message: _tooltip(i),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: buckets.length > 40 ? 0.5 : 2,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SizedBox(
                        height: 14,
                        child:
                            (i == buckets.length - 1 || i == maxIndex) &&
                                buckets[i].count > 0
                            ? Text(
                                calendar.digits(buckets[i].count),
                                maxLines: 1,
                                overflow: TextOverflow.visible,
                                softWrap: false,
                                style: TextStyle(fontSize: 11, color: b.fg),
                              )
                            : null,
                      ),
                      const SizedBox(height: 4),
                      Container(
                        height: maxCount == 0
                            ? 1
                            : math.max(
                                buckets[i].count == 0 ? 1.0 : 3.0,
                                110 * buckets[i].count / maxCount,
                              ),
                        decoration: BoxDecoration(
                          color: buckets[i].count == 0
                              ? b.line
                              : i == buckets.length - 1
                              ? b.accent
                              : b.accent.withValues(alpha: 0.55),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 14,
                        child: i % labelEvery == 0
                            ? Text(
                                _label(buckets[i]),
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.visible,
                                style: TextStyle(fontSize: 10, color: b.muted),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Commits by weekday (rows, from the calendar's first weekday) and hour.
class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.summary, required this.calendar});

  final ReportSummary summary;
  final AppCalendar calendar;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final grid = summary.heatmap;
    var maxCount = 0;
    for (var d = 1; d <= 7; d++) {
      for (final v in grid[d]) {
        maxCount = math.max(maxCount, v);
      }
    }
    final names = calendar.weekdayNames;
    return Column(
      children: [
        for (var i = 0; i < 7; i++)
          Builder(
            builder: (context) {
              final weekday = (calendar.firstWeekday - 1 + i) % 7 + 1;
              return Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(
                        names[weekday - 1],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: b.muted),
                      ),
                    ),
                    for (var hour = 0; hour < 24; hour++)
                      Expanded(
                        child: Tooltip(
                          message:
                              '${names[weekday - 1]} '
                              '${calendar.digits(hour.toString().padLeft(2, '0'))}:00 · '
                              '${translate('report_n_commits').replaceAll('{n}', calendar.digits(grid[weekday][hour]))}',
                          child: Container(
                            height: 14,
                            margin: const EdgeInsetsDirectional.only(end: 2),
                            decoration: BoxDecoration(
                              color: maxCount == 0 || grid[weekday][hour] == 0
                                  ? b.hover
                                  : Color.lerp(
                                      b.accent.withValues(alpha: 0.25),
                                      b.accent,
                                      grid[weekday][hour] / maxCount,
                                    ),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        const SizedBox(height: 4),
        Row(
          children: [
            const SizedBox(width: 64),
            for (var hour = 0; hour < 24; hour++)
              Expanded(
                child: hour % 6 == 0 || hour == 23
                    ? Text(
                        calendar.digits(hour.toString().padLeft(2, '0')),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                        style: TextStyle(fontSize: 10, color: b.muted),
                      )
                    : const SizedBox(),
              ),
          ],
        ),
      ],
    );
  }
}

/// Preset chips plus a calendar chip that opens the custom range popover.
class _PeriodControl extends StatelessWidget {
  const _PeriodControl({
    super.key,
    required this.calendar,
    required this.period,
    required this.onPreset,
    required this.onCustom,
  });

  final AppCalendar calendar;
  final ReportPeriod period;
  final ValueChanged<PeriodPreset> onPreset;
  final VoidCallback onCustom;

  static const _chips = [
    PeriodPreset.last7Days,
    PeriodPreset.last30Days,
    PeriodPreset.last90Days,
    PeriodPreset.lastYear,
    PeriodPreset.all,
  ];

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final isCustom = !_chips.contains(period.preset);
    Widget chip({
      required String label,
      required bool on,
      required VoidCallback onTap,
      IconData? icon,
    }) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: on ? b.bg : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: on ? Border.all(color: b.line) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: on ? b.fg : b.muted),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: on ? b.fg : b.muted,
                fontWeight: on ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );

    String customLabel() {
      if (!isCustom) return '';
      if (period.preset != PeriodPreset.custom) {
        return presetLabel(period.preset);
      }
      return '${calendar.formatDay(period.from!)} – ${calendar.formatDay(period.to)}';
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: b.hover,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final preset in _chips) ...[
            chip(
              label: translate('report_chip_${preset.name}'),
              on: period.preset == preset,
              onTap: () => onPreset(preset),
            ),
            const SizedBox(width: 2),
          ],
          Tooltip(
            message: translate('report_custom_range'),
            child: chip(
              label: customLabel(),
              on: isCustom,
              icon: Icons.calendar_today_outlined,
              onTap: onCustom,
            ),
          ),
        ],
      ),
    );
  }
}

/// "All authors" / one author picker.
class _AuthorMenu extends StatelessWidget {
  const _AuthorMenu({
    required this.contributors,
    required this.selected,
    required this.selectedName,
    required this.onSelected,
  });

  final List<ContributorStat> contributors;
  final String? selected;
  final String? selectedName;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final label = selected == null
        ? translate('report_all_authors')
        : (selectedName ?? selected!);
    return PopupMenuButton<String>(
      tooltip: translate('report_author'),
      onSelected: (key) => onSelected(key.isEmpty ? null : key),
      itemBuilder: (context) => [
        PopupMenuItem(value: '', child: Text(translate('report_all_authors'))),
        if (contributors.isNotEmpty) const PopupMenuDivider(),
        for (final c in contributors)
          PopupMenuItem(
            value: c.key,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    c.name.isEmpty ? c.email : c.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  AppCalendarSettings.current.digits(c.commits),
                  style: TextStyle(fontSize: 12, color: b.muted),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border.all(color: b.line),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_outline, size: 16, color: b.fg),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: b.fg),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down, size: 14, color: b.muted),
          ],
        ),
      ),
    );
  }
}
