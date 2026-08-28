import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../l10n/translations.dart';
import 'terminal_session.dart';

/// The bottom terminal panel: a row of terminal tabs plus the active
/// session's [TerminalView].
class TerminalPanel extends StatelessWidget {
  const TerminalPanel({
    super.key,
    required this.sessions,
    required this.activeIndex,
    required this.onSelect,
    required this.onClose,
    required this.onAddTab,
  });

  final List<TerminalSession> sessions;
  final int activeIndex;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;
  final VoidCallback onAddTab;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 32,
            child: Row(
              children: [
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: sessions.length,
                    itemBuilder: (context, index) {
                      final session = sessions[index];
                      final isActive = index == activeIndex;
                      return InkWell(
                        onTap: () => onSelect(index),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: isActive
                                ? colorScheme.surfaceContainerHighest
                                : Colors.transparent,
                            border: Border(
                              right:
                                  BorderSide(color: colorScheme.outlineVariant),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                session.title,
                                style: TextStyle(
                                  fontWeight: isActive
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () => onClose(index),
                                child: const Icon(Icons.close, size: 16),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                IconButton(
                  tooltip: translate('new_tab'),
                  icon: const Icon(Icons.add),
                  onPressed: onAddTab,
                ),
              ],
            ),
          ),
          Expanded(
            child: sessions.isEmpty
                ? const SizedBox.shrink()
                : TerminalView(
                    key: ValueKey(sessions[activeIndex].id),
                    sessions[activeIndex].terminal,
                    autofocus: true,
                  ),
          ),
        ],
      ),
    );
  }
}
