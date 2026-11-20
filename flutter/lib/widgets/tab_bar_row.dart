import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../models/repo_tab.dart';
import '../theme/app_theme.dart';

/// Slim strip of open repository tabs, shown under the top bar only while
/// more than one tab is open (the top bar's repo switcher covers the
/// single-tab case), with a trailing "add tab" button.
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
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              padding: const EdgeInsets.symmetric(vertical: 4),
              separatorBuilder: (_, __) => const SizedBox(width: 2),
              itemBuilder: (context, index) => _Tab(
                title: tabs[index].title,
                active: index == activeIndex,
                onTap: () => onSelect(index),
                onClose: () => onClose(index),
              ),
            ),
          ),
          IconButton(
            tooltip: translate('new_tab'),
            icon: const Icon(Icons.add, size: 14),
            constraints: const BoxConstraints.tightFor(width: 26, height: 26),
            style: IconButton.styleFrom(minimumSize: const Size(26, 26)),
            onPressed: onAddTab,
          ),
        ],
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
