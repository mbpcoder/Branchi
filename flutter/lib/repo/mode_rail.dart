import 'package:flutter/material.dart';

enum RepoViewMode { code, git }

/// Narrow vertical action rail on the far left of an opened repository,
/// switching between the "Code" (file tree + editor) and "Git" (branches +
/// commits) views.
class ModeRail extends StatelessWidget {
  const ModeRail({super.key, required this.mode, required this.onChanged});

  final RepoViewMode mode;
  final ValueChanged<RepoViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            _ModeButton(
              icon: Icons.code,
              tooltip: 'Code',
              selected: mode == RepoViewMode.code,
              onTap: () => onChanged(RepoViewMode.code),
            ),
            _ModeButton(
              icon: Icons.account_tree_outlined,
              tooltip: 'Git',
              selected: mode == RepoViewMode.git,
              onTap: () => onChanged(RepoViewMode.git),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.15)
                : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
