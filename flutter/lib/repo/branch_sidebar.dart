import 'dart:async';

import 'package:flutter/material.dart';

import 'branch_watch_store.dart';
import 'git_actions.dart';
import 'models.dart';
import 'remotes_dialog.dart';

/// Auto-refresh interval choices offered by the watch dropdown, in minutes.
const List<int> kBranchWatchIntervalsMinutes = [5, 10, 15, 30, 45, 60];

String branchWatchIntervalLabel(int minutes) {
  if (minutes == 60) return '1 hour';
  return '$minutes minutes';
}

/// Left-hand sidebar listing local and remote branches for the open repo,
/// with collapsible sections and per-branch checkout/delete/update actions.
class BranchSidebar extends StatefulWidget {
  const BranchSidebar({
    super.key,
    required this.repoPath,
    required this.branches,
    required this.onChanged,
    this.width = 220,
  });

  final String repoPath;
  final List<BranchEntry> branches;

  /// Called after a branch action (checkout/create/delete/update) succeeds,
  /// so the caller can reload the repository's commits and branches.
  final VoidCallback onChanged;

  final double width;

  @override
  State<BranchSidebar> createState() => _BranchSidebarState();
}

class _BranchSidebarState extends State<BranchSidebar> {
  bool _localExpanded = true;
  bool _remoteExpanded = true;

  int? _watchIntervalMinutes;
  Timer? _watchTimer;
  bool _isUpdatingCurrentBranch = false;

  @override
  void initState() {
    super.initState();
    _loadWatchInterval();
  }

  @override
  void dispose() {
    _watchTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(BranchSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repoPath != widget.repoPath) {
      _loadWatchInterval();
    }
  }

  Future<void> _loadWatchInterval() async {
    final repoPath = widget.repoPath;
    final minutes = await BranchWatchStore.loadIntervalMinutes(repoPath);
    if (!mounted || repoPath != widget.repoPath) return;
    setState(() => _watchIntervalMinutes = minutes);
    _restartWatchTimer();
  }

  void _restartWatchTimer() {
    _watchTimer?.cancel();
    final minutes = _watchIntervalMinutes;
    if (minutes == null) return;
    _watchTimer = Timer.periodic(Duration(minutes: minutes), (_) {
      _updateCurrentBranch();
    });
  }

  Future<void> _updateCurrentBranch() async {
    if (_isUpdatingCurrentBranch) return;
    BranchEntry? head;
    for (final branch in widget.branches) {
      if (branch.isHead) {
        head = branch;
        break;
      }
    }
    if (head == null) return;
    setState(() => _isUpdatingCurrentBranch = true);
    try {
      await GitActions.updateBranch(
        widget.repoPath,
        head.name,
        isRemote: head.isRemote,
      );
      if (!mounted) return;
      widget.onChanged();
    } finally {
      if (mounted) setState(() => _isUpdatingCurrentBranch = false);
    }
  }

  // Dismissing the menu without picking anything also resolves to `null`
  // from showMenu, so "off" is modeled as this sentinel instead of `null`
  // to tell an explicit choice apart from a dismissal.
  static const int _offValue = -1;

  Future<void> _selectWatchInterval(Offset position) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        for (final minutes in kBranchWatchIntervalsMinutes)
          PopupMenuItem<int>(
            value: minutes,
            child: Text(branchWatchIntervalLabel(minutes)),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<int>(value: _offValue, child: Text('Off')),
      ],
    );
    if (!mounted || selected == null) return;
    final newInterval = selected == _offValue ? null : selected;
    if (newInterval == _watchIntervalMinutes) return;
    setState(() => _watchIntervalMinutes = newInterval);
    _restartWatchTimer();
    await BranchWatchStore.saveIntervalMinutes(widget.repoPath, newInterval);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
        title: const Text('Delete branch'),
        content: Text('Delete branch "${branch.name}"?'),
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

  Future<void> _showContextMenu(Offset position, BranchEntry branch) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(value: 'checkout', child: Text('Checkout')),
        PopupMenuItem(value: 'update', child: Text('Update')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
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
      case 'delete':
        await _delete(branch);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = widget.branches.where((b) => !b.isRemote).toList();
    final remote = widget.branches.where((b) => b.isRemote).toList();

    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionHeader(
            title: 'Branches',
            expanded: _localExpanded,
            onToggle: () => setState(() => _localExpanded = !_localExpanded),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: _isUpdatingCurrentBranch
                      ? 'Pulling…'
                      : 'Update current branch',
                  icon: _isUpdatingCurrentBranch
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        )
                      : Icon(
                          Icons.refresh,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  onPressed: _isUpdatingCurrentBranch ? null : _updateCurrentBranch,
                ),
                const SizedBox(width: 4),
                Builder(
                  builder: (context) => IconButton(
                    iconSize: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: _watchIntervalMinutes == null
                        ? 'Auto-refresh current branch: off'
                        : 'Auto-refresh current branch every '
                            '${branchWatchIntervalLabel(_watchIntervalMinutes!)}',
                    icon: Icon(
                      _watchIntervalMinutes == null
                          ? Icons.watch_later_outlined
                          : Icons.watch_later,
                      color: _watchIntervalMinutes == null
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : Theme.of(context).colorScheme.primary,
                    ),
                    onPressed: () {
                      final box = context.findRenderObject() as RenderBox;
                      final position = box.localToGlobal(
                        box.size.bottomLeft(Offset.zero),
                      );
                      _selectWatchInterval(position);
                    },
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Git config',
                  icon: Icon(
                    Icons.settings_outlined,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () =>
                      showRemotesDialog(context, widget.repoPath),
                ),
              ],
            ),
          ),
          if (_localExpanded)
            for (final branch in local)
              _BranchTile(
                branch: branch,
                onDoubleTap: () => _checkout(branch),
                onSecondaryTapDown: (position) =>
                    _showContextMenu(position, branch),
              ),
          if (remote.isNotEmpty) ...[
            _SectionHeader(
              title: 'Remote',
              expanded: _remoteExpanded,
              onToggle: () =>
                  setState(() => _remoteExpanded = !_remoteExpanded),
            ),
            if (_remoteExpanded)
              for (final branch in remote)
                _BranchTile(
                  branch: branch,
                  onDoubleTap: () => _checkout(branch),
                  onSecondaryTapDown: (position) =>
                      _showContextMenu(position, branch),
                ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.expanded,
    required this.onToggle,
    this.trailing,
  });

  final String title;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onToggle,
              child: Row(
                children: [
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    title.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                  ),
                ],
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _BranchTile extends StatelessWidget {
  const _BranchTile({
    required this.branch,
    required this.onDoubleTap,
    required this.onSecondaryTapDown,
  });

  final BranchEntry branch;
  final VoidCallback onDoubleTap;
  final ValueChanged<Offset> onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: onDoubleTap,
      onSecondaryTapDown: (details) =>
          onSecondaryTapDown(details.globalPosition),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        leading: Icon(
          branch.isRemote ? Icons.cloud_outlined : Icons.call_split,
          size: 16,
          color: branch.isHead
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        title: Text(
          branch.name,
          style: TextStyle(
            fontWeight: branch.isHead ? FontWeight.bold : FontWeight.normal,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
