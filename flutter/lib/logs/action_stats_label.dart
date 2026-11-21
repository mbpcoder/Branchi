import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../theme/app_theme.dart';
import 'action_log.dart';

/// The counts beside a commit, pull or push in the Activity panel and the
/// footer: "2 commits  5 files  +120 −14", or "up to date" when nothing
/// moved.
class ActionStatsLabel extends StatelessWidget {
  const ActionStatsLabel({super.key, required this.stats, this.compact = false});

  final ActionStats stats;

  /// Plain text without chip backgrounds, for the 32px footer.
  final bool compact;

  static String _count(int n, String key) => n == 1
      ? translate('${key}_one')
      : translate('${key}_n').replaceAll('{n}', '$n');

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final style = TextStyle(
      fontSize: 12,
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
      color: b.muted,
    );

    if (stats.isUpToDate) {
      return Text(translate('activity_up_to_date'), style: style);
    }

    Widget chip(String text) => compact
        ? Text(text, style: style)
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: b.hover,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(text, style: style),
          );

    final commits = stats.commits;
    final parts = <Widget>[
      if (commits != null) chip(_count(commits, 'activity_commits')),
      chip(_count(stats.files, 'activity_files')),
      Text('+${stats.insertions}', style: style.copyWith(color: b.add)),
      Text('−${stats.deletions}', style: style.copyWith(color: b.del)),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) SizedBox(width: compact ? 6 : 8),
          parts[i],
        ],
      ],
    );
  }
}
