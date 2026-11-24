import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'models.dart';

/// Middle pane: the commit log for the open repo, newest first.
///
/// Click selects one commit; Ctrl/Cmd+click adds or removes a commit and
/// Shift+click selects the range from the last clicked commit.
class CommitList extends StatefulWidget {
  const CommitList({
    super.key,
    required this.commits,
    required this.selectedIds,
    required this.onSelect,
  });

  final List<CommitEntry> commits;
  final Set<String> selectedIds;

  /// The new selection, in [commits] order (newest first); never empty.
  final ValueChanged<List<CommitEntry>> onSelect;

  @override
  State<CommitList> createState() => _CommitListState();
}

class _CommitListState extends State<CommitList> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scroll = ScrollController();
  String _query = '';

  /// Where a Shift+click range starts: the last commit clicked without
  /// Shift.
  String? _anchorId;

  @override
  void initState() {
    super.initState();
    // E.g. History opened from line blame with a commit already selected.
    if (widget.selectedIds.length == 1) {
      _anchorId = widget.selectedIds.single;
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
    }
  }

  @override
  void didUpdateWidget(covariant CommitList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only a single selection made elsewhere (e.g. from line blame) is
    // scrolled to; a multi-selection is made here, where it's visible.
    if (widget.selectedIds.length == 1 &&
        !setEquals(widget.selectedIds, oldWidget.selectedIds)) {
      _anchorId = widget.selectedIds.single;
      // After layout, so the list knows its size.
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Scrolls the selected commit into the middle of the list if it's off
  /// screen, e.g. when it was selected from line blame in the editor.
  void _revealSelected() {
    if (!mounted || !_scroll.hasClients) return;
    final commits = _filteredCommits;
    if (widget.selectedIds.length != 1) return;
    final selectedId = widget.selectedIds.single;
    final index = commits.indexWhere((c) => c.id == selectedId);
    if (index == -1) return;
    final position = _scroll.position;
    final viewport = position.viewportDimension;
    // Every row has the same height (see prototypeItem below).
    final rowExtent = (position.maxScrollExtent + viewport) / commits.length;
    if (rowExtent <= 0) return;
    final top = index * rowExtent;
    final visible = top >= position.pixels &&
        top + rowExtent <= position.pixels + viewport;
    if (visible) return;
    final target = (top - (viewport - rowExtent) / 2)
        .clamp(0.0, position.maxScrollExtent);
    unawaited(
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  /// Applies a click on [commit] to the selection, given the [visible]
  /// (search-filtered) rows a Shift+click range is taken from.
  void _handleTap(CommitEntry commit, List<CommitEntry> visible) {
    final keys = HardwareKeyboard.instance;
    final toggle = keys.isControlPressed || keys.isMetaPressed;
    final anchorIndex = _anchorId == null
        ? -1
        : visible.indexWhere((c) => c.id == _anchorId);

    final Set<String> ids;
    if (keys.isShiftPressed && anchorIndex != -1) {
      final index = visible.indexOf(commit);
      ids = {
        if (toggle) ...widget.selectedIds,
        for (var i = math.min(anchorIndex, index);
            i <= math.max(anchorIndex, index);
            i++)
          visible[i].id,
      };
    } else if (toggle) {
      ids = {...widget.selectedIds};
      if (!ids.remove(commit.id)) ids.add(commit.id);
      // The last selected commit can't be deselected.
      if (ids.isEmpty) return;
      _anchorId = commit.id;
    } else {
      ids = {commit.id};
      _anchorId = commit.id;
    }

    final selection = [
      for (final c in widget.commits)
        if (ids.contains(c.id)) c,
    ];
    if (selection.isNotEmpty) widget.onSelect(selection);
  }

  List<CommitEntry> get _filteredCommits {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.commits;
    return widget.commits.where((commit) {
      return commit.summary.toLowerCase().contains(query) ||
          commit.id.toLowerCase().contains(query) ||
          commit.author.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final commits = _filteredCommits;
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: _SearchField(
            controller: _searchController,
            hasQuery: _query.isNotEmpty,
            onChanged: (value) => setState(() => _query = value),
            onClear: () {
              _searchController.clear();
              setState(() => _query = '');
            },
          ),
        ),
        Expanded(
          child: commits.isEmpty
              ? Center(
                  child: Text(
                    widget.commits.isEmpty
                        ? 'No commits yet'
                        : 'No commits match your search',
                    style: TextStyle(color: b.muted),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  itemCount: commits.length,
                  // All rows are one line of summary + one of metadata, so
                  // they share a height; this also makes scrolling to a
                  // commit exact.
                  prototypeItem: _CommitTile(
                    commit: commits.first,
                    now: now,
                    selected: false,
                    onTap: () {},
                  ),
                  itemBuilder: (context, index) {
                    final commit = commits[index];
                    return _CommitTile(
                      commit: commit,
                      now: now,
                      selected: widget.selectedIds.contains(commit.id),
                      onTap: () => _handleTap(commit, commits),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hasQuery,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final bool hasQuery;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: b.hover,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 14, color: b.muted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: TextStyle(fontSize: 13, color: b.fg),
              cursorColor: b.fg,
              cursorHeight: 14,
              decoration: InputDecoration(
                hintText: 'Search commits',
                hintStyle: TextStyle(fontSize: 13, color: b.muted),
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (hasQuery)
            InkWell(
              onTap: onClear,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.close, size: 14, color: b.muted),
              ),
            ),
        ],
      ),
    );
  }
}

class _CommitTile extends StatelessWidget {
  const _CommitTile({
    required this.commit,
    required this.now,
    required this.selected,
    required this.onTap,
  });

  final CommitEntry commit;
  final DateTime now;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final dotColor = selected ? b.accent : b.muted;
    return Material(
      color: selected ? b.hover : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: b.hover,
        splashFactory: NoSplash.splashFactory,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                width: 2,
                color: selected ? b.accent : Colors.transparent,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 10,
                child: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Center(
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: commit.isMergeCommit ? null : dotColor,
                        border: Border.all(color: dotColor, width: 1.5),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      commit.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: b.fg,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Tooltip(
                      message: formatCommitDate(commit.time),
                      waitDuration: const Duration(milliseconds: 600),
                      child: Text(
                        '${commit.author} · ${formatRelativeTime(commit.time, now)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: b.muted),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  commit.shortId,
                  style: b.mono(fontSize: 11, color: b.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const List<String> _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Compact relative time for commit rows: "just now", "5m ago", "3h ago",
/// "2d ago", then "Sep 25" (or "Sep 25, 2023" for other years).
String formatRelativeTime(DateTime time, DateTime now) {
  final local = time.toLocal();
  final diff = now.difference(local);
  if (diff.isNegative || diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  final date = '${_monthNames[local.month - 1]} ${local.day}';
  return local.year == now.year ? date : '$date, ${local.year}';
}

/// Absolute commit date, e.g. "Sep 26, 2025, 12:26".
String formatCommitDate(DateTime time) {
  final local = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${_monthNames[local.month - 1]} ${local.day}, ${local.year}, '
      '${two(local.hour)}:${two(local.minute)}';
}
