import 'package:flutter/material.dart';

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

/// Third-column pane shown when [WorkingChangesBar] is selected: a commit
/// message box with Commit/Commit & Push actions, and the list of changed
/// files with a per-file actions menu (stage/unstage/revert).
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
  });

  final List<StatusEntry> status;
  final bool isLoading;
  final String? error;
  final bool canPush;
  final ValueChanged<StatusEntry> onStage;
  final ValueChanged<StatusEntry> onUnstage;
  final ValueChanged<StatusEntry> onRevert;
  final Future<bool> Function(String message) onCommit;
  final Future<bool> Function(String message) onCommitAndPush;
  final ValueChanged<StatusEntry> onOpenFile;

  @override
  State<WorkingChangesDetail> createState() => _WorkingChangesDetailState();
}

class _WorkingChangesDetailState extends State<WorkingChangesDetail> {
  final _messageController = TextEditingController();
  bool _isCommitting = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  bool get _canCommit =>
      !_isCommitting &&
      _messageController.text.trim().isNotEmpty &&
      widget.status.any((e) => e.isStaged);

  Future<void> _commit({required bool push}) async {
    setState(() => _isCommitting = true);
    final message = _messageController.text.trim();
    final ok = push
        ? await widget.onCommitAndPush(message)
        : await widget.onCommit(message);
    if (!mounted) return;
    setState(() => _isCommitting = false);
    if (ok) {
      _messageController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Commit', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _messageController,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Commit message',
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _canCommit ? () => _commit(push: false) : null,
                    child: const Text('Commit'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _canCommit && widget.canPush
                        ? () => _commit(push: true)
                        : null,
                    child: const Text('Commit && Push'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _buildFileList(context)),
      ],
    );
  }

  Widget _buildFileList(BuildContext context) {
    if (widget.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.error != null) {
      return Center(child: Text('Failed to load status: ${widget.error}'));
    }
    if (widget.status.isEmpty) {
      return const Center(child: Text('No uncommitted changes'));
    }
    return ListView(
      children: [
        for (final entry in widget.status)
          _StatusFileTile(
            entry: entry,
            onStage: () => widget.onStage(entry),
            onUnstage: () => widget.onUnstage(entry),
            onRevert: () => widget.onRevert(entry),
            onOpen: () => widget.onOpenFile(entry),
          ),
      ],
    );
  }
}

class _StatusFileTile extends StatelessWidget {
  const _StatusFileTile({
    required this.entry,
    required this.onStage,
    required this.onUnstage,
    required this.onRevert,
    required this.onOpen,
  });

  final StatusEntry entry;
  final VoidCallback onStage;
  final VoidCallback onUnstage;
  final VoidCallback onRevert;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          _StatusLetter(status: entry.staged, filled: true),
          const SizedBox(width: 2),
          _StatusLetter(status: entry.unstaged, filled: false),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'File actions',
            icon: const Icon(Icons.more_horiz, size: 18),
            onSelected: (action) {
              switch (action) {
                case 'open':
                  onOpen();
                  break;
                case 'stage':
                  onStage();
                  break;
                case 'unstage':
                  onUnstage();
                  break;
                case 'revert':
                  onRevert();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'open', child: Text('Open in editor')),
              if (entry.unstaged != null)
                const PopupMenuItem(value: 'stage', child: Text('Stage')),
              if (entry.isStaged)
                const PopupMenuItem(value: 'unstage', child: Text('Unstage')),
              if (entry.unstaged != null)
                const PopupMenuItem(
                  value: 'revert',
                  child: Text('Revert (discard changes)'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusLetter extends StatelessWidget {
  const _StatusLetter({required this.status, required this.filled});

  final FileChangeStatus? status;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final status = this.status;
    if (status == null) {
      return const SizedBox(width: 14);
    }
    final (letter, color) = switch (status) {
      FileChangeStatus.new_ => ('A', Colors.green),
      FileChangeStatus.modified => ('M', Colors.orange),
      FileChangeStatus.deleted => ('D', Colors.red),
      FileChangeStatus.renamed => ('R', Colors.blue),
      FileChangeStatus.typechange => ('T', Colors.purple),
      FileChangeStatus.conflicted => ('!', Colors.red),
    };
    return SizedBox(
      width: 14,
      child: Text(
        letter,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: filled ? color : color.withValues(alpha: 0.55),
          fontWeight: filled ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
      ),
    );
  }
}
