import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../models/repo_tab.dart';
import '../repo/git_actions.dart';
import '../repo/repo_controller.dart';
import '../shortcuts/app_shortcuts.dart';
import '../theme/app_theme.dart';
import 'auto_pull_button.dart';
import 'tab_bar_row.dart';

/// Height of the first row of [AppTopBar] (title + tabs).
const double kAppTopBarHeight = 44;

/// Height of the active repository's toolbar, the second row.
const double kRepoToolbarHeight = 46;

/// The window's top area, outermost first:
///
/// 1. `Branchi  [tab] [tab] [+]  …  ☾ 📌 ⚙` - the open tabs, with the
///    app-wide buttons.
/// 2. `[branch]  [History | Changes N | Files | Report]  …
///    [● Auto 1:42 ▾]  Fetch  Pull  [Push]` - the selected tab's
///    repository toolbar; only when that tab has a repository open
///    ([controller] non-null).
///
/// Everything under the tabs belongs to the selected tab.
class AppTopBar extends StatelessWidget {
  const AppTopBar({
    super.key,
    required this.tabs,
    required this.activeIndex,
    required this.onSelectTab,
    required this.onCloseTab,
    required this.onAddTab,
    required this.controller,
    required this.onOpenSettings,
    required this.isDark,
    required this.onToggleTheme,
    required this.isPinned,
    required this.onTogglePin,
  });

  final List<RepoTab> tabs;
  final int activeIndex;
  final ValueChanged<int> onSelectTab;
  final ValueChanged<int> onCloseTab;
  final VoidCallback onAddTab;

  /// The active tab's repository controller; `null` on a start-page tab.
  final RepoController? controller;

  final VoidCallback onOpenSettings;
  final bool isDark;
  final VoidCallback onToggleTheme;
  final bool isPinned;
  final VoidCallback onTogglePin;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTitleRow(context),
        if (controller != null)
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => _buildRepoToolbar(context, controller),
          ),
      ],
    );
  }

  Widget _buildTitleRow(BuildContext context) {
    final b = context.branchi;
    return Container(
      height: kAppTopBarHeight,
      padding: const EdgeInsetsDirectional.only(start: 20, end: 12),
      decoration: BoxDecoration(
        color: b.bg,
        border: Border(bottom: BorderSide(color: b.line)),
      ),
      child: Row(
        children: [
          Text(
            'Branchi',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              letterSpacing: -0.13,
              color: b.fg,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: TabBarRow(
              tabs: tabs,
              activeIndex: activeIndex,
              onSelect: onSelectTab,
              onClose: onCloseTab,
              onAddTab: onAddTab,
              embedded: true,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: isDark
                ? translate('switch_to_light_mode')
                : translate('switch_to_dark_mode'),
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            ),
            onPressed: onToggleTheme,
          ),
          IconButton(
            tooltip: isPinned
                ? translate('unpin_window')
                : translate('pin_window'),
            icon: Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined),
            onPressed: onTogglePin,
          ),
          IconButton(
            tooltip: translate('settings'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: onOpenSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildRepoToolbar(BuildContext context, RepoController controller) {
    final b = context.branchi;
    return Container(
      height: kRepoToolbarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: b.bg,
        border: Border(bottom: BorderSide(color: b.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(child: _BranchPill(controller: controller)),
                const SizedBox(width: 24),
                _SectionTabs(controller: controller),
              ],
            ),
          ),
          AutoPullButton(
            watcher: controller.watcher,
            isBusy: controller.isPulling,
          ),
          const SizedBox(width: 12),
          _RemoteActions(controller: controller),
        ],
      ),
    );
  }
}

/// The current-branch pill; opens a local-branch switcher.
class _BranchPill extends StatelessWidget {
  const _BranchPill({required this.controller});

  final RepoController controller;

  Future<void> _checkout(BuildContext context, String name) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final result = await controller.checkout(name);
    if (!result.isSuccess) {
      messenger?.showSnackBar(SnackBar(content: Text(result.error!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final current = controller.currentBranch;
    final local = controller.branches.where((br) => !br.isRemote).toList()
      ..sort((x, y) => x.name.compareTo(y.name));
    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      style: const MenuStyle(minimumSize: WidgetStatePropertyAll(Size(200, 0))),
      menuChildren: [
        for (final branch in local)
          MenuItemButton(
            onPressed: branch.isHead
                ? null
                : () => _checkout(context, branch.name),
            leadingIcon: SizedBox(
              width: 14,
              child: branch.isHead
                  ? Icon(Icons.check, size: 14, color: b.accent)
                  : null,
            ),
            child: Text(
              branch.name,
              style: b.mono(
                fontSize: 12,
                color: branch.isHead ? b.fg : b.muted,
              ),
            ),
          ),
      ],
      builder: (context, menu, _) => _HoverBox(
        tooltip: translate('switch_branch'),
        onTap: local.isEmpty
            ? null
            : () => menu.isOpen ? menu.close() : menu.open(),
        borderRadius: 999,
        border: true,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.call_split, size: 12, color: b.muted),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text(
                current ?? '—',
                overflow: TextOverflow.ellipsis,
                style: b.mono(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `[History | Changes N | Files]` segmented control.
class _SectionTabs extends StatelessWidget {
  const _SectionTabs({required this.controller});

  final RepoController controller;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    Widget segment(
      RepoSection section,
      String label,
      AppShortcut shortcut, {
      int? count,
    }) {
      final selected = controller.section == section;
      return Tooltip(
        message: AppShortcuts.label(shortcut),
        waitDuration: const Duration(milliseconds: 500),
        child: GestureDetector(
        onTap: () => controller.section = section,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: selected ? b.bg : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? b.fg : b.muted,
                    fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
                if (count != null && count > 0) ...[
                  const SizedBox(width: 5),
                  Text('$count', style: TextStyle(color: b.accent)),
                ],
              ],
            ),
          ),
        ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: b.hover,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          segment(RepoSection.history, translate('history'),
              AppShortcut.history),
          const SizedBox(width: 4),
          segment(
            RepoSection.changes,
            translate('changes'),
            AppShortcut.changes,
            count: controller.changesCount,
          ),
          const SizedBox(width: 4),
          segment(RepoSection.files, translate('files'), AppShortcut.files),
          const SizedBox(width: 4),
          segment(RepoSection.report, translate('report'), AppShortcut.report),
        ],
      ),
    );
  }
}

/// Fetch / Pull / [Push] buttons, backed by [RepoController] (which calls
/// [GitActions]). Failures are shown in a snackbar; every run is recorded
/// in the action log (shown in the footer and the logs panel).
class _RemoteActions extends StatelessWidget {
  const _RemoteActions({required this.controller});

  final RepoController controller;

  Future<void> _run(
    BuildContext context,
    Future<GitActionResult> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final result = await action();
    if (!result.isSuccess) {
      messenger?.showSnackBar(SnackBar(content: Text(result.error!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final hasBranch = controller.currentBranch != null;

    Widget label(String text, bool busy, Color color) {
      if (!busy) return Text(text);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
          ),
          const SizedBox(width: 6),
          Text(text),
        ],
      );
    }

    final quiet = TextButton.styleFrom(
      foregroundColor: b.muted,
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: translate('fetch_tooltip'),
          child: TextButton(
            style: quiet,
            onPressed: controller.isFetching
                ? null
                : () => _run(context, controller.fetch),
            child: label(translate('fetch'), controller.isFetching, b.muted),
          ),
        ),
        const SizedBox(width: 4),
        Tooltip(
          message: translate('pull_tooltip'),
          child: TextButton(
            style: quiet,
            onPressed: controller.isPulling || !hasBranch
                ? null
                : () => _run(context, controller.pull),
            child: label(translate('pull'), controller.isPulling, b.muted),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: translate('push_tooltip'),
          child: FilledButton(
            onPressed: controller.isPushing || !hasBranch
                ? null
                : () => _run(context, controller.push),
            child: label(translate('push'), controller.isPushing, b.bg),
          ),
        ),
      ],
    );
  }
}

/// A small hoverable, clickable box with a 6px (or pill) radius.
class _HoverBox extends StatefulWidget {
  const _HoverBox({
    required this.child,
    required this.onTap,
    this.tooltip,
    this.padding = EdgeInsets.zero,
    this.borderRadius = 6,
    this.border = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? tooltip;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final bool border;

  @override
  State<_HoverBox> createState() => _HoverBoxState();
}

class _HoverBoxState extends State<_HoverBox> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    Widget box = MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: widget.padding,
          decoration: BoxDecoration(
            color: _hovered && widget.onTap != null
                ? b.hover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: widget.border ? Border.all(color: b.line) : null,
          ),
          child: widget.child,
        ),
      ),
    );
    if (widget.tooltip != null) {
      box = Tooltip(message: widget.tooltip!, child: box);
    }
    return box;
  }
}
