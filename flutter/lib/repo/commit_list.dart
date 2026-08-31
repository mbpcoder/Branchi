import 'package:flutter/material.dart';

import 'models.dart';

/// Middle pane: the commit log for the open repo, newest first.
class CommitList extends StatefulWidget {
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
  State<CommitList> createState() => _CommitListState();
}

class _CommitListState extends State<CommitList> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    final commits = _filteredCommits;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Search commit message or hash',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ),
        Expanded(
          child: commits.isEmpty
              ? Center(
                  child: Text(
                    widget.commits.isEmpty
                        ? 'No commits yet'
                        : 'No commits match your search',
                  ),
                )
              : ListView.builder(
                  itemCount: commits.length,
                  itemBuilder: (context, index) {
                    final commit = commits[index];
                    final selected = commit.id == widget.selectedId;
                    return _CommitTile(
                      commit: commit,
                      selected: selected,
                      onTap: () => widget.onSelect(commit),
                    );
                  },
                ),
        ),
      ],
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
