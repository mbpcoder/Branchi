import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../models/repo_tab.dart';
import '../shortcuts/app_shortcuts.dart';
import '../theme/app_theme.dart';

/// Strip of open tabs with an "add tab" button right after the last tab.
/// Middle-click a tab to close it. With [embedded] it draws no bar of its
/// own, for placing inside the top bar's first row.
class TabBarRow extends StatelessWidget {
  const TabBarRow({
    super.key,
    required this.tabs,
    required this.activeIndex,
    required this.onSelect,
    required this.onClose,
    required this.onAddTab,
    this.embedded = false,
  });

  static const double height = 34;

  final List<RepoTab> tabs;
  final int activeIndex;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;
  final VoidCallback onAddTab;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    // The "add tab" button is the list's last item, so it sits right
    // after the last open tab and scrolls with the tabs.
    final list = SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length + 1,
        padding: const EdgeInsets.symmetric(vertical: 4),
        separatorBuilder: (_, __) => const SizedBox(width: 2),
        itemBuilder: (context, index) {
          if (index == tabs.length) {
            return Center(
              child: IconButton(
                tooltip: translate('new_tab'),
                icon: const Icon(Icons.add, size: 14),
                constraints:
                    const BoxConstraints.tightFor(width: 26, height: 26),
                style: IconButton.styleFrom(minimumSize: const Size(26, 26)),
                onPressed: onAddTab,
              ),
            );
          }
          return _Tab(
            title: tabs[index].title,
            shortcut: AppShortcuts.tabLabel(index),
            active: index == activeIndex,
            onTap: () => onSelect(index),
            onClose: () => onClose(index),
          );
        },
      ),
    );
    if (embedded) return list;
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: b.bg,
        border: Border(bottom: BorderSide(color: b.line)),
      ),
      child: list,
    );
  }
}

class _Tab extends StatefulWidget {
  const _Tab({
    required this.title,
    this.shortcut,
    required this.active,
    required this.onTap,
    required this.onClose,
  });

  final String title;

  /// "Alt+3", shown in the tab's tooltip.
  final String? shortcut;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        // Middle-click closes the tab, as in browsers.
        onTertiaryTapUp: (_) => widget.onClose(),
        child: Container(
          padding: const EdgeInsets.only(left: 10, right: 4),
          decoration: BoxDecoration(
            color: widget.active || _hovered ? b.hover : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: widget.shortcut == null
                    ? widget.title
                    : '${widget.title} (${widget.shortcut})',
                waitDuration: const Duration(milliseconds: 500),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Text(
                    widget.title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: widget.active ? b.fg : b.muted,
                      fontWeight:
                          widget.active ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: translate('close_tab'),
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: widget.onClose,
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Icon(
                      Icons.close,
                      size: 12,
                      color: widget.active || _hovered
                          ? b.muted
                          : Colors.transparent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
