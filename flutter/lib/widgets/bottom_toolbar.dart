import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../logs/action_log.dart';
import '../logs/action_stats_label.dart';
import '../theme/app_theme.dart';

/// The 32px footer: the most recent git action (status dot, action, time)
/// on the left, with its change counts, opening the Activity panel when
/// clicked; the active file's type and the Activity (logs) and
/// Terminal toggles on the right.
class BottomToolbar extends StatelessWidget {
  const BottomToolbar({
    super.key,
    required this.isTerminalOpen,
    required this.onToggleTerminal,
    required this.isLogsOpen,
    required this.onToggleLogs,
    this.fileTypeLabel,
  });

  final bool isTerminalOpen;
  final VoidCallback onToggleTerminal;
  final bool isLogsOpen;
  final VoidCallback onToggleLogs;

  /// The active editor tab's detected file type, e.g. "PHP". `null` when no
  /// file is open or the Files section isn't active.
  final String? fileTypeLabel;

  static String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final textStyle = TextStyle(fontSize: 12, color: b.muted);
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: b.bg,
        border: Border(top: BorderSide(color: b.line)),
      ),
      child: DefaultTextStyle.merge(
        style: textStyle,
        child: Row(
          children: [
            Expanded(
              child: ListenableBuilder(
                listenable: ActionLog.instance,
                builder: (context, _) {
                  final entries = ActionLog.instance.entries;
                  if (entries.isEmpty) {
                    return Text(translate('ready'), style: textStyle);
                  }
                  final last = entries.first;
                  return Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Tooltip(
                      message: last.detail ?? last.action,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: isLogsOpen ? null : onToggleLogs,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: last.success ? b.add : b.del,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  last.action,
                                  overflow: TextOverflow.ellipsis,
                                  style: textStyle,
                                ),
                              ),
                              if (last.stats != null) ...[
                                const SizedBox(width: 8),
                                ActionStatsLabel(
                                  stats: last.stats!,
                                  compact: true,
                                ),
                              ],
                              Text(
                                ' · ${_time(last.timestamp)}',
                                style: textStyle,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (fileTypeLabel != null) ...[
              Text(fileTypeLabel!, style: textStyle),
              const SizedBox(width: 16),
            ],
            _FooterToggle(
              label: translate('activity'),
              selected: isLogsOpen,
              onTap: onToggleLogs,
            ),
            const SizedBox(width: 8),
            _FooterToggle(
              label: translate('terminal'),
              selected: isTerminalOpen,
              onTap: onToggleTerminal,
            ),
          ],
        ),
      ),
    );
  }
}

class _FooterToggle extends StatelessWidget {
  const _FooterToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? b.hover : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 12, color: selected ? b.fg : b.muted),
        ),
      ),
    );
  }
}
