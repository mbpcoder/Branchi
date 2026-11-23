import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_calendar.dart';

import '../l10n/app_locale.dart';
import 'action_log.dart';
import 'action_stats_label.dart';
import '../shortcuts/app_shortcuts.dart';
import '../theme/app_theme.dart';

/// Minimum and maximum drag-resize height for the logs/terminal panels.
const double kPanelMinHeight = 80;
const double kPanelMaxHeight = 600;

/// A thin draggable handle drawn above a bottom panel, letting the user
/// resize it by dragging vertically.
class PanelResizeHandle extends StatelessWidget {
  const PanelResizeHandle({super.key, required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: (details) => onDrag(-details.delta.dy),
        child: SizedBox(
          height: 6,
          child: Center(
            child: Container(
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              color: colorScheme.outlineVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// The − button that closes a bottom panel, at the end of its header.
class PanelHideButton extends StatelessWidget {
  const PanelHideButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
  });

  /// The panel's shortcut, e.g. "Alt+F12".
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: IconButton(
        tooltip: '${translate('hide_panel')} ($tooltip)',
        icon: Icon(Icons.remove, size: 16, color: b.muted),
        constraints: const BoxConstraints.tightFor(width: 26, height: 26),
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(minimumSize: const Size(26, 26)),
        onPressed: onPressed,
      ),
    );
  }
}

/// The bottom logs panel: git actions run through [GitActions], newest
/// first, grouped by day ("Today", "Yesterday", "Sep 8, 2026"). Today's
/// recent actions show a relative time ("4 min ago"); hovering a time shows
/// the exact one.
class LogsPanel extends StatefulWidget {
  const LogsPanel({
    super.key,
    required this.height,
    required this.onHeightChanged,
    required this.onHide,
  });

  final double height;
  final ValueChanged<double> onHeightChanged;

  /// Closes the panel (the − button).
  final VoidCallback onHide;

  @override
  State<LogsPanel> createState() => _LogsPanelState();
}

class _LogsPanelState extends State<LogsPanel> {
  /// Keeps "4 min ago" current.
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(seconds: 30),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PanelResizeHandle(
          onDrag: (delta) => widget.onHeightChanged(
            (widget.height + delta).clamp(kPanelMinHeight, kPanelMaxHeight),
          ),
        ),
        Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: b.bg,
            border: Border(top: b.hairline),
          ),
          child: Column(
            children: [
              SizedBox(
                height: 32,
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        translate('activity').toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          color: b.muted,
                          letterSpacing: 0.44,
                        ),
                      ),
                    ),
                    PanelHideButton(
                      tooltip: AppShortcuts.label(AppShortcut.activity),
                      onPressed: widget.onHide,
                    ),
                  ],
                ),
              ),
              Expanded(child: _entries(context)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _entries(BuildContext context) {
    final b = context.branchi;
    return ListenableBuilder(
      listenable: Listenable.merge([
        ActionLog.instance,
        AppCalendarSettings.preference,
      ]),
      builder: (context, _) {
        final entries = ActionLog.instance.entries;
        if (entries.isEmpty) {
          return Center(
            child: Text(
              translate('no_logged_actions'),
              style: TextStyle(color: b.muted),
            ),
          );
        }
        final now = DateTime.now();
        final cal = AppCalendarSettings.current;
        // Day headers between the entries: a String is a header,
        // an ActionLogEntry a row.
        final items = <Object>[];
        DateTime? day;
        for (final entry in entries) {
          final t = entry.timestamp;
          final entryDay = DateTime(t.year, t.month, t.day);
          if (entryDay != day) {
            day = entryDay;
            items.add(_dayLabel(entryDay, now, cal));
          }
          items.add(entry);
        }
        return GestureDetector(
          onSecondaryTapUp: (details) =>
              _showClearMenu(context, details.globalPosition),
          behavior: HitTestBehavior.translucent,
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 8),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              if (item is String) {
                return Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 4),
                  child: Text(
                    item.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      color: b.muted,
                      letterSpacing: 0.44,
                    ),
                  ),
                );
              }
              return _row(context, item as ActionLogEntry, now, cal);
            },
          ),
        );
      },
    );
  }

  Widget _row(
    BuildContext context,
    ActionLogEntry entry,
    DateTime now,
    AppCalendar cal,
  ) {
    final b = context.branchi;
    final detail = entry.success ? null : entry.detail;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                entry.success ? Icons.check : Icons.close,
                size: 14,
                color: entry.success ? b.add : b.del,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  entry.action,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: b.fg),
                ),
              ),
              if (entry.stats != null) ...[
                const SizedBox(width: 10),
                ActionStatsLabel(stats: entry.stats!),
              ],
              const SizedBox(width: 8),
              Tooltip(
                message: cal.digits(_clock(entry.timestamp, seconds: true)),
                child: Text(
                  '· ${_time(entry.timestamp, now, cal)}',
                  style: TextStyle(fontSize: 12, color: b.muted),
                ),
              ),
            ],
          ),
          if (detail != null && detail.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 24, top: 2),
              child: Text(detail, style: TextStyle(fontSize: 12, color: b.del)),
            ),
        ],
      ),
    );
  }

  static String _dayLabel(DateTime day, DateTime now, AppCalendar cal) {
    final today = DateTime(now.year, now.month, now.day);
    final daysAgo = today.difference(day).inDays;
    if (daysAgo == 0) return translate('activity_today');
    if (daysAgo == 1) return translate('activity_yesterday');
    return cal.formatDate(day);
  }

  /// "just now" / "4 min ago" within the last hour, else "14:32".
  static String _time(DateTime time, DateTime now, AppCalendar cal) {
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return translate('activity_just_now');
    if (diff.inMinutes < 60) {
      return translate(
        'report_ago_minutes',
      ).replaceAll('{n}', cal.digits(diff.inMinutes));
    }
    return cal.digits(_clock(time));
  }

  static String _clock(DateTime t, {bool seconds = false}) {
    String two(int v) => v.toString().padLeft(2, '0');
    final hm = '${two(t.hour)}:${two(t.minute)}';
    return seconds ? '$hm:${two(t.second)}' : hm;
  }

  Future<void> _showClearMenu(BuildContext context, Offset position) async {
    final selection = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(value: 'clear', child: Text(translate('clear_logs'))),
      ],
    );
    if (selection == 'clear') {
      ActionLog.instance.clear();
    }
  }
}
