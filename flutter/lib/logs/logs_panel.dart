import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import 'action_log.dart';

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

/// The bottom logs panel: a timestamped list of git actions run through
/// [GitActions], newest first.
class LogsPanel extends StatelessWidget {
  const LogsPanel({super.key, required this.height, required this.onHeightChanged});

  final double height;
  final ValueChanged<double> onHeightChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PanelResizeHandle(
          onDrag: (delta) => onHeightChanged(
            (height + delta).clamp(kPanelMinHeight, kPanelMaxHeight),
          ),
        ),
        Container(
          height: height,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
          ),
          child: AnimatedBuilder(
            animation: ActionLog.instance,
            builder: (context, _) {
              final entries = ActionLog.instance.entries;
              if (entries.isEmpty) {
                return Center(
                  child: Text(
                    translate('no_logged_actions'),
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                );
              }
              return GestureDetector(
                onSecondaryTapUp: (details) =>
                    _showClearMenu(context, details.globalPosition),
                behavior: HitTestBehavior.translucent,
                child: ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        entry.success
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        size: 16,
                        color:
                            entry.success ? colorScheme.primary : colorScheme.error,
                      ),
                      title: Text(entry.action),
                      subtitle: entry.success ? null : Text(entry.detail ?? ''),
                      trailing: Text(_formatTimestamp(entry.timestamp)),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
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

  String _formatTimestamp(DateTime timestamp) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${twoDigits(timestamp.hour)}:${twoDigits(timestamp.minute)}:'
        '${twoDigits(timestamp.second)}';
  }
}
