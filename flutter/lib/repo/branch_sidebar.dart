import 'package:flutter/material.dart';

import 'models.dart';

/// Left-hand sidebar listing local and remote branches for the open repo.
class BranchSidebar extends StatelessWidget {
  const BranchSidebar({super.key, required this.branches});

  final List<BranchEntry> branches;

  @override
  Widget build(BuildContext context) {
    final local = branches.where((b) => !b.isRemote).toList();
    final remote = branches.where((b) => b.isRemote).toList();

    return Container(
      width: 220,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionHeader('Branches'),
          for (final branch in local) _BranchTile(branch: branch),
          if (remote.isNotEmpty) ...[
            _SectionHeader('Remote'),
            for (final branch in remote) _BranchTile(branch: branch),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}

class _BranchTile extends StatelessWidget {
  const _BranchTile({required this.branch});

  final BranchEntry branch;

  @override
  Widget build(BuildContext context) {
    return ListTile(
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
    );
  }
}
