import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../l10n/app_locale.dart';
import '../theme/app_theme.dart';

/// One `<<<<<<< / ======= / >>>>>>>` block left in a file by a merge.
/// Indexes are 0-based line numbers.
class ConflictBlock {
  const ConflictBlock({
    required this.start,
    required this.mid,
    required this.end,
    this.base,
  });

  /// The `<<<<<<<` line, the optional `|||||||` (diff3) line, the `=======`
  /// line and the `>>>>>>>` line.
  final int start;
  final int? base;
  final int mid;
  final int end;

  /// "mine" (the current branch) and "theirs" (the merged branch).
  List<String> mine(List<String> lines) =>
      lines.sublist(start + 1, base ?? mid);
  List<String> theirs(List<String> lines) => lines.sublist(mid + 1, end);
}

/// Finds complete conflict blocks in [lines]. Unfinished ones are ignored.
List<ConflictBlock> findConflicts(List<String> lines) {
  final blocks = <ConflictBlock>[];
  int? start;
  int? base;
  int? mid;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.startsWith('<<<<<<<')) {
      start = i;
      base = null;
      mid = null;
    } else if (start != null && mid == null && line.startsWith('|||||||')) {
      base = i;
    } else if (start != null && mid == null && line.startsWith('=======')) {
      mid = i;
    } else if (start != null && mid != null && line.startsWith('>>>>>>>')) {
      blocks.add(ConflictBlock(start: start, base: base, mid: mid, end: i));
      start = null;
    }
  }
  return blocks;
}

/// Which side(s) of a conflict to keep.
enum ConflictChoice { mine, theirs, both }

/// The text that replaces [block] for [choice].
List<String> resolveBlock(
  List<String> lines,
  ConflictBlock block,
  ConflictChoice choice,
) =>
    switch (choice) {
      ConflictChoice.mine => block.mine(lines),
      ConflictChoice.theirs => block.theirs(lines),
      ConflictChoice.both => [...block.mine(lines), ...block.theirs(lines)],
    };

/// Bar above the editor while a file has conflict blocks: "Conflict 1 of 3",
/// previous/next, and Use mine / Use theirs / Use both for the block at the
/// cursor. Once the blocks are gone it offers [onMarkResolved].
class ConflictBar extends StatelessWidget {
  const ConflictBar({
    super.key,
    required this.controller,
    required this.onMarkResolved,
    required this.onDismissResolved,
    required this.showResolved,
    this.mineIsBottom = false,
  });

  /// True during a rebase: git puts the new base on top and the user's own
  /// commit at the bottom, so "mine" is the bottom block.
  final bool mineIsBottom;

  final CodeLineEditingController controller;

  /// Saves and stages the file; null when it isn't in a git repo.
  final VoidCallback? onMarkResolved;
  final VoidCallback onDismissResolved;

  /// Whether to offer "Mark as resolved" when no blocks are left (the file
  /// had conflicts earlier in this session).
  final bool showResolved;

  /// Files longer than this aren't scanned on every edit.
  static const _maxLines = 50000;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final codeLines = controller.codeLines;
        if (codeLines.length > _maxLines) return const SizedBox.shrink();
        final lines = [
          for (var i = 0; i < codeLines.length; i++) codeLines[i].text,
        ];
        final blocks = findConflicts(lines);
        if (blocks.isEmpty) {
          return showResolved ? _resolved(context) : const SizedBox.shrink();
        }
        return _bar(context, lines, blocks);
      },
    );
  }

  /// The block at or after the cursor, else the last one.
  int _currentIndex(List<ConflictBlock> blocks) {
    final cursor = controller.selection.extentIndex;
    for (var i = 0; i < blocks.length; i++) {
      if (blocks[i].end >= cursor) return i;
    }
    return blocks.length - 1;
  }

  void _select(ConflictBlock block) {
    controller.selection = CodeLineSelection(
      baseIndex: block.start,
      baseOffset: 0,
      extentIndex: block.end,
      extentOffset: controller.codeLines[block.end].length,
    );
    controller.makeCursorCenterIfInvisible();
  }

  void _apply(List<String> lines, ConflictBlock block, ConflictChoice choice) {
    final keep = resolveBlock(lines, block, choice);
    final last = controller.codeLines.length - 1;
    if (keep.isEmpty && block.end < last) {
      // Remove the block's lines entirely, line breaks included.
      controller.replaceSelection(
        '',
        CodeLineSelection(
          baseIndex: block.start,
          baseOffset: 0,
          extentIndex: block.end + 1,
          extentOffset: 0,
        ),
      );
    } else {
      controller.replaceSelection(
        keep.join('\n'),
        CodeLineSelection(
          baseIndex: block.start,
          baseOffset: 0,
          extentIndex: block.end,
          extentOffset: controller.codeLines[block.end].length,
        ),
      );
    }
    // Move on to the next conflict, if any.
    final rest = findConflicts([
      for (var i = 0; i < controller.codeLines.length; i++)
        controller.codeLines[i].text,
    ]);
    final next = rest.where((b) => b.start >= block.start).firstOrNull ??
        rest.firstOrNull;
    if (next != null) _select(next);
  }

  Widget _frame(BuildContext context, Color color, List<Widget> children) {
    final b = context.branchi;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border(bottom: BorderSide(color: b.line)),
      ),
      child: Row(children: children),
    );
  }

  Widget _button(
    BuildContext context,
    String label,
    VoidCallback? onPressed, {
    String? tooltip,
    bool primary = false,
  }) {
    final b = context.branchi;
    final button = primary
        ? FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              textStyle: const TextStyle(fontSize: 12),
            ),
            child: Text(label),
          )
        : OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              textStyle: const TextStyle(fontSize: 12),
              foregroundColor: b.fg,
              side: BorderSide(color: b.line),
            ),
            child: Text(label),
          );
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 6),
      child: tooltip == null ? button : Tooltip(message: tooltip, child: button),
    );
  }

  Widget _bar(
    BuildContext context,
    List<String> lines,
    List<ConflictBlock> blocks,
  ) {
    final b = context.branchi;
    final index = _currentIndex(blocks);
    final block = blocks[index];
    // "<<<<<<< HEAD" / ">>>>>>> feature/login" name the two sides.
    String side(String marker) {
      final name = marker.length > 8 ? marker.substring(8).trim() : '';
      return name.isEmpty ? '' : ' ($name)';
    }

    final mineName = side(lines[block.start]);
    final theirsName = side(lines[block.end]);
    return _frame(context, b.mod, [
      Icon(Icons.call_merge, size: 16, color: b.mod),
      const SizedBox(width: 8),
      Text(
        translate('conflict_n_of')
            .replaceAll('{n}', '${index + 1}')
            .replaceAll('{count}', '${blocks.length}'),
        style: TextStyle(color: b.fg, fontSize: 12, fontWeight: FontWeight.w600),
      ),
      const SizedBox(width: 4),
      IconButton(
        tooltip: translate('conflict_previous'),
        visualDensity: VisualDensity.compact,
        iconSize: 16,
        onPressed: () => _select(blocks[(index - 1) % blocks.length]),
        icon: const Icon(Icons.keyboard_arrow_up),
      ),
      IconButton(
        tooltip: translate('conflict_next'),
        visualDensity: VisualDensity.compact,
        iconSize: 16,
        onPressed: () => _select(
          // When the cursor is before the current block, "next" is it.
          controller.selection.extentIndex < block.start ||
                  (controller.selection.baseIndex != block.start)
              ? block
              : blocks[(index + 1) % blocks.length],
        ),
        icon: const Icon(Icons.keyboard_arrow_down),
      ),
      const Spacer(),
      _button(
        context,
        translate('merge_use_mine'),
        () => _apply(
          lines,
          block,
          mineIsBottom ? ConflictChoice.theirs : ConflictChoice.mine,
        ),
        tooltip: translate('conflict_mine_tip') +
            (mineIsBottom ? theirsName : mineName),
      ),
      _button(
        context,
        translate('merge_use_theirs'),
        () => _apply(
          lines,
          block,
          mineIsBottom ? ConflictChoice.mine : ConflictChoice.theirs,
        ),
        tooltip: translate('conflict_theirs_tip') +
            (mineIsBottom ? mineName : theirsName),
      ),
      _button(
        context,
        translate('conflict_use_both'),
        () => _apply(lines, block, ConflictChoice.both),
        tooltip: translate('conflict_both_tip'),
      ),
    ]);
  }

  Widget _resolved(BuildContext context) {
    final b = context.branchi;
    return _frame(context, b.add, [
      Icon(Icons.check_circle_outline, size: 16, color: b.add),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          translate('conflict_file_clear'),
          style: TextStyle(color: b.fg, fontSize: 12),
        ),
      ),
      TextButton(
        onPressed: onDismissResolved,
        child: Text(translate('conflict_not_now')),
      ),
      if (onMarkResolved != null)
        _button(
          context,
          translate('merge_mark_resolved'),
          onMarkResolved,
          tooltip: translate('merge_mark_resolved_tip'),
          primary: true,
        ),
    ]);
  }
}
