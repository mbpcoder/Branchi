import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../repo/models.dart';

/// The thin bottom strip holding the terminal and logs toggle buttons, plus
/// (when a repository is open) the active file's detected type and the
/// current branch with a quick-switch dropdown.
class BottomToolbar extends StatelessWidget {
  const BottomToolbar({
    super.key,
    required this.isTerminalOpen,
    required this.onToggleTerminal,
    required this.isLogsOpen,
    required this.onToggleLogs,
    this.fileTypeLabel,
    this.currentBranch,
    this.branches = const [],
    this.onSelectBranch,
  });

  final bool isTerminalOpen;
  final VoidCallback onToggleTerminal;
  final bool isLogsOpen;
  final VoidCallback onToggleLogs;

  /// The active editor tab's detected file type, e.g. "PHP". `null` when no
  /// file is open or the Code tab isn't active.
  final String? fileTypeLabel;

  /// The repository's current (HEAD) branch name, `null` if no repo is open.
  final String? currentBranch;

  /// All local branches, offered in the branch-switch dropdown.
  final List<BranchEntry> branches;

  final ValueChanged<BranchEntry>? onSelectBranch;

  Future<void> _showBranchMenu(BuildContext context, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final local = branches.where((b) => !b.isRemote).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final selected = await showMenu<BranchEntry>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        for (final branch in local)
          PopupMenuItem<BranchEntry>(
            value: branch,
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: branch.isHead
                      ? const Icon(Icons.check, size: 16)
                      : null,
                ),
                Text(branch.name),
              ],
            ),
          ),
      ],
    );
    if (selected == null || selected.isHead) return;
    onSelectBranch?.call(selected);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 32,
      color: colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          IconButton(
            iconSize: 18,
            tooltip: translate('terminal'),
            isSelected: isTerminalOpen,
            style: IconButton.styleFrom(
              padding: EdgeInsets.zero,
              backgroundColor:
                  isTerminalOpen ? colorScheme.surface : Colors.transparent,
            ),
            icon: const Icon(Icons.terminal),
            onPressed: onToggleTerminal,
          ),
          IconButton(
            iconSize: 18,
            tooltip: translate('logs'),
            isSelected: isLogsOpen,
            style: IconButton.styleFrom(
              padding: EdgeInsets.zero,
              backgroundColor:
                  isLogsOpen ? colorScheme.surface : Colors.transparent,
            ),
            icon: const Icon(Icons.receipt_long),
            onPressed: onToggleLogs,
          ),
          const Spacer(),
          if (fileTypeLabel != null) ...[
            Text(
              fileTypeLabel!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(width: 12),
          ],
          if (currentBranch != null)
            Builder(
              builder: (context) => InkWell(
                onTap: () {
                  final box = context.findRenderObject() as RenderBox;
                  final position = box.localToGlobal(
                    box.size.topLeft(Offset.zero),
                  );
                  _showBranchMenu(context, position);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.call_split, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        currentBranch!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
