import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_locale.dart';
import '../theme/app_theme.dart';
import 'branch_base_prefs.dart';
import 'file_explorer.dart';
import 'git_actions.dart';
import 'merge.dart';
import 'models.dart';
import 'remotes_dialog.dart';

/// Auto-refresh interval choices offered by the watch dropdown, in minutes.
const List<int> kBranchWatchIntervalsMinutes = [1, 2, 3, 4, 5, 10, 15, 30, 45, 60];

String branchWatchIntervalLabel(int minutes) {
  if (minutes == 60) return translate('bs_1_hour');
  if (minutes == 1) return translate('bs_1_minute');
  return translate('bs_minutes').replaceAll('{n}', '$minutes');
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
            Text(translate('bs_off')),
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
    this.onMergeConflicts,
    this.width = 220,
  });

  final String repoPath;
  final List<BranchEntry> branches;

  /// Opens a new built-in terminal tab in the repository folder. The menu
  /// item is hidden when this is null.
  final VoidCallback? onOpenInTerminal;

  /// Called when a merge started here stopped on conflicts, so the caller
  /// can show them (in Changes).
  final VoidCallback? onMergeConflicts;

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

  /// The chosen base branch for this repo, or null for the default.
  String? _compareBase;

  bool _localExpanded = true;
  bool _remoteExpanded = true;

  /// Folder and remote nodes the user collapsed, keyed by
  /// "local:feature", "remote:origin" or "remote:origin/feature".
  final Set<String> _collapsed = {};
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
      final base = await BranchBasePrefs.load(repo);
      if (!mounted || repo != widget.repoPath) return;
      setState(() {
        _compareBase = base;
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

  Future<String?> _promptCreateLocalBranch(
    String suggestedName, {
    String? title,
  }) {
    final controller = TextEditingController(text: suggestedName);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title ?? translate('bs_no_local_title')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration:
              InputDecoration(labelText: translate('bs_new_branch_name')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(translate('cancel')),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) Navigator.pop(dialogContext, name);
            },
            child: Text(translate('bs_create')),
          ),
        ],
      ),
    );
  }

  /// A confirm dialog with a red [action] button; true when confirmed.
  Future<bool> _confirmDanger({
    required String title,
    required String body,
    required String action,
  }) async {
    final b = context.branchi;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(body),
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(translate('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: b.del,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return confirmed == true && mounted;
  }

  /// Deletes [branch] after confirming. A remote branch is deleted on the
  /// server. A local branch with commits its base lacks needs a second,
  /// explicit confirmation, since deleting it loses them.
  Future<void> _delete(BranchEntry branch) async {
    final confirmed = await _confirmDanger(
      title: branch.isRemote
          ? translate('branch_delete_remote_title')
              .replaceAll('{remote}', branch.name.split('/').first)
          : translate('bs_delete_title'),
      body: branch.isRemote
          ? translate('branch_delete_remote_body')
              .replaceAll('{branch}', branch.name)
          : translate('bs_delete_body').replaceAll('{branch}', branch.name),
      action: translate('bs_delete'),
    );
    if (!confirmed) return;

    if (!branch.isRemote) {
      final unmerged = await GitActions.unmergedCommits(
        widget.repoPath,
        branch.name,
        base: _currentBase,
      );
      if (!mounted) return;
      if (unmerged == null || unmerged.commits > 0) {
        final String body;
        if (unmerged == null) {
          body = translate('bs_unmerged_unknown')
              .replaceAll('{branch}', branch.name);
        } else {
          final base = _baseLabel(unmerged.base);
          body = translate(base == null
                  ? 'bs_unmerged_body_no_base'
                  : 'bs_unmerged_body')
              .replaceAll('{branch}', branch.name)
              .replaceAll('{n}', '${unmerged.commits}')
              .replaceAll('{base}', base ?? '');
        }
        final again = await _confirmDanger(
          title: translate('bs_unmerged_title'),
          body: body,
          action: translate('bs_delete_anyway'),
        );
        if (!again) return;
      }
    }

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

  /// Asks for a name, creates a branch at [branch]'s tip and switches to
  /// it.
  Future<void> _newBranchFrom(BranchEntry branch) async {
    final name = await _promptCreateLocalBranch(
      '',
      title: translate('bs_new_branch_from_title')
          .replaceAll('{branch}', branch.name),
    );
    if (name == null || !mounted) return;
    final created =
        await GitActions.createBranch(widget.repoPath, name, from: branch.name);
    if (!mounted) return;
    if (!created.isSuccess) {
      widget.onChanged();
      _showError(created.error!);
      return;
    }
    final switched = await GitActions.checkoutBranch(widget.repoPath, name);
    if (!mounted) return;
    widget.onChanged();
    if (!switched.isSuccess) _showError(switched.error!);
  }

  /// Switches to [branch], then merges [base] into it (after asking how).
  Future<void> _mergeBaseInto(BranchEntry branch, String base) async {
    final switched =
        await GitActions.checkoutBranch(widget.repoPath, branch.name);
    if (!mounted) return;
    widget.onChanged();
    if (!switched.isSuccess) {
      _showError(switched.error!);
      return;
    }
    await _merge(base);
  }

  /// Merges [source] into the current branch after asking how.
  Future<void> _merge(
    String source, {
    MergeMode mode = MergeMode.merge,
  }) async {
    final outcome = await showMergeDialog(
      context,
      repo: widget.repoPath,
      source: source,
      mode: mode,
    );
    if (!mounted || outcome == null) return;
    widget.onChanged();
    if (outcome.result == 'conflicts') {
      widget.onMergeConflicts?.call();
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(translate(outcome.result == 'up_to_date'
                  ? 'merge_done_up_to_date'
                  : 'merge_done')
              .replaceAll('{source}', source)),
        ));
    }
  }

  Future<void> _showContextMenu(Offset position, BranchEntry branch) async {
    final current = [
      for (final b in widget.branches)
        if (b.isHead) b.name,
    ].firstOrNull;
    final canMergeIn = current != null && !branch.isHead;
    final base = branch.isHead && branch.baseBehind > 0 ? branch.base : null;
    // "Merge master into feature/x": for a local branch other than the
    // current one and the base itself. (The current branch has "Update
    // from master" above when it's behind.)
    final compareBase = _currentBase;
    final mergeBaseInto = !branch.isRemote &&
            !branch.isHead &&
            compareBase != null &&
            branch.name != compareBase &&
            branch.name != _baseLabel(compareBase)
        ? compareBase
        : null;
    final hasMergeItems =
        canMergeIn || base != null || mergeBaseInto != null;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<String>(
      context: context,
      // Wider than the default 280px, so branch names fit on a line or two.
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 360),
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(value: 'checkout', child: Text(translate('bs_checkout'))),
        PopupMenuItem(value: 'update', child: Text(translate('bs_update'))),
        if (hasMergeItems) const PopupMenuDivider(),
        if (canMergeIn)
          PopupMenuItem(
            value: 'merge',
            child: _MenuLabel(
              translate('bs_merge_into_current'),
              detail: '${branch.name} → $current',
            ),
          ),
        if (canMergeIn)
          PopupMenuItem(
            value: 'rebase',
            child: _MenuLabel(
              translate('bs_rebase_current_onto'),
              detail: '$current → ${branch.name}',
            ),
          ),
        if (base != null)
          PopupMenuItem(
            value: 'merge_base',
            child: _MenuLabel(translate('merge_menu_update_from')
                .replaceAll('{source}', _baseLabel(base) ?? base)
                .replaceAll('{count}', '${branch.baseBehind}')),
          ),
        if (mergeBaseInto != null)
          PopupMenuItem(
            value: 'merge_base_into',
            child: _MenuLabel(
              translate('bs_merge_base_into_this')
                  .replaceAll('{base}', _baseLabel(mergeBaseInto)!),
              detail: '${_baseLabel(mergeBaseInto)} → ${branch.name}',
            ),
          ),
        if (hasMergeItems) const PopupMenuDivider(),
        PopupMenuItem(
          value: 'new_branch',
          child: _MenuLabel(
            translate('bs_new_branch_from'),
            detail: branch.name,
          ),
        ),
        const PopupMenuDivider(),
        if (!branch.isRemote)
          PopupMenuItem(value: 'push', child: Text(translate('bs_push'))),
        PopupMenuItem(value: 'delete', child: Text(translate('bs_delete'))),
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
      case 'merge':
        await _merge(branch.name);
        break;
      case 'rebase':
        await _merge(branch.name, mode: MergeMode.rebase);
        break;
      case 'merge_base':
        await _merge(base!);
        break;
      case 'merge_base_into':
        await _mergeBaseInto(branch, mergeBaseInto!);
        break;
      case 'new_branch':
        await _newBranchFrom(branch);
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
        PopupMenuItem(
          value: 'compare_base',
          child: Text(
            translate('branch_compare_with').replaceAll(
              '{base}',
              _baseLabel(_currentBase) ?? _baseLabel(_compareBase) ?? 'main',
            ),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'watch',
          child: Text(
            interval == null
                ? translate('bs_auto_refresh_off')
                : translate('bs_auto_refresh_every').replaceAll(
                    '{interval}',
                    branchWatchIntervalLabel(interval),
                  ),
          ),
        ),
        PopupMenuItem(value: 'config', child: Text(translate('bs_git_config'))),
        PopupMenuItem(
          value: 'explorer',
          child: Text(translate('bs_open_explorer')),
        ),
        if (widget.onOpenInTerminal != null)
          PopupMenuItem(
            value: 'terminal',
            child: Text(translate('bs_open_terminal')),
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
      case 'compare_base':
        await _chooseCompareBase();
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

  /// Remote names ("origin") seen in the branch list.
  Set<String> get _remoteNames => {
        for (final branch in widget.branches)
          if (branch.isRemote && branch.name.contains('/'))
            branch.name.substring(0, branch.name.indexOf('/')),
      };

  /// The branch local branches are compared with, as shown ("main" for
  /// "origin/main"), or null when nothing is compared.
  String? _baseLabel(String? base) =>
      base == null ? null : BranchBasePrefs.displayName(base, _remoteNames);

  /// Lets the user pick which branch local branches are compared with.
  Future<void> _chooseCompareBase() async {
    final current = await BranchBasePrefs.load(widget.repoPath);
    if (!mounted) return;
    final names = [
      ...sortBranches(
        widget.branches.where((e) => !e.isRemote).toList(),
        BranchSort.name,
      ).map((e) => e.name),
      ...sortBranches(
        widget.branches
            .where((e) => e.isRemote && !e.name.endsWith('/HEAD'))
            .toList(),
        BranchSort.name,
      ).map((e) => e.name),
    ];
    const reset = '\u0000default';
    final selected = current ?? reset;
    final b = context.branchi;
    final picked = await showDialog<String>(
      context: context,
      builder: (context) {
        Widget option(String value, Widget title, {String? subtitle}) =>
            ListTile(
              dense: true,
              leading: Icon(
                Icons.check,
                size: 16,
                color: value == selected ? b.accent : Colors.transparent,
              ),
              title: title,
              subtitle: subtitle == null ? null : Text(subtitle),
              onTap: () => Navigator.of(context).pop(value),
            );
        return SimpleDialog(
          title: Text(translate('branch_compare_title')),
          children: [
            SizedBox(
              width: 340,
              height: 360,
              child: ListView(
                children: [
                  option(
                    reset,
                    Text(translate('branch_compare_default')),
                    subtitle: _defaultBaseLabel,
                  ),
                  for (final name in names)
                    option(name, Text(name, style: TextStyle(color: b.fg))),
                ],
              ),
            ),
          ],
        );
      },
    );
    if (picked == null || !mounted) return;
    final value = picked == reset ? null : picked;
    if (value == current) return;
    await BranchBasePrefs.save(widget.repoPath, value);
    setState(() => _compareBase = value);
    widget.onChanged();
  }

  /// What the default base is called, when the loaded branches are
  /// compared with it.
  String? get _defaultBaseLabel {
    if (_compareBase == null) return _baseLabel(_currentBase);
    return null;
  }

  /// The base the loaded branches were compared with.
  String? get _currentBase {
    for (final branch in widget.branches) {
      if (branch.base != null) return branch.base;
    }
    return null;
  }

  /// Folders stay open while searching, so every match is visible.
  bool _isExpanded(String key) =>
      _searchQuery.trim().isNotEmpty || !_collapsed.contains(key);

  void _toggleFolder(String key) => setState(() {
        if (!_collapsed.remove(key)) _collapsed.add(key);
      });

  /// Rows for [folder]: its sub-folders first, then its branches, each
  /// indented by [depth]. [key] prefixes the folder keys in [_collapsed].
  List<Widget> _treeRows(
    _BranchFolder folder, {
    required String key,
    required int depth,
  }) {
    final names = folder.folders.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [
      for (final name in names) ...[
        _FolderRow(
          name: name,
          icon: Icons.folder_outlined,
          depth: depth,
          count: folder.folders[name]!.branchCount,
          expanded: _isExpanded('$key$name'),
          onToggle: () => _toggleFolder('$key$name'),
        ),
        if (_isExpanded('$key$name'))
          ..._treeRows(
            folder.folders[name]!,
            key: '$key$name/',
            depth: depth + 1,
          ),
      ],
      for (final branch in folder.branches)
        Padding(
          padding: EdgeInsetsDirectional.only(start: depth * _treeIndent),
          child: _buildBranchRow(branch, label: branch.name.split('/').last),
        ),
    ];
  }

  Widget _buildBranchRow(BranchEntry branch, {String? label}) {
    return _BranchTile(
      branch: branch,
      label: label ?? branch.name,
      baseLabel: _baseLabel(branch.base),
      isBase: !branch.isRemote &&
          _currentBase != null &&
          (branch.name == _currentBase ||
              branch.name == _baseLabel(_currentBase)),
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

    // Every remote branch, grouped by remote ("origin/main" -> "origin").
    final remotesByName = <String, List<BranchEntry>>{};
    for (final branch in remote) {
      if (branch.name.endsWith('/HEAD')) continue;
      final slash = branch.name.indexOf('/');
      final remoteName = slash == -1 ? '' : branch.name.substring(0, slash);
      remotesByName.putIfAbsent(remoteName, () => []).add(branch);
    }
    final remoteCount =
        remotesByName.values.fold<int>(0, (sum, list) => sum + list.length);

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
                  tooltip: translate(
                    _isSearching ? 'bs_close_search' : 'bs_search',
                  ),
                  icon: _isSearching ? Icons.close : Icons.search,
                  active: _isSearching,
                  onPressed: _toggleSearch,
                ),
                _SidebarAction(
                  tooltip: widget.isUpdatingCurrentBranch
                      ? translate('bs_pulling')
                      : translate('bs_update_current'),
                  icon: Icons.refresh,
                  busy: widget.isUpdatingCurrentBranch,
                  onPressed: widget.isUpdatingCurrentBranch
                      ? null
                      : widget.onUpdateCurrentBranch,
                ),
                Builder(
                  builder: (context) => _SidebarAction(
                    tooltip: watching
                        ? translate('bs_more_watching').replaceAll(
                            '{interval}',
                            branchWatchIntervalLabel(
                              widget.watchIntervalMinutes!,
                            ),
                          )
                        : translate('bs_more'),
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
                          hintText: translate('bs_search'),
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
            ..._treeRows(
              _BranchFolder.of(local, (branch) => branch.name),
              key: 'local:',
              depth: 0,
            ),
          if (remotesByName.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
              child: Divider(height: 1, thickness: 1, color: b.line),
            ),
            _SectionHeader(
              title: translate('branches_remote'),
              icon: Icons.cloud_outlined,
              count: remoteCount,
              expanded: _remoteExpanded,
              onToggle: () =>
                  setState(() => _remoteExpanded = !_remoteExpanded),
            ),
            if (_remoteExpanded)
              for (final entry in remotesByName.entries) ...[
                _FolderRow(
                  name: entry.key,
                  icon: Icons.dns_outlined,
                  depth: 0,
                  count: entry.value.length,
                  expanded: _isExpanded('remote:${entry.key}'),
                  onToggle: () => _toggleFolder('remote:${entry.key}'),
                ),
                if (_isExpanded('remote:${entry.key}'))
                  ..._treeRows(
                    _BranchFolder.of(
                      entry.value,
                      (branch) => _shortRemoteName(branch.name),
                    ),
                    key: 'remote:${entry.key}/',
                    depth: 1,
                  ),
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
      padding: const EdgeInsetsDirectional.only(start: 8, bottom: 6),
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
                padding: const EdgeInsetsDirectional.only(end: 8),
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
    this.baseLabel,
    this.isBase = false,
    required this.onDoubleTap,
    required this.onSecondaryTapDown,
  });

  final BranchEntry branch;
  final String label;

  /// The base branch's name for the "3 ahead · 12 behind main" line; no
  /// line when null.
  final String? baseLabel;

  /// Whether this is the branch the others are compared with.
  final bool isBase;
  final VoidCallback onDoubleTap;
  final ValueChanged<Offset> onSecondaryTapDown;

  /// From this many commits behind, the base line turns amber.
  static const _farBehind = 100;

  Widget _vsBase(BuildContext context, String base) {
    final b = context.branchi;
    String fill(String key) => translate(key)
        .replaceAll('{ahead}', '${branch.baseAhead}')
        .replaceAll('{behind}', '${branch.baseBehind}')
        .replaceAll('{base}', base)
        .replaceAll('{branch}', branch.name);
    return Tooltip(
      message: fill('branch_vs_base_tip'),
      waitDuration: const Duration(milliseconds: 400),
      child: Text(
        fill(branch.baseBehind == 0 ? 'branch_vs_base_even' : 'branch_vs_base'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: b.mono(
          fontSize: 11,
          color: branch.baseBehind >= _farBehind ? b.mod : b.muted,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final current = branch.isHead;
    final base = branch.isRemote ? null : baseLabel;
    final name = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13,
        color: branch.isMerged ? b.mod : (current ? b.fg : b.muted),
        fontWeight: current ? FontWeight.w500 : FontWeight.w400,
      ),
    );
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!branch.isRemote) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.call_split,
                          size: 13,
                          color: current ? b.accent : b.muted,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(child: name),
                              if (isBase) ...[
                                const SizedBox(width: 6),
                                _BaseBadge(),
                              ],
                              if (branch.isMerged) ...[
                                const SizedBox(width: 6),
                                _MergedBadge(branch: branch),
                              ],
                              if (!branch.isRemote)
                                _SyncState(branch: branch),
                            ],
                          ),
                          // Full row width, under the name and the icons.
                          if (base != null) ...[
                            const SizedBox(height: 2),
                            _vsBase(context, base),
                          ],
                        ],
                      ),
                    ),
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

/// A branch menu item: what it does, with the branch names it acts on
/// underneath in small text. Names wrap instead of being cut off.
class _MenuLabel extends StatelessWidget {
  const _MenuLabel(this.title, {this.detail});

  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title),
          if (detail != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              // Branch names read left to right, also in RTL.
              child: Text(
                detail!,
                textDirection: TextDirection.ltr,
                style: TextStyle(fontSize: 11, color: b.muted),
              ),
            ),
        ],
      ),
    );
  }
}

/// The "base" pill on the branch the others are compared with.
class _BaseBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return Tooltip(
      message: translate('branch_base_badge_tip'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: b.line),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          translate('branch_base_badge'),
          style: TextStyle(fontSize: 10, color: b.muted),
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
          padding: const EdgeInsetsDirectional.only(start: 6),
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
              padding: const EdgeInsetsDirectional.only(start: 6),
              child: Text('↑${branch.ahead}', style: mono.copyWith(color: b.add)),
            ),
          ),
        if (branch.behind > 0)
          Tooltip(
            message: translate('branch_behind')
                .replaceAll('{n}', '${branch.behind}')
                .replaceAll('{remote}', counterpart),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 6),
              child:
                  Text('↓${branch.behind}', style: mono.copyWith(color: b.accent)),
            ),
          ),
        Tooltip(
          message: translate('branch_on_remote').replaceAll('{remote}', counterpart),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 6),
            child: Icon(Icons.cloud_outlined, size: 13, color: b.muted),
          ),
        ),
      ],
    );
  }
}

/// How far each tree level is indented.
const double _treeIndent = 14;

/// Branches grouped by their "/"-separated name parts: "feature/login"
/// lands in folder "feature".
class _BranchFolder {
  final Map<String, _BranchFolder> folders = {};
  final List<BranchEntry> branches = [];

  /// Builds the tree from [branches] (kept in their order), placed by the
  /// path [pathOf] gives each one.
  static _BranchFolder of(
    List<BranchEntry> branches,
    String Function(BranchEntry) pathOf,
  ) {
    final root = _BranchFolder();
    for (final branch in branches) {
      final parts = pathOf(branch).split('/');
      var node = root;
      for (final part in parts.take(parts.length - 1)) {
        if (part.isEmpty) continue;
        node = node.folders.putIfAbsent(part, _BranchFolder.new);
      }
      node.branches.add(branch);
    }
    return root;
  }

  int get branchCount => folders.values
      .fold(branches.length, (sum, folder) => sum + folder.branchCount);
}

/// A collapsible folder (or remote) row in the branch tree.
class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.name,
    required this.icon,
    required this.depth,
    required this.count,
    required this.expanded,
    required this.onToggle,
  });

  final String name;
  final IconData icon;
  final int depth;
  final int count;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: depth * _treeIndent,
        bottom: 2,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(6),
          hoverColor: b.hover,
          splashFactory: NoSplash.splashFactory,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(2, 5, 8, 5),
            child: Row(
              children: [
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_down
                      : (Directionality.of(context) == TextDirection.rtl
                          ? Icons.keyboard_arrow_left
                          : Icons.keyboard_arrow_right),
                  size: 14,
                  color: b.muted,
                ),
                const SizedBox(width: 2),
                Icon(icon, size: 13, color: b.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: b.muted),
                  ),
                ),
                Text('$count', style: TextStyle(fontSize: 11, color: b.off)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
