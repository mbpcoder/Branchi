import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_locale.dart';
import '../theme/app_theme.dart';
import 'file_explorer.dart';
import 'git_actions.dart';
import 'models.dart';
import 'remotes_dialog.dart';

/// Auto-refresh interval choices offered by the watch dropdown, in minutes.
const List<int> kBranchWatchIntervalsMinutes = [1, 2, 3, 4, 5, 10, 15, 30, 45, 60];

String branchWatchIntervalLabel(int minutes) {
  if (minutes == 60) return '1 hour';
  if (minutes == 1) return '1 minute';
  return '$minutes minutes';
}

// Dismissing the menu without picking anything also resolves to `null` from
// showMenu, so "off" is modeled as this sentinel instead of `null` to tell
// an explicit choice apart from a dismissal.
const int kBranchWatchOffValue = -1;

/// Shows the auto-refresh interval picker anchored at [position], with the
/// currently active [currentIntervalMinutes] checked. Returns the chosen
/// interval in minutes, or `null` for "off"/"disabled", or leaves the
/// current selection untouched if the menu is dismissed.
Future<int?> showBranchWatchIntervalMenu(
  BuildContext context,
  Offset position, {
  required int? currentIntervalMinutes,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final currentValue = currentIntervalMinutes ?? kBranchWatchOffValue;
  final selected = await showMenu<int>(
    context: context,
    position: RelativeRect.fromRect(
      position & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    initialValue: currentValue,
    items: [
      for (final minutes in kBranchWatchIntervalsMinutes)
        PopupMenuItem<int>(
          value: minutes,
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: minutes == currentValue
                    ? const Icon(Icons.check, size: 16)
                    : null,
              ),
              Text(branchWatchIntervalLabel(minutes)),
            ],
          ),
        ),
      const PopupMenuDivider(),
      PopupMenuItem<int>(
        value: kBranchWatchOffValue,
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: currentValue == kBranchWatchOffValue
                  ? const Icon(Icons.check, size: 16)
                  : null,
            ),
            const Text('Off'),
          ],
        ),
      ),
    ],
  );
  if (selected == null) return currentIntervalMinutes;
  return selected == kBranchWatchOffValue ? null : selected;
}

/// Left-hand sidebar listing local and remote branches for the open repo,
/// with collapsible sections and per-branch checkout/delete/update actions.
class BranchSidebar extends StatefulWidget {
  const BranchSidebar({
    super.key,
    required this.repoPath,
    required this.branches,
    required this.onChanged,
    required this.watchIntervalMinutes,
    required this.onWatchIntervalChanged,
    required this.isUpdatingCurrentBranch,
    required this.onUpdateCurrentBranch,
    this.onOpenInTerminal,
    this.width = 220,
  });

  final String repoPath;
  final List<BranchEntry> branches;

  /// Opens a new built-in terminal tab in the repository folder. The menu
  /// item is hidden when this is null.
  final VoidCallback? onOpenInTerminal;

  /// Called after a branch action (checkout/create/delete/update) succeeds,
  /// so the caller can reload the repository's commits and branches.
  final VoidCallback onChanged;

  /// The currently active auto-refresh interval in minutes, or `null` if
  /// auto-refresh is off. Owned by the parent so it keeps running even when
  /// this sidebar isn't mounted (e.g. while the Code tab is active).
  final int? watchIntervalMinutes;
  final ValueChanged<int?> onWatchIntervalChanged;

  final bool isUpdatingCurrentBranch;
  final VoidCallback onUpdateCurrentBranch;

  final double width;

  @override
  State<BranchSidebar> createState() => _BranchSidebarState();
}

/// How the sidebar orders branches within each group.
enum BranchSort {
  name,

  /// Newest last commit first. (Git doesn't record when a branch was
  /// created, so recent activity is the closest useful order.)
  lastCommit,
}

/// Orders [branches] by [sort]; names break ties, case-insensitively.
List<BranchEntry> sortBranches(List<BranchEntry> branches, BranchSort sort) {
  int byName(BranchEntry a, BranchEntry b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
  return List.of(branches)
    ..sort((a, b) {
      if (sort == BranchSort.lastCommit) {
        final at = a.lastCommitTime;
        final bt = b.lastCommitTime;
        if (at != null && bt != null && at != bt) return bt.compareTo(at);
        if ((at == null) != (bt == null)) return at == null ? 1 : -1;
      }
      return byName(a, b);
    });
}

class _BranchSidebarState extends State<BranchSidebar> {
  static const _sortKeyPrefix = 'branchi_branch_sort_';
  BranchSort _sort = BranchSort.name;

  bool _localExpanded = true;
  bool _remoteExpanded = true;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadSort();
  }

  @override
  void didUpdateWidget(covariant BranchSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repoPath != widget.repoPath) _loadSort();
  }

  Future<void> _loadSort() async {
    final repo = widget.repoPath;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_sortKeyPrefix + repo);
      if (!mounted || repo != widget.repoPath) return;
      setState(() {
        _sort = BranchSort.values.firstWhere(
          (v) => v.name == saved,
          orElse: () => BranchSort.name,
        );
      });
    } catch (_) {
      // Keep the default order.
    }
  }

  Future<void> _setSort(BranchSort sort) async {
    setState(() => _sort = sort);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sortKeyPrefix + widget.repoPath, sort.name);
    } catch (_) {
      // Applies for now; not remembered.
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _searchQuery = '';
      }
    });
  }

  Future<void> _selectWatchInterval(Offset position) async {
    final newInterval = await showBranchWatchIntervalMenu(
      context,
      position,
      currentIntervalMinutes: widget.watchIntervalMinutes,
    );
    if (!mounted || newInterval == widget.watchIntervalMinutes) return;
    widget.onWatchIntervalChanged(newInterval);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openInFileExplorer() async {
    final error = await openInFileExplorer(widget.repoPath);
    if (error != null) _showError(error);
  }

  String _shortRemoteName(String remoteBranchName) {
    final slash = remoteBranchName.indexOf('/');
    return slash == -1
        ? remoteBranchName
        : remoteBranchName.substring(slash + 1);
  }

  /// Double-clicking a local branch switches to it directly. Double-clicking
  /// a remote branch switches to its local counterpart if one already
  /// exists, otherwise prompts to create one first.
  Future<void> _checkout(BranchEntry branch) async {
    if (branch.isHead) return;

    if (!branch.isRemote) {
      final result = await GitActions.checkoutBranch(widget.repoPath, branch.name);
      if (!mounted) return;
      if (result.isSuccess) {
        widget.onChanged();
      } else {
        _showError(result.error!);
      }
      return;
    }

    final shortName = _shortRemoteName(branch.name);
    final hasLocalCounterpart =
        widget.branches.any((b) => !b.isRemote && b.name == shortName);

    if (hasLocalCounterpart) {
      final result = await GitActions.checkoutBranch(widget.repoPath, shortName);
      if (!mounted) return;
      if (result.isSuccess) {
        widget.onChanged();
      } else {
        _showError(result.error!);
      }
      return;
    }

    final newName = await _promptCreateLocalBranch(shortName);
    if (newName == null || !mounted) return;

    final createResult = await GitActions.createBranch(
      widget.repoPath,
      newName,
      from: branch.name,
    );
    if (!mounted) return;
    if (!createResult.isSuccess) {
      _showError(createResult.error!);
      return;
    }

    final checkoutResult = await GitActions.checkoutBranch(widget.repoPath, newName);
    if (!mounted) return;
    if (checkoutResult.isSuccess) {
      widget.onChanged();
    } else {
      _showError(checkoutResult.error!);
    }
  }

  Future<String?> _promptCreateLocalBranch(String suggestedName) {
    final controller = TextEditingController(text: suggestedName);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('No local branch exists'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'New branch name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) Navigator.pop(dialogContext, name);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(BranchEntry branch) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          branch.isRemote
              ? translate('branch_delete_remote_title')
                  .replaceAll('{remote}', branch.name.split('/').first)
              : 'Delete branch',
        ),
        content: Text(
          branch.isRemote
              ? translate('branch_delete_remote_body')
                  .replaceAll('{branch}', branch.name)
              : 'Delete branch "${branch.name}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final result = await GitActions.deleteBranch(
      widget.repoPath,
      branch.name,
      isRemote: branch.isRemote,
    );
    if (!mounted) return;
    if (result.isSuccess) {
      widget.onChanged();
    } else {
      _showError(result.error!);
    }
  }

  Future<void> _update(BranchEntry branch) async {
    final result = await GitActions.updateBranch(
      widget.repoPath,
      branch.name,
      isRemote: branch.isRemote,
    );
    if (!mounted) return;
    if (result.isSuccess) {
      widget.onChanged();
    } else {
      _showError(result.error!);
    }
  }

  Future<void> _push(BranchEntry branch) async {
    final result = await GitActions.push(widget.repoPath, branch.name);
    if (!mounted) return;
    if (result.isSuccess) {
      widget.onChanged();
    } else {
      _showError(result.error!);
    }
  }

  Future<void> _showContextMenu(Offset position, BranchEntry branch) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(value: 'checkout', child: Text('Checkout')),
        const PopupMenuItem(value: 'update', child: Text('Update')),
        if (!branch.isRemote)
          const PopupMenuItem(value: 'push', child: Text('Push')),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'checkout':
        await _checkout(branch);
        break;
      case 'update':
        await _update(branch);
        break;
      case 'push':
        await _push(branch);
        break;
      case 'delete':
        await _delete(branch);
        break;
    }
  }

  Future<void> _showOverflowMenu(Offset position) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final interval = widget.watchIntervalMinutes;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        CheckedPopupMenuItem(
          value: 'sort_name',
          checked: _sort == BranchSort.name,
          child: Text(translate('branch_sort_name')),
        ),
        CheckedPopupMenuItem(
          value: 'sort_last_commit',
          checked: _sort == BranchSort.lastCommit,
          child: Text(translate('branch_sort_last_commit')),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'watch',
          child: Text(
            interval == null
                ? 'Auto-refresh: off'
                : 'Auto-refresh: every ${branchWatchIntervalLabel(interval)}',
          ),
        ),
        const PopupMenuItem(value: 'config', child: Text('Git config…')),
        const PopupMenuItem(
          value: 'explorer',
          child: Text('Open in file explorer'),
        ),
        if (widget.onOpenInTerminal != null)
          const PopupMenuItem(
            value: 'terminal',
            child: Text('Open in terminal'),
          ),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'sort_name':
        await _setSort(BranchSort.name);
        break;
      case 'sort_last_commit':
        await _setSort(BranchSort.lastCommit);
        break;
      case 'watch':
        await _selectWatchInterval(position);
        break;
      case 'config':
        await showRemotesDialog(context, widget.repoPath);
        break;
      case 'explorer':
        await _openInFileExplorer();
        break;
      case 'terminal':
        widget.onOpenInTerminal?.call();
        break;
    }
  }

  Widget _buildBranchRow(BranchEntry branch, {String? label}) {
    return _BranchTile(
      branch: branch,
      label: label ?? branch.name,
      onDoubleTap: () => _checkout(branch),
      onSecondaryTapDown: (position) => _showContextMenu(position, branch),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final query = _searchQuery.trim().toLowerCase();
    final local = sortBranches(
      widget.branches
          .where((e) => !e.isRemote)
          .where((e) => query.isEmpty || e.name.toLowerCase().contains(query))
          .toList(),
      _sort,
    );
    final remote = sortBranches(
      widget.branches
          .where((e) => e.isRemote)
          .where((e) => query.isEmpty || e.name.toLowerCase().contains(query))
          .toList(),
      _sort,
    );

    // Remote branches that a local branch already stands for are shown on
    // that local row (cloud + ahead/behind), so only the rest are listed,
    // grouped by remote ("origin/main" -> "origin").
    final represented = {
      for (final branch in widget.branches)
        if (!branch.isRemote && branch.remoteCounterpart != null)
          branch.remoteCounterpart!,
    };
    final remotesByName = <String, List<BranchEntry>>{};
    for (final branch in remote) {
      if (represented.contains(branch.name) || branch.name.endsWith('/HEAD')) {
        continue;
      }
      final slash = branch.name.indexOf('/');
      final remoteName = slash == -1 ? '' : branch.name.substring(0, slash);
      remotesByName.putIfAbsent(remoteName, () => []).add(branch);
    }

    final watching = widget.watchIntervalMinutes != null;

    return Container(
      width: widget.width,
      decoration: BoxDecoration(border: Border(right: b.hairline)),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
        children: [
          _SectionHeader(
            title: translate('branches_local'),
            icon: Icons.laptop_outlined,
            expanded: _localExpanded,
            onToggle: () => setState(() => _localExpanded = !_localExpanded),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SidebarAction(
                  tooltip: _isSearching ? 'Close search' : 'Search branches',
                  icon: _isSearching ? Icons.close : Icons.search,
                  active: _isSearching,
                  onPressed: _toggleSearch,
                ),
                _SidebarAction(
                  tooltip: widget.isUpdatingCurrentBranch
                      ? 'Pulling…'
                      : 'Update current branch',
                  icon: Icons.refresh,
                  busy: widget.isUpdatingCurrentBranch,
                  onPressed: widget.isUpdatingCurrentBranch
                      ? null
                      : widget.onUpdateCurrentBranch,
                ),
                Builder(
                  builder: (context) => _SidebarAction(
                    tooltip: watching
                        ? 'More · auto-refresh every '
                            '${branchWatchIntervalLabel(widget.watchIntervalMinutes!)}'
                        : 'More',
                    icon: Icons.more_horiz,
                    badge: watching,
                    onPressed: () {
                      final box = context.findRenderObject() as RenderBox;
                      _showOverflowMenu(
                        box.localToGlobal(box.size.bottomLeft(Offset.zero)),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_isSearching)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: b.hover,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 13, color: b.muted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        style: TextStyle(fontSize: 13, color: b.fg),
                        cursorHeight: 14,
                        decoration: InputDecoration(
                          isDense: true,
                          filled: false,
                          hintText: 'Search branches',
                          hintStyle: TextStyle(fontSize: 13, color: b.muted),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (value) =>
                            setState(() => _searchQuery = value),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_localExpanded)
            for (final branch in local) _buildBranchRow(branch),
          if (remotesByName.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
              child: Divider(height: 1, thickness: 1, color: b.line),
            ),
            for (final entry in remotesByName.entries) ...[
              _SectionHeader(
                title: translate('branches_only_on_remote')
                    .replaceAll('{remote}', entry.key),
                icon: Icons.cloud_outlined,
                count: entry.value.length,
                expanded: _remoteExpanded,
                onToggle: () =>
                    setState(() => _remoteExpanded = !_remoteExpanded),
              ),
              if (_remoteExpanded)
                _RemoteOnlyBox(
                  children: [
                    for (final branch in entry.value)
                      _buildBranchRow(
                        branch,
                        label: _shortRemoteName(branch.name),
                      ),
                  ],
                ),
              if (entry.key != remotesByName.keys.last)
                const SizedBox(height: 16),
            ],
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatefulWidget {
  const _SectionHeader({
    required this.title,
    required this.expanded,
    required this.onToggle,
    this.trailing,
    this.icon,
    this.count,
  });

  final String title;
  final IconData? icon;
  final int? count;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget? trailing;

  @override
  State<_SectionHeader> createState() => _SectionHeaderState();
}

class _SectionHeaderState extends State<_SectionHeader> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 6),
      child: SizedBox(
        height: 22,
        child: Row(
          children: [
            Expanded(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() => _hovered = false),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onToggle,
                  child: Row(
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon, size: 13, color: b.muted),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: b.muted,
                            letterSpacing: 0.44,
                          ),
                        ),
                      ),
                      if (_hovered || !widget.expanded) ...[
                        const SizedBox(width: 2),
                        Icon(
                          widget.expanded
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_right,
                          size: 13,
                          color: b.muted,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (widget.count != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  '${widget.count}',
                  style: TextStyle(fontSize: 11, color: b.muted),
                ),
              ),
            if (widget.trailing != null) widget.trailing!,
          ],
        ),
      ),
    );
  }
}

/// A small, muted icon button for the sidebar's section toolbar.
class _SidebarAction extends StatelessWidget {
  const _SidebarAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
    this.busy = false,
    this.badge = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool active;
  final bool busy;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        hoverColor: b.hover,
        splashFactory: NoSplash.splashFactory,
        child: SizedBox(
          width: 22,
          height: 22,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (busy)
                SizedBox(
                  width: 11,
                  height: 11,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: b.muted,
                  ),
                )
              else
                Icon(icon, size: 14, color: active ? b.fg : b.muted),
              if (badge)
                Positioned(
                  top: 3,
                  right: 3,
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: b.accent,
                      shape: BoxShape.circle,
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

class _BranchTile extends StatelessWidget {
  const _BranchTile({
    required this.branch,
    required this.label,
    required this.onDoubleTap,
    required this.onSecondaryTapDown,
  });

  final BranchEntry branch;
  final String label;
  final VoidCallback onDoubleTap;
  final ValueChanged<Offset> onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final current = branch.isHead;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Tooltip(
        message: branch.name,
        waitDuration: const Duration(milliseconds: 800),
        child: GestureDetector(
          onSecondaryTapDown: (details) =>
              onSecondaryTapDown(details.globalPosition),
          child: Material(
            color: current ? b.hover : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              onDoubleTap: onDoubleTap,
              borderRadius: BorderRadius.circular(6),
              hoverColor: b.hover,
              splashFactory: NoSplash.splashFactory,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                child: Row(
                  children: [
                    if (!branch.isRemote) ...[
                      Icon(
                        Icons.call_split,
                        size: 13,
                        color: current ? b.accent : b.muted,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          // Remote rows always say where they live.
                          if (branch.isRemote && label != branch.name)
                            TextSpan(
                              text: branch.name
                                  .substring(0, branch.name.length - label.length),
                              style: TextStyle(color: b.off),
                            ),
                          TextSpan(text: label),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: branch.isMerged
                              ? b.mod
                              : (current ? b.fg : b.muted),
                          fontWeight:
                              current ? FontWeight.w500 : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (branch.isMerged) ...[
                      const SizedBox(width: 6),
                      _MergedBadge(branch: branch),
                    ],
                    if (!branch.isRemote) _SyncState(branch: branch),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The "!" next to a branch already merged into the default branch. Clicking
/// it explains why the branch is shown in a different color.
class _MergedBadge extends StatelessWidget {
  const _MergedBadge({required this.branch});

  final BranchEntry branch;

  void _explain(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(translate('branch_merged_title')),
        content: Text(
          translate('branch_merged_info')
              .replaceAll('{branch}', branch.name)
              .replaceAll('{base}', branch.mergedInto ?? ''),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(translate('close')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return Tooltip(
      message: translate('branch_merged_title'),
      child: InkWell(
        onTap: () => _explain(context),
        customBorder: const CircleBorder(),
        child: Container(
          width: 16,
          height: 16,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: b.mod),
          ),
          child: Text(
            '!',
            style: TextStyle(
              fontSize: 11,
              height: 1,
              fontWeight: FontWeight.w700,
              color: b.mod,
            ),
          ),
        ),
      ),
    );
  }
}


/// Trailing part of a local branch row: commits to push (↑) / pull (↓),
/// and a cloud when the branch also exists on a remote.
class _SyncState extends StatelessWidget {
  const _SyncState({required this.branch});

  final BranchEntry branch;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final counterpart = branch.remoteCounterpart;
    if (counterpart == null) {
      return Tooltip(
        message: translate('branch_local_only'),
        child: Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Icon(Icons.cloud_off_outlined, size: 13, color: b.off),
        ),
      );
    }
    final mono = b.mono(fontSize: 11, color: b.muted);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (branch.ahead > 0)
          Tooltip(
            message: translate('branch_ahead')
                .replaceAll('{n}', '${branch.ahead}')
                .replaceAll('{remote}', counterpart),
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text('↑${branch.ahead}', style: mono.copyWith(color: b.add)),
            ),
          ),
        if (branch.behind > 0)
          Tooltip(
            message: translate('branch_behind')
                .replaceAll('{n}', '${branch.behind}')
                .replaceAll('{remote}', counterpart),
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child:
                  Text('↓${branch.behind}', style: mono.copyWith(color: b.accent)),
            ),
          ),
        Tooltip(
          message: translate('branch_on_remote').replaceAll('{remote}', counterpart),
          child: Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Icon(Icons.cloud_outlined, size: 13, color: b.muted),
          ),
        ),
      ],
    );
  }
}

/// Dashed box around branches that exist only on a remote, so they can't
/// be mistaken for local ones.
class _RemoteOnlyBox extends StatelessWidget {
  const _RemoteOnlyBox({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return CustomPaint(
      painter: _DashedBorderPainter(color: b.off),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 6, 2, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...children,
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
              child: Text(
                translate('branches_remote_hint'),
                style: TextStyle(fontSize: 11, color: b.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(8),
        ).deflate(0.5),
      );
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 7) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color;
}
