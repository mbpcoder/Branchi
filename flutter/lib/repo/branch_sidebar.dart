import 'package:flutter/material.dart';

import 'git_actions.dart';
import 'models.dart';
import 'remotes_dialog.dart';

/// Auto-refresh interval choices offered by the watch dropdown, in minutes.
const List<int> kBranchWatchIntervalsMinutes = [5, 10, 15, 30, 45, 60];

String branchWatchIntervalLabel(int minutes) {
  if (minutes == 60) return '1 hour';
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
    this.width = 220,
  });

  final String repoPath;
  final List<BranchEntry> branches;

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

class _BranchSidebarState extends State<BranchSidebar> {
  bool _localExpanded = true;
  bool _remoteExpanded = true;

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
                  tooltip: widget.isUpdatingCurrentBranch
                      ? 'Pulling…'
                      : 'Update current branch',
                  icon: widget.isUpdatingCurrentBranch
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
                  onPressed: widget.isUpdatingCurrentBranch
                      ? null
                      : widget.onUpdateCurrentBranch,
                ),
                const SizedBox(width: 4),
                Builder(
                  builder: (context) => IconButton(
                    iconSize: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: widget.watchIntervalMinutes == null
                        ? 'Auto-refresh current branch: off'
                        : 'Auto-refresh current branch every '
                            '${branchWatchIntervalLabel(widget.watchIntervalMinutes!)}',
                    icon: Icon(
                      widget.watchIntervalMinutes == null
                          ? Icons.watch_later_outlined
                          : Icons.watch_later,
                      color: widget.watchIntervalMinutes == null
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
