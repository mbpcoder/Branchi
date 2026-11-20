import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'commit_list.dart' show formatCommitDate;
import 'models.dart';

/// Right-hand pane: metadata for the selected commit plus a per-file diff
/// viewer, or a loading/empty/error state.
class CommitDetail extends StatelessWidget {
  const CommitDetail({
    super.key,
    required this.commit,
    required this.diffFiles,
    required this.isLoading,
    required this.error,
    required this.selectedFilePath,
    required this.onSelectFile,
    required this.onOpenFile,
  });

  final CommitEntry? commit;
  final List<DiffFileEntry> diffFiles;
  final bool isLoading;
  final String? error;
  final String? selectedFilePath;
  final ValueChanged<String> onSelectFile;
  final ValueChanged<String> onOpenFile;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final commit = this.commit;
    if (commit == null) {
      return Center(
        child: Text(
          'Select a commit to see its changes',
          style: TextStyle(color: b.muted),
        ),
      );
    }

    final selectedFile = diffFiles.isEmpty
        ? null
        : diffFiles.firstWhere(
            (f) => f.path == selectedFilePath,
            orElse: () => diffFiles.first,
          );

    final Widget body;
    if (isLoading) {
      body = Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: b.muted),
        ),
      );
    } else if (error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Failed to load diff: $error',
            style: TextStyle(color: b.del),
          ),
        ),
      );
    } else if (selectedFile == null) {
      body = Center(
        child: Text('No file changes', style: TextStyle(color: b.muted)),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FileList(
            files: diffFiles,
            selected: selectedFile,
            onSelect: onSelectFile,
            onOpen: onOpenFile,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
              child: _PatchView(
                key: ValueKey('${commit.id}:${selectedFile.path}'),
                file: selectedFile,
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CommitHeader(commit: commit),
        Expanded(child: body),
      ],
    );
  }
}

class _CommitHeader extends StatelessWidget {
  const _CommitHeader({required this.commit});

  final CommitEntry commit;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final meta = TextStyle(fontSize: 12, color: b.muted);
    return Container(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 20),
      decoration: BoxDecoration(border: Border(bottom: b.hairline)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            commit.summary,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.18,
              color: b.fg,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              Tooltip(
                message: commit.email,
                child: Text(commit.author, style: meta),
              ),
              Text(formatCommitDate(commit.time), style: meta),
              Tooltip(
                message: '${commit.id}\nClick to copy',
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: commit.id));
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        const SnackBar(
                          content: Text('Commit hash copied'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    child: Text(
                      commit.shortId,
                      style: b.mono(fontSize: 12, color: b.muted),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The changed files of the commit. The selected one is shown in full
/// colour; the others are muted. The first row also carries the
/// "N files changed" summary on the right.
class _FileList extends StatelessWidget {
  const _FileList({
    required this.files,
    required this.selected,
    required this.onSelect,
    required this.onOpen,
  });

  final List<DiffFileEntry> files;
  final DiffFileEntry selected;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final summary = Text(
      files.length == 1 ? '1 file changed' : '${files.length} files changed',
      style: TextStyle(fontSize: 12, color: b.muted),
    );
    final rows = [
      for (var i = 0; i < files.length; i++)
        _FileRow(
          file: files[i],
          selected: files[i].path == selected.path,
          dimUnselected: files.length > 1,
          trailing: i == 0 ? summary : null,
          onTap: () => onSelect(files[i].path),
          onOpen: () => onOpen(files[i].path),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: files.length <= 6
          ? Column(children: rows)
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 6 * 34.0),
              child: ListView(shrinkWrap: true, children: rows),
            ),
    );
  }
}

class _FileRow extends StatefulWidget {
  const _FileRow({
    required this.file,
    required this.selected,
    required this.dimUnselected,
    required this.onTap,
    required this.onOpen,
    this.trailing,
  });

  final DiffFileEntry file;
  final bool selected;
  final bool dimUnselected;
  final VoidCallback onTap;
  final VoidCallback onOpen;
  final Widget? trailing;

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final file = widget.file;
    final pathColor =
        widget.selected || !widget.dimUnselected ? b.fg : b.muted;
    final (statusLetter, statusLabel, statusColor) = switch (file.status) {
      FileChangeStatus.new_ => ('A', 'Added', b.add),
      FileChangeStatus.modified => ('M', 'Modified', b.mod),
      FileChangeStatus.deleted => ('D', 'Deleted', b.del),
      FileChangeStatus.renamed => ('R', 'Renamed', b.mod),
      FileChangeStatus.typechange => ('T', 'Type changed', b.mod),
      FileChangeStatus.conflicted => ('!', 'Conflicted', b.del),
    };
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: widget.selected && widget.dimUnselected
            ? b.hover
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(6),
          hoverColor: b.hover,
          splashFactory: NoSplash.splashFactory,
          child: SizedBox(
            height: 34,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Tooltip(
                    message: statusLabel,
                    child: Text(
                      statusLetter,
                      style: b.mono(fontSize: 11, color: statusColor),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      file.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: b.mono(fontSize: 12, color: pathColor),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('+${file.additions}',
                      style: TextStyle(fontSize: 12, color: b.add)),
                  const SizedBox(width: 12),
                  Text('−${file.deletions}',
                      style: TextStyle(fontSize: 12, color: b.del)),
                  const SizedBox(width: 8),
                  Opacity(
                    opacity: _hovered ? 1 : 0,
                    child: IconButton(
                      tooltip: 'Open in editor',
                      icon: Icon(Icons.open_in_new, size: 14, color: b.muted),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 24, minHeight: 24),
                      onPressed: widget.onOpen,
                    ),
                  ),
                  const Spacer(),
                  if (widget.trailing != null) widget.trailing!,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _LineKind { add, del, context, hunk, meta }

class _DiffLine {
  const _DiffLine(this.kind, this.number, this.text);

  final _LineKind kind;
  final int? number;
  final String text;
}

/// Parses the unified patch text into displayable rows, dropping the file
/// header (`diff --git`, `---`, `+++` …) and numbering each line by its
/// position in the new file (or the old file, for deletions).
List<_DiffLine> _parsePatch(String patch) {
  final hunkHeader = RegExp(r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@');
  final raw = patch.split('\n');
  if (raw.isNotEmpty && raw.last.isEmpty) raw.removeLast();

  final lines = <_DiffLine>[];
  var inHunk = false;
  var oldNo = 0;
  var newNo = 0;
  for (final line in raw) {
    final match = hunkHeader.firstMatch(line);
    if (match != null) {
      inHunk = true;
      oldNo = int.parse(match.group(1)!);
      newNo = int.parse(match.group(2)!);
      lines.add(_DiffLine(_LineKind.hunk, null, line));
      continue;
    }
    if (!inHunk) {
      // File header lines, or a "Binary files … differ" notice.
      if (line.startsWith('Binary files')) {
        lines.add(_DiffLine(_LineKind.meta, null, line));
      }
      continue;
    }
    if (line.startsWith('+')) {
      lines.add(_DiffLine(_LineKind.add, newNo++, line.substring(1)));
    } else if (line.startsWith('-')) {
      lines.add(_DiffLine(_LineKind.del, oldNo++, line.substring(1)));
    } else if (line.startsWith(' ')) {
      lines.add(_DiffLine(_LineKind.context, newNo, line.substring(1)));
      oldNo++;
      newNo++;
    } else if (line.isNotEmpty) {
      lines.add(_DiffLine(_LineKind.meta, null, line));
    }
  }
  return lines;
}

class _PatchView extends StatefulWidget {
  const _PatchView({super.key, required this.file});

  final DiffFileEntry file;

  @override
  State<_PatchView> createState() => _PatchViewState();
}

class _PatchViewState extends State<_PatchView> {
  static const double _lineHeight = 22;
  static const double _numberWidth = 44;
  static const double _signWidth = 16;

  final ScrollController _vertical = ScrollController();
  final ScrollController _horizontal = ScrollController();
  late List<_DiffLine> _lines;
  late int _maxChars;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(covariant _PatchView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.patch != widget.file.patch) _parse();
  }

  void _parse() {
    _lines = _parsePatch(widget.file.patch);
    _maxChars = _lines.fold(0, (m, l) => math.max(m, l.text.length));
  }

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final codeStyle = b.mono(fontSize: 12, height: _lineHeight / 12);

    if (_lines.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text('No textual changes', style: TextStyle(color: b.muted)),
      );
    }

    final painter = TextPainter(
      text: TextSpan(text: 'M', style: codeStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final charWidth = painter.width;
    painter.dispose();
    final contentWidth =
        _numberWidth + _signWidth + _maxChars * charWidth + 24;

    return Container(
      decoration: BoxDecoration(
        border: Border.fromBorderSide(b.hairline),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = math.max(constraints.maxWidth, contentWidth);
            return Scrollbar(
              controller: _horizontal,
              child: Scrollbar(
                controller: _vertical,
                notificationPredicate: (n) => n.depth == 1,
                child: SingleChildScrollView(
                  controller: _horizontal,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: width,
                    child: SelectionArea(
                      child: ListView.builder(
                        controller: _vertical,
                        itemCount: _lines.length,
                        itemExtent: _lineHeight,
                        itemBuilder: (context, index) =>
                            _buildLine(b, codeStyle, _lines[index]),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLine(BranchiColors b, TextStyle style, _DiffLine line) {
    final (Color bg, Color color, String sign) = switch (line.kind) {
      _LineKind.add => (b.addBg, b.add, '+'),
      _LineKind.del => (b.delBg, b.del, '−'),
      _LineKind.context => (Colors.transparent, b.fg, ''),
      _LineKind.hunk => (b.hover, b.muted, ''),
      _LineKind.meta => (Colors.transparent, b.muted, ''),
    };
    return ColoredBox(
      color: bg,
      child: Row(
        children: [
          SizedBox(
            width: _numberWidth,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: SelectionContainer.disabled(
                child: Text(
                  line.number?.toString() ?? '',
                  textAlign: TextAlign.right,
                  style: style.copyWith(color: b.muted),
                ),
              ),
            ),
          ),
          SizedBox(
            width: _signWidth,
            child: SelectionContainer.disabled(
              child: Text(sign, style: style.copyWith(color: color)),
            ),
          ),
          Expanded(
            child: Text(
              line.text.isEmpty ? ' ' : line.text,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: style.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
