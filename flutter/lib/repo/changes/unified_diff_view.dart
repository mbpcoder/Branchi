import 'package:flutter/material.dart';

import '../../l10n/app_locale.dart';
import '../../theme/app_theme.dart';

enum DiffLineKind { context, add, del }

class DiffLine {
  const DiffLine(this.kind, this.number, this.text);

  final DiffLineKind kind;

  /// New-side line number for context/added lines, old-side for deletions.
  final int? number;
  final String text;
}

class DiffHunk {
  DiffHunk(this.header);

  final String header;
  final List<DiffLine> lines = [];
}

/// A unified diff (`git diff` style patch) parsed into hunks.
class ParsedDiff {
  ParsedDiff._(this.hunks, this.additions, this.deletions, this.isBinary);

  factory ParsedDiff.parse(String patch) {
    final hunks = <DiffHunk>[];
    var additions = 0;
    var deletions = 0;
    var isBinary = false;
    DiffHunk? current;
    var oldN = 0;
    var newN = 0;
    final header = RegExp(r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@');

    for (final raw in patch.split('\n')) {
      final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
      final match = header.firstMatch(line);
      if (match != null) {
        oldN = int.parse(match.group(1)!);
        newN = int.parse(match.group(2)!);
        current = DiffHunk(line);
        hunks.add(current);
        continue;
      }
      if (current == null) {
        if (line.startsWith('Binary files') || line.startsWith('GIT binary')) {
          isBinary = true;
        }
        continue;
      }
      if (line.startsWith('+')) {
        current.lines.add(DiffLine(DiffLineKind.add, newN++, line.substring(1)));
        additions++;
      } else if (line.startsWith('-')) {
        current.lines.add(DiffLine(DiffLineKind.del, oldN++, line.substring(1)));
        deletions++;
      } else if (line.startsWith(' ')) {
        current.lines
            .add(DiffLine(DiffLineKind.context, newN, line.substring(1)));
        oldN++;
        newN++;
      } else if (line.startsWith('diff --git')) {
        // Start of another file's patch: stop attaching lines to this hunk.
        current = null;
      }
      // "\ No newline at end of file" and trailing blanks are skipped.
    }
    return ParsedDiff._(hunks, additions, deletions, isBinary);
  }

  final List<DiffHunk> hunks;
  final int additions;
  final int deletions;
  final bool isBinary;
}

/// Renders a [ParsedDiff] as a stack of bordered, 8px-radius hunk boxes with
/// a muted header row, a line-number gutter and tinted +/− rows.
class UnifiedDiffView extends StatelessWidget {
  const UnifiedDiffView({super.key, required this.diff});

  final ParsedDiff diff;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    if (diff.isBinary || diff.hunks.isEmpty) {
      return Center(
        child: Text(
          translate(diff.isBinary ? 'changes_binary_file' : 'changes_no_diff'),
          style: TextStyle(color: b.muted),
        ),
      );
    }
    return SelectionArea(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
        itemCount: diff.hunks.length,
        itemBuilder: (context, i) => Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 16),
          child: _HunkBox(hunk: diff.hunks[i]),
        ),
      ),
    );
  }
}

class _HunkBox extends StatelessWidget {
  const _HunkBox({required this.hunk});

  final DiffHunk hunk;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final style = b.mono(fontSize: 12, height: 22 / 12);
    return Directionality(
      // Code is always laid out left-to-right, even in RTL locales.
      textDirection: TextDirection.ltr,
      child: Container(
        decoration: BoxDecoration(
          border: Border.fromBorderSide(b.hairline),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: IntrinsicWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      color: b.hover,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      child: Text(
                        hunk.header,
                        style: style.copyWith(color: b.muted),
                      ),
                    ),
                    for (final line in hunk.lines) _row(b, style, line),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(BranchiColors b, TextStyle style, DiffLine line) {
    final (sign, color, bg) = switch (line.kind) {
      DiffLineKind.add => ('+', b.add, b.addBg),
      DiffLineKind.del => ('−', b.del, b.delBg),
      DiffLineKind.context => ('', b.fg, Colors.transparent),
    };
    return Container(
      color: bg,
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                line.number?.toString() ?? '',
                textAlign: TextAlign.right,
                style: style.copyWith(color: b.muted),
              ),
            ),
          ),
          SizedBox(
            width: 16,
            child: Text(sign, style: style.copyWith(color: color)),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(
              line.text,
              softWrap: false,
              style: style.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
