import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../models/repo_tab.dart';
import '../theme/app_theme.dart';

/// Slim strip of open tabs, always shown under the top bar, with an
/// "add tab" button right after the last tab. Middle-click a tab to close it.
class TabBarRow extends StatelessWidget {
  const TabBarRow({
    super.key,
    required this.tabs,
    required this.activeIndex,
    required this.onSelect,
    required this.onClose,
    required this.onAddTab,
  });

  static const double height = 34;

  final List<RepoTab> tabs;
  final int activeIndex;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;
  final VoidCallback onAddTab;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: b.bg,
        border: Border(bottom: BorderSide(color: b.line)),
      ),
      // The "add tab" button is the list's last item, so it sits right
      // after the last open tab and scrolls with the tabs.
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
            active: index == activeIndex,
            onTap: () => onSelect(index),
            onClose: () => onClose(index),
          );
        },
      ),
    );
  }
}

class _Tab extends StatefulWidget {
  const _Tab({
    required this.title,
    required this.active,
    required this.onTap,
    required this.onClose,
  });

  final String title;
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
              ConstrainedBox(
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
