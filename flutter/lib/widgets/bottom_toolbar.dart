import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';

/// The thin bottom strip holding the terminal and logs toggle buttons.
class BottomToolbar extends StatelessWidget {
  const BottomToolbar({
    super.key,
    required this.isTerminalOpen,
    required this.onToggleTerminal,
    required this.isLogsOpen,
    required this.onToggleLogs,
  });

  final bool isTerminalOpen;
  final VoidCallback onToggleTerminal;
  final bool isLogsOpen;
  final VoidCallback onToggleLogs;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 32,
      color: colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          IconButton(
            iconSize: 18,
            tooltip: translate('terminal'),
            isSelected: isTerminalOpen,
            style: IconButton.styleFrom(
              padding: EdgeInsets.zero,
              backgroundColor:
                  isTerminalOpen ? colorScheme.surface : Colors.transparent,
            ),
            icon: const Icon(Icons.terminal),
            onPressed: onToggleTerminal,
          ),
          IconButton(
            iconSize: 18,
            tooltip: translate('logs'),
            isSelected: isLogsOpen,
            style: IconButton.styleFrom(
              padding: EdgeInsets.zero,
              backgroundColor:
                  isLogsOpen ? colorScheme.surface : Colors.transparent,
            ),
            icon: const Icon(Icons.receipt_long),
            onPressed: onToggleLogs,
          ),
        ],
      ),
    );
  }
}
