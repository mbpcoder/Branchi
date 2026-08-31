import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../l10n/app_locale.dart';
import '../logs/logs_panel.dart' show PanelResizeHandle, kPanelMinHeight, kPanelMaxHeight;
import 'terminal_session.dart';

/// The bottom terminal panel: a row of terminal tabs plus the active
/// session's [TerminalView].
class TerminalPanel extends StatefulWidget {
  const TerminalPanel({
    super.key,
    required this.sessions,
    required this.activeIndex,
    required this.onSelect,
    required this.onClose,
    required this.onAddTab,
    required this.height,
    required this.onHeightChanged,
  });

  final List<TerminalSession> sessions;
  final int activeIndex;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;
  final VoidCallback onAddTab;
  final double height;
  final ValueChanged<double> onHeightChanged;

  @override
  State<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<TerminalPanel> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _requestFocus();
  }

  @override
  void didUpdateWidget(covariant TerminalPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sessions.isNotEmpty &&
        (oldWidget.activeIndex != widget.activeIndex ||
            oldWidget.sessions.length != widget.sessions.length)) {
      _requestFocus();
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  /// Explicitly grabs keyboard focus once the terminal has finished
  /// building. `autofocus` alone isn't enough here: the toolbar button
  /// that opens/switches the terminal already holds focus from the tap
  /// that triggered this rebuild, and Flutter's autofocus only applies
  /// when nothing in the scope currently has focus.
  void _requestFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  List<TerminalSession> get sessions => widget.sessions;
  int get activeIndex => widget.activeIndex;
  ValueChanged<int> get onSelect => widget.onSelect;
  ValueChanged<int> get onClose => widget.onClose;
  VoidCallback get onAddTab => widget.onAddTab;
  double get height => widget.height;
  ValueChanged<double> get onHeightChanged => widget.onHeightChanged;

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
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? colorScheme.surfaceContainerHighest
                                    : Colors.transparent,
                                border: Border(
                                  right: BorderSide(
                                      color: colorScheme.outlineVariant),
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
                    : GestureDetector(
                        onTap: () => _focusNode.requestFocus(),
                        child: TerminalView(
                          key: ValueKey(sessions[activeIndex].id),
                          sessions[activeIndex].terminal,
                          focusNode: _focusNode,
                          autofocus: true,
                          // This is a desktop-only terminal, so keystrokes
                          // should always come from the hardware keyboard.
                          // Routing through the platform IME/text-input
                          // connection instead is what causes input to stop
                          // working after certain keys (e.g. Enter) on some
                          // platforms.
                          hardwareKeyboardOnly: true,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
