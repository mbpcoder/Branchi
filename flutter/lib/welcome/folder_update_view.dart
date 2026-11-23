import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_locale.dart';
import '../repo/folder_update_controller.dart';
import '../theme/app_theme.dart';

/// Content of a folder tab: the repositories one level inside the folder,
/// "Update all" (fast-forward of each current branch) and an Open button
/// per repository. The table can be filtered by repository name and status;
/// filters only affect what is shown, never which repositories are updated.
class FolderUpdateView extends StatefulWidget {
  const FolderUpdateView({
    super.key,
    required this.controller,
    required this.onOpenRepository,
    required this.onChangeFolder,
    required this.isRepositoryOpen,
  });

  final FolderUpdateController controller;

  /// Opens the repository at the given path in a new tab.
  final ValueChanged<String> onOpenRepository;

  /// Points this tab at another folder.
  final ValueChanged<String> onChangeFolder;

  /// Whether the repository at the given path is already open in a tab;
  /// its row's Open button then reads "Go to tab".
  final bool Function(String path) isRepositoryOpen;

  @override
  State<FolderUpdateView> createState() => _FolderUpdateViewState();
}

class _FolderUpdateViewState extends State<FolderUpdateView> {
  final _searchController = TextEditingController();
  String _query = '';

  /// Selected status chips; empty means "any status".
  final Set<FolderRepoStatus> _statuses = {};

  FolderUpdateController get controller => widget.controller;

  @override
  void didUpdateWidget(FolderUpdateView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Filters belong to the folder they were set on.
    if (oldWidget.controller != widget.controller) {
      _searchController.clear();
      _query = '';
      _statuses.clear();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path != null) widget.onChangeFolder(path);
  }

  bool get _hasFilters => _query.isNotEmpty || _statuses.isNotEmpty;

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _statuses.clear();
    });
  }

  List<FolderRepo> _filtered(List<FolderRepo> repos) {
    final query = _query.toLowerCase();
    return repos
        .where(
          (r) =>
              (query.isEmpty || r.name.toLowerCase().contains(query)) &&
              (_statuses.isEmpty || _statuses.contains(r.status)),
        )
        .toList();
  }

  String _subtitle() {
    final parts = [
      controller.folderPath,
      translate(
        'folder_update_repo_count',
      ).replaceAll('{n}', '${controller.repos.length}'),
    ];
    final last = controller.lastRunAt;
    if (last != null) {
      final time = TimeOfDay.fromDateTime(last);
      final hh = time.hour.toString().padLeft(2, '0');
      final mm = time.minute.toString().padLeft(2, '0');
      parts.add(
        translate('folder_update_last_run').replaceAll('{time}', '$hh:$mm'),
      );
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final b = context.branchi;
        final c = controller;
        final showProgress = c.isRunning || c.lastRunAt != null;
        final visible = _filtered(c.repos);
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.folder_outlined,
                      size: 22,
                      color: b.muted,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.basename(c.folderPath),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: b.fg,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _subtitle(),
                          style: b.mono(fontSize: 12, color: b.muted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: c.isRunning ? null : _pickFolder,
                    child: Text(translate('folder_update_change_folder')),
                  ),
                  const SizedBox(width: 8),
                  if (c.isRunning)
                    FilledButton.icon(
                      onPressed: c.stop,
                      icon: const Icon(Icons.stop, size: 16),
                      label: Text(translate('folder_update_stop')),
                    )
                  else
                    FilledButton.icon(
                      onPressed: c.isScanning || c.repos.isEmpty
                          ? null
                          : c.updateAll,
                      icon: const Icon(Icons.sync, size: 16),
                      label: Text(translate('folder_update_update_all')),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              if (showProgress) ...[
                Row(
                  children: [
                    Text(
                      translate('folder_update_progress')
                          .replaceAll('{done}', '${c.doneCount}')
                          .replaceAll('{total}', '${c.repos.length}'),
                      style: TextStyle(
                        fontSize: 12,
                        color: b.fg,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _summary(c),
                        textAlign: TextAlign.end,
                        style: TextStyle(fontSize: 12, color: b.muted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: c.repos.isEmpty ? 0 : c.doneCount / c.repos.length,
                    minHeight: 3,
                    backgroundColor: b.line,
                    color: b.accent,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (c.isScanning && c.repos.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (c.scanError != null)
                Text(c.scanError!, style: TextStyle(color: b.del))
              else if (c.repos.isEmpty)
                Text(
                  translate('folder_update_no_repos'),
                  style: TextStyle(color: b.muted),
                )
              else ...[
                _FilterBar(
                  controller: c,
                  searchController: _searchController,
                  selected: _statuses,
                  showClear: _hasFilters,
                  onQueryChanged: (value) =>
                      setState(() => _query = value.trim()),
                  onToggleStatus: (status) => setState(() {
                    if (!_statuses.remove(status)) _statuses.add(status);
                  }),
                  onClear: _clearFilters,
                ),
                const SizedBox(height: 12),
                if (visible.isEmpty)
                  Text(
                    translate('folder_update_no_matches'),
                    style: TextStyle(color: b.muted),
                  )
                else
                  _RepoTable(
                    repos: visible,
                    onOpenRepository: widget.onOpenRepository,
                    isRepositoryOpen: widget.isRepositoryOpen,
                  ),
              ],
              const SizedBox(height: 12),
              Text(
                translate('folder_update_rules'),
                style: TextStyle(fontSize: 12, color: b.muted),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _summary(FolderUpdateController c) {
    final items = <String>[];
    void add(FolderRepoStatus status, String key) {
      final n = c.countOf(status);
      if (n > 0) items.add(translate(key).replaceAll('{n}', '$n'));
    }

    add(FolderRepoStatus.updated, 'folder_update_sum_updated');
    add(FolderRepoStatus.upToDate, 'folder_update_sum_up_to_date');
    add(FolderRepoStatus.skipped, 'folder_update_sum_skipped');
    add(FolderRepoStatus.failed, 'folder_update_sum_failed');
    return items.join(' · ');
  }
}

/// Translation key of each status's label; idle has none.
const _statusLabelKeys = {
  FolderRepoStatus.waiting: 'folder_update_waiting',
  FolderRepoStatus.updating: 'folder_update_updating',
  FolderRepoStatus.updated: 'folder_update_updated',
  FolderRepoStatus.upToDate: 'folder_update_up_to_date',
  FolderRepoStatus.skipped: 'folder_update_skipped',
  FolderRepoStatus.failed: 'folder_update_failed',
};

/// Name search field plus one chip per status present in the list (with its
/// count). A selected chip stays visible even if its count drops to zero, so
/// it can still be deselected.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.controller,
    required this.searchController,
    required this.selected,
    required this.showClear,
    required this.onQueryChanged,
    required this.onToggleStatus,
    required this.onClear,
  });

  final FolderUpdateController controller;
  final TextEditingController searchController;
  final Set<FolderRepoStatus> selected;
  final bool showClear;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<FolderRepoStatus> onToggleStatus;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final statuses = [
      for (final status in _statusLabelKeys.keys)
        if (controller.countOf(status) > 0 || selected.contains(status)) status,
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 260,
          height: 34,
          child: TextField(
            controller: searchController,
            onChanged: onQueryChanged,
            style: TextStyle(fontSize: 13, color: b.fg),
            decoration: InputDecoration(
              isDense: true,
              hintText: translate('folder_update_search_hint'),
              prefixIcon: const Icon(Icons.search, size: 16),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
        for (final status in statuses)
          FilterChip(
            label: Text(
              '${translate(_statusLabelKeys[status]!)} '
              '${controller.countOf(status)}',
              style: const TextStyle(fontSize: 12),
            ),
            selected: selected.contains(status),
            onSelected: (_) => onToggleStatus(status),
            visualDensity: VisualDensity.compact,
          ),
        if (showClear)
          TextButton(
            onPressed: onClear,
            child: Text(translate('folder_update_clear_filters')),
          ),
      ],
    );
  }
}

class _RepoTable extends StatelessWidget {
  const _RepoTable({
    required this.repos,
    required this.onOpenRepository,
    required this.isRepositoryOpen,
  });

  final List<FolderRepo> repos;
  final ValueChanged<String> onOpenRepository;
  final bool Function(String path) isRepositoryOpen;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final headerStyle = TextStyle(
      fontSize: 11,
      color: b.muted,
      letterSpacing: 0.44,
    );
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: b.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    translate('folder_update_col_repository'),
                    style: headerStyle,
                  ),
                ),
                SizedBox(
                  width: 130,
                  child: Text(
                    translate('folder_update_col_status'),
                    style: headerStyle,
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Text(
                    translate('folder_update_col_details'),
                    style: headerStyle,
                  ),
                ),
                const SizedBox(width: 8 + _actionWidth),
              ],
            ),
          ),
          for (final repo in repos)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(border: Border(top: b.hairline)),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          repo.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: b.fg,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          repo.isDetached ? 'HEAD' : (repo.branch ?? ' '),
                          style: b.mono(fontSize: 12, color: b.muted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 130, child: _StatusLabel(repo: repo)),
                  Expanded(
                    flex: 4,
                    child: Tooltip(
                      message: repo.detail ?? '',
                      child: Text(
                        _detailText(repo),
                        style: TextStyle(fontSize: 12, color: b.muted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Fixed width, so "Open" and the wider "Go to tab" keep
                  // the columns lined up.
                  SizedBox(
                    width: _actionWidth,
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      // Already open in a tab: the button switches to it.
                      child: isRepositoryOpen(repo.path)
                          ? FilledButton.tonalIcon(
                              onPressed: () => onOpenRepository(repo.path),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 30),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                              ),
                              icon: const Icon(Icons.tab, size: 14),
                              label: Text(translate('folder_update_go_to_tab')),
                            )
                          : OutlinedButton.icon(
                              onPressed: () => onOpenRepository(repo.path),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 30),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                              ),
                              icon: const Icon(Icons.open_in_new, size: 14),
                              label: Text(translate('folder_update_open')),
                            ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _detailText(FolderRepo repo) {
    if (repo.status == FolderRepoStatus.updating) {
      return translate('folder_update_updating_detail');
    }
    final key = repo.detailKey;
    if (key != null) {
      return translate(key).replaceAll('{n}', repo.detail ?? '');
    }
    return repo.detail ?? '';
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.repo});

  final FolderRepo repo;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    late final Color color;
    late final String key;
    IconData? icon;
    switch (repo.status) {
      case FolderRepoStatus.idle:
        return const SizedBox.shrink();
      case FolderRepoStatus.waiting:
        color = b.muted;
        key = 'folder_update_waiting';
        icon = Icons.schedule;
      case FolderRepoStatus.updating:
        color = b.accent;
        key = 'folder_update_updating';
      case FolderRepoStatus.updated:
        color = b.add;
        key = 'folder_update_updated';
        icon = Icons.check_circle_outline;
      case FolderRepoStatus.upToDate:
        color = b.muted;
        key = 'folder_update_up_to_date';
        icon = Icons.check;
      case FolderRepoStatus.skipped:
        color = b.mod;
        key = 'folder_update_skipped';
        icon = Icons.remove_circle_outline;
      case FolderRepoStatus.failed:
        color = b.del;
        key = 'folder_update_failed';
        icon = Icons.error_outline;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon == null)
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
          )
        else
          Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            translate(key),
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Width of the Open / Go to tab button column in the repository table.
const double _actionWidth = 120;
