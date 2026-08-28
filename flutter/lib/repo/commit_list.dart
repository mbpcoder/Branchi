import 'package:flutter/material.dart';

import 'models.dart';

/// Middle pane: the commit log for the open repo, newest first.
class CommitList extends StatelessWidget {
  const CommitList({
    super.key,
    required this.commits,
    required this.selectedId,
    required this.onSelect,
  });

  final List<CommitEntry> commits;
  final String? selectedId;
  final ValueChanged<CommitEntry> onSelect;

  @override
  Widget build(BuildContext context) {
    if (commits.isEmpty) {
      return const Center(child: Text('No commits yet'));
    }

    return ListView.builder(
      itemCount: commits.length,
      itemBuilder: (context, index) {
        final commit = commits[index];
        final selected = commit.id == selectedId;
        return _CommitTile(
          commit: commit,
          selected: selected,
          onTap: () => onSelect(commit),
        );
      },
    );
  }
}

class _CommitTile extends StatelessWidget {
  const _CommitTile({
    required this.commit,
    required this.selected,
    required this.onTap,
  });

  final CommitEntry commit;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                commit.isMergeCommit ? Icons.merge_type : Icons.circle,
                size: commit.isMergeCommit ? 16 : 10,
                color: scheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      commit.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${commit.author} · ${commit.shortId} · ${_formatDate(commit.time)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime time) {
    final local = time.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
