import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../theme/app_theme.dart';
import 'changes/unified_diff_view.dart';
import 'models.dart';

/// Status bar shown at the top of the commit-log column: summarizes the
/// working tree's uncommitted changes and, when tapped, switches the third
/// column to show them.
class WorkingChangesBar extends StatelessWidget {
  const WorkingChangesBar({
    super.key,
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final List<StatusEntry> status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = status.length;
    final staged = status.where((e) => e.isStaged).length;

    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.pending_actions,
                size: 18,
                color: count == 0 ? scheme.onSurfaceVariant : scheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  count == 0
                      ? 'No uncommitted changes'
                      : '$count changed file${count == 1 ? '' : 's'}'
                          '${staged > 0 ? ' · $staged staged' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// Third-column pane shown for the Changes section: a 380px column listing
/// staged and unstaged files with the commit form underneath, and a detail
/// pane on the right with the selected file's diff and stage/unstage/discard
/// actions.
class WorkingChangesDetail extends StatefulWidget {
  const WorkingChangesDetail({
    super.key,
    required this.status,
    required this.isLoading,
    required this.error,
    required this.canPush,
    required this.onStage,
    required this.onUnstage,
    required this.onRevert,
    required this.onCommit,
    required this.onCommitAndPush,
    required this.onOpenFile,
    required this.onRefresh,
    this.branchName,
    this.loadDiff,
  });

  final List<StatusEntry> status;
  final bool isLoading;
  final String? error;
  final bool canPush;
  final FutureOr<void> Function(StatusEntry entry) onStage;
  final FutureOr<void> Function(StatusEntry entry) onUnstage;
  final FutureOr<void> Function(StatusEntry entry) onRevert;
  final Future<bool> Function(String message) onCommit;
  final Future<bool> Function(String message) onCommitAndPush;
  final ValueChanged<StatusEntry> onOpenFile;
  final VoidCallback onRefresh;

  /// The checked-out branch, shown on the commit button ("Commit to main").
  final String? branchName;

  /// Loads the unified-diff patch of [entry]'s staged (index vs HEAD) or
  /// unstaged (working tree vs index) changes. When null the diff pane shows
  /// a placeholder instead.
  final Future<String?> Function(StatusEntry entry, {required bool staged})?
      loadDiff;

  @override
  State<WorkingChangesDetail> createState() => _WorkingChangesDetailState();
}

/// Identifies a row in the file list: the same path can appear in both the
/// staged and the unstaged section.
typedef _Selection = ({String path, bool staged});

class _WorkingChangesDetailState extends State<WorkingChangesDetail> {
  final _summaryController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isCommitting = false;
  bool _isBulkUpdating = false;

  _Selection? _selected;

  // Diff of the selected row.
  int _diffRequest = 0;
  bool _isDiffLoading = false;
  String? _diffError;
  ParsedDiff? _diff;

  List<StatusEntry> get _staged =>
      widget.status.where((e) => e.staged != null).toList();
  List<StatusEntry> get _unstaged =>
      widget.status.where((e) => e.unstaged != null).toList();

  @override
  void initState() {
    super.initState();
    _syncSelection();
  }

  @override
  void didUpdateWidget(covariant WorkingChangesDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.status, widget.status) ||
        oldWidget.loadDiff != widget.loadDiff) {
      _syncSelection(force: true);
    }
  }

  @override
  void dispose() {
    _summaryController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  StatusEntry? _entryFor(_Selection? sel) {
    if (sel == null) return null;
    for (final e in widget.status) {
      if (e.path != sel.path) continue;
      if (sel.staged ? e.staged != null : e.unstaged != null) return e;
    }
    return null;
  }

  /// Keeps [_selected] pointing at an existing row: if the selected file
  /// moved sections (e.g. after staging it) follow it, else fall back to the
  /// first row.
  void _syncSelection({bool force = false}) {
    final previous = _selected;
    _Selection? next;
    if (_entryFor(previous) != null) {
      next = previous;
    } else if (previous != null &&
        _entryFor((path: previous.path, staged: !previous.staged)) != null) {
      next = (path: previous.path, staged: !previous.staged);
    } else if (_staged.isNotEmpty) {
      next = (path: _staged.first.path, staged: true);
    } else if (_unstaged.isNotEmpty) {
      next = (path: _unstaged.first.path, staged: false);
    }
    if (force || next != previous) {
      if (next != previous) _diff = null;
      _selected = next;
      _loadDiff();
    }
  }

  void _select(_Selection sel) {
    if (sel == _selected) return;
    setState(() {
      _selected = sel;
      _diff = null;
      _loadDiff();
    });
  }

  void _loadDiff() {
    final request = ++_diffRequest;
    final entry = _entryFor(_selected);
    final load = widget.loadDiff;
    if (entry == null || load == null) {
      _isDiffLoading = false;
      _diffError = null;
      _diff = null;
      return;
    }
    _isDiffLoading = true;
    _diffError = null;
    final staged = _selected!.staged;
    () async {
      try {
        final patch = await load(entry, staged: staged);
        if (!mounted || request != _diffRequest) return;
        setState(() {
          _isDiffLoading = false;
          _diff = patch == null ? null : ParsedDiff.parse(patch);
        });
      } catch (error) {
        if (!mounted || request != _diffRequest) return;
        setState(() {
          _isDiffLoading = false;
          _diff = null;
          _diffError = error.toString();
        });
      }
    }();
  }

  String get _message {
    final summary = _summaryController.text.trim();
    final description = _descriptionController.text.trim();
    return description.isEmpty ? summary : '$summary\n\n$description';
  }

  bool get _canCommit =>
      !_isCommitting &&
      _summaryController.text.trim().isNotEmpty &&
      widget.status.any((e) => e.isStaged);

  Future<void> _commit({required bool push}) async {
    if (!_canCommit) return;
    setState(() => _isCommitting = true);
    final message = _message;
    final ok = push
        ? await widget.onCommitAndPush(message)
        : await widget.onCommit(message);
    if (!mounted) return;
    setState(() => _isCommitting = false);
    if (ok) {
      _summaryController.clear();
      _descriptionController.clear();
    }
  }

  Future<void> _bulk(
    List<StatusEntry> entries,
    FutureOr<void> Function(StatusEntry) action,
  ) async {
    if (entries.isEmpty || _isBulkUpdating) return;
    setState(() => _isBulkUpdating = true);
    try {
      // Sequential: each call writes the index, which git locks.
      for (final e in entries) {
        await action(e);
        if (!mounted) return;
      }
    } finally {
      if (mounted) setState(() => _isBulkUpdating = false);
    }
  }

  Future<void> _showRowMenu(
    Offset position,
    StatusEntry entry,
    bool staged,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
            value: 'open', child: Text(translate('changes_open_in_editor'))),
        if (staged)
          PopupMenuItem(
              value: 'unstage', child: Text(translate('changes_unstage_file')))
        else
          PopupMenuItem(
              value: 'stage', child: Text(translate('changes_stage_file'))),
        if (entry.unstaged != null)
          PopupMenuItem(
              value: 'revert', child: Text(translate('changes_discard'))),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case 'open':
        widget.onOpenFile(entry);
      case 'stage':
        await widget.onStage(entry);
      case 'unstage':
        await widget.onUnstage(entry);
      case 'revert':
        await widget.onRevert(entry);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return ColoredBox(
      color: b.bg,
      child: DefaultTextStyle.merge(
        style: TextStyle(color: b.fg, fontSize: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 380,
              decoration: BoxDecoration(
                border: BorderDirectional(end: b.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _buildFileList(context)),
                  _buildCommitForm(context),
                ],
              ),
            ),
            Expanded(child: _buildDetail(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildFileList(BuildContext context) {
    final b = context.branchi;
    if (widget.isLoading && widget.status.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (widget.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            translate('changes_load_failed')
                .replaceAll('{error}', widget.error!),
            style: TextStyle(color: b.del),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (widget.status.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(translate('changes_no_changes'),
                style: TextStyle(color: b.muted)),
            const SizedBox(height: 8),
            _TextAction(
              label: translate('changes_refresh'),
              onTap: widget.onRefresh,
            ),
          ],
        ),
      );
    }

    final staged = _staged;
    final unstaged = _unstaged;
    final busy = _isBulkUpdating || widget.isLoading;
    return ListView(
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        _SectionHeader(
          top: 18,
          label: '${translate('changes_staged')} · ${staged.length}',
          action: translate('changes_unstage_all'),
          onAction: busy || staged.isEmpty
              ? null
              : () => _bulk(staged, widget.onUnstage),
          onRefresh: widget.isLoading ? null : widget.onRefresh,
        ),
        for (final e in staged) _row(e, staged: true),
        _SectionHeader(
          top: 22,
          label: '${translate('changes_unstaged')} · ${unstaged.length}',
          action: translate('changes_stage_all'),
          onAction: busy || unstaged.isEmpty
              ? null
              : () => _bulk(unstaged, widget.onStage),
        ),
        for (final e in unstaged) _row(e, staged: false),
      ],
    );
  }

  Widget _row(StatusEntry entry, {required bool staged}) {
    final sel = (path: entry.path, staged: staged);
    return _FileRow(
      key: ValueKey(sel),
      entry: entry,
      status: staged ? entry.staged! : entry.unstaged!,
      selected: sel == _selected,
      onTap: () => _select(sel),
      onSecondaryTap: (pos) => _showRowMenu(pos, entry, staged),
    );
  }

  Widget _buildCommitForm(BuildContext context) {
    final b = context.branchi;
    final branch = widget.branchName;
    final commitLabel = branch == null || branch.isEmpty
        ? translate('changes_commit')
        : translate('changes_commit_to').replaceAll('{branch}', branch);
    final canCommit = _canCommit;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(border: Border(top: b.hairline)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FieldLabel(translate('changes_summary')),
          TextField(
            controller: _summaryController,
            style: TextStyle(color: b.fg, fontSize: 13),
            textAlignVertical: TextAlignVertical.center,
            decoration: _inputDecoration(b).copyWith(
              constraints: const BoxConstraints.tightFor(height: 36),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _commit(push: false),
          ),
          const SizedBox(height: 10),
          _FieldLabel(translate('changes_description')),
          TextField(
            controller: _descriptionController,
            style: TextStyle(color: b.fg, fontSize: 13),
            minLines: 3,
            maxLines: 3,
            decoration: _inputDecoration(b).copyWith(
              hintText: translate('changes_optional'),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _AccentButton(
                  label: commitLabel,
                  busy: _isCommitting,
                  onPressed: canCommit ? () => _commit(push: false) : null,
                ),
              ),
              const SizedBox(width: 8),
              _MoreButton(
                tooltip: translate('changes_more_options'),
                items: [
                  PopupMenuItem(
                    value: 'push',
                    enabled: canCommit && widget.canPush,
                    child: Text(translate('changes_commit_and_push')),
                  ),
                ],
                onSelected: (value) {
                  if (value == 'push') _commit(push: true);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(BranchiColors b) {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: color),
        );
    return InputDecoration(
      isDense: true,
      filled: false,
      hintStyle: TextStyle(color: b.muted, fontSize: 13),
      border: border(b.line),
      enabledBorder: border(b.line),
      focusedBorder: border(b.accent),
    );
  }

  Widget _buildDetail(BuildContext context) {
    final b = context.branchi;
    final sel = _selected;
    final entry = _entryFor(sel);
    if (sel == null || entry == null) {
      return Center(
        child: Text(
          widget.status.isEmpty ? '' : translate('changes_select_file'),
          style: TextStyle(color: b.muted),
        ),
      );
    }
    final diff = _diff;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          decoration: BoxDecoration(border: Border(bottom: b.hairline)),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  entry.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: b.mono(fontSize: 12),
                ),
              ),
              if (diff != null && !diff.isBinary) ...[
                const SizedBox(width: 12),
                Text('+${diff.additions}',
                    style: TextStyle(color: b.add, fontSize: 12)),
                const SizedBox(width: 6),
                Text('−${diff.deletions}',
                    style: TextStyle(color: b.del, fontSize: 12)),
              ],
              const Spacer(),
              _IconAction(
                icon: Icons.open_in_new,
                tooltip: translate('changes_open_in_editor'),
                onTap: () => widget.onOpenFile(entry),
              ),
              if (!sel.staged) ...[
                const SizedBox(width: 6),
                _OutlinedSmallButton(
                  label: translate('changes_discard'),
                  color: b.del,
                  onTap: () => widget.onRevert(entry),
                ),
              ],
              const SizedBox(width: 6),
              _OutlinedSmallButton(
                label: translate(
                    sel.staged ? 'changes_unstage_file' : 'changes_stage_file'),
                onTap: () => sel.staged
                    ? widget.onUnstage(entry)
                    : widget.onStage(entry),
              ),
            ],
          ),
        ),
        Expanded(child: _buildDiffBody(context)),
      ],
    );
  }

  Widget _buildDiffBody(BuildContext context) {
    final b = context.branchi;
    if (widget.loadDiff == null) {
      return Center(
        child: Text(
          translate('changes_diff_unavailable'),
          style: TextStyle(color: b.muted),
        ),
      );
    }
    if (_isDiffLoading && _diff == null) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_diffError != null) {
      return Center(
        child: Text(
          translate('changes_diff_failed').replaceAll('{error}', _diffError!),
          style: TextStyle(color: b.del),
        ),
      );
    }
    final diff = _diff;
    if (diff == null) {
      return Center(
        child: Text(translate('changes_no_diff'),
            style: TextStyle(color: b.muted)),
      );
    }
    return UnifiedDiffView(diff: diff);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.top,
    required this.label,
    required this.action,
    required this.onAction,
    this.onRefresh,
  });

  final double top;
  final String label;
  final String action;
  final VoidCallback? onAction;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(20, top, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: b.muted,
                fontSize: 11,
                letterSpacing: 0.44,
              ),
            ),
          ),
          if (onRefresh != null) ...[
            _IconAction(
              icon: Icons.refresh,
              size: 14,
              tooltip: translate('changes_refresh'),
              onTap: onRefresh!,
            ),
            const SizedBox(width: 8),
          ],
          _TextAction(label: action, onTap: onAction),
        ],
      ),
    );
  }
}

class _TextAction extends StatefulWidget {
  const _TextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  State<_TextAction> createState() => _TextActionState();
}

class _TextActionState extends State<_TextAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final enabled = widget.onTap != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          widget.label,
          style: TextStyle(
            fontSize: 12,
            color: !enabled
                ? b.muted.withValues(alpha: 0.5)
                : _hover
                    ? b.fg
                    : b.muted,
          ),
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 16,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        hoverColor: b.hover,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: size, color: b.muted),
        ),
      ),
    );
  }
}

class _FileRow extends StatefulWidget {
  const _FileRow({
    super.key,
    required this.entry,
    required this.status,
    required this.selected,
    required this.onTap,
    required this.onSecondaryTap,
  });

  final StatusEntry entry;
  final FileChangeStatus status;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<Offset> onSecondaryTap;

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final path = widget.entry.path;
    final slash = path.lastIndexOf('/');
    final name = slash < 0 ? path : path.substring(slash + 1);
    final dir = slash < 0 ? '' : path.substring(0, slash);
    final (letter, color) = statusLetter(b, widget.status);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onSecondaryTapUp: (d) => widget.onSecondaryTap(d.globalPosition),
        child: Tooltip(
          message: path,
          waitDuration: const Duration(milliseconds: 700),
          child: Container(
            padding: const EdgeInsetsDirectional.fromSTEB(18, 8, 20, 8),
            decoration: BoxDecoration(
              color: widget.selected || _hover ? b.hover : null,
              border: BorderDirectional(
                start: BorderSide(
                  width: 2,
                  color: widget.selected ? b.accent : Colors.transparent,
                ),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  child: Text(letter, style: b.mono(fontSize: 11, color: color)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: b.fg, fontSize: 13),
                  ),
                ),
                if (dir.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      dir,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(color: b.muted, fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The one-letter status code and its color for [status].
(String, Color) statusLetter(BranchiColors b, FileChangeStatus status) =>
    switch (status) {
      FileChangeStatus.new_ => ('A', b.add),
      FileChangeStatus.modified => ('M', b.mod),
      FileChangeStatus.deleted => ('D', b.del),
      FileChangeStatus.renamed => ('R', b.accent),
      FileChangeStatus.typechange => ('T', b.mod),
      FileChangeStatus.conflicted => ('!', b.del),
    };

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(color: context.branchi.muted, fontSize: 11),
      ),
    );
  }
}

class _AccentButton extends StatelessWidget {
  const _AccentButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled || busy ? 1 : 0.45,
      child: Material(
        color: b.accent,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            height: 36,
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MoreButton extends StatelessWidget {
  const _MoreButton({
    required this.tooltip,
    required this.items,
    required this.onSelected,
  });

  final String tooltip;
  final List<PopupMenuEntry<String>> items;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return PopupMenuButton<String>(
      tooltip: tooltip,
      onSelected: onSelected,
      itemBuilder: (_) => items,
      position: PopupMenuPosition.over,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          border: Border.fromBorderSide(b.hairline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.keyboard_arrow_down, size: 16, color: b.fg),
      ),
    );
  }
}

class _OutlinedSmallButton extends StatelessWidget {
  const _OutlinedSmallButton({
    required this.label,
    required this.onTap,
    this.color,
  });

  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        hoverColor: b.hover,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            border: Border.fromBorderSide(b.hairline),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: color ?? b.fg),
          ),
        ),
      ),
    );
  }
}
