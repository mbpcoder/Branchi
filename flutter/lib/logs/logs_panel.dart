import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import 'action_log.dart';

/// The bottom logs panel: a timestamped list of git actions run through
/// [GitActions], newest first.
class LogsPanel extends StatelessWidget {
  const LogsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 200,
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
          return ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return ListTile(
                dense: true,
                leading: Icon(
                  entry.success ? Icons.check_circle_outline : Icons.error_outline,
                  size: 16,
                  color: entry.success ? colorScheme.primary : colorScheme.error,
                ),
                title: Text(entry.action),
                subtitle: entry.success ? null : Text(entry.detail ?? ''),
                trailing: Text(_formatTimestamp(entry.timestamp)),
              );
            },
          );
        },
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${twoDigits(timestamp.hour)}:${twoDigits(timestamp.minute)}:'
        '${twoDigits(timestamp.second)}';
  }
}
