import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'commit_list.dart' show formatCommitDate;
import 'models.dart';

/// Changed-file rows shown before the file list scrolls.
const int _maxVisibleFileRows = 6;
const double _fileRowHeight = 34;

/// Right-hand pane: metadata for the selected commit(s) plus a per-file
/// diff viewer, or a loading/empty/error state. With several commits
/// selected, [diffFiles] is their net change.
class CommitDetail extends StatelessWidget {
  const CommitDetail({
    super.key,
    required this.commits,
    required this.diffFiles,
    required this.isLoading,
    required this.error,
    required this.selectedFilePath,
    required this.filesAsTree,
    required this.onSelectFile,
    required this.onOpenFile,
    required this.onFilesAsTreeChanged,
  });

  /// The selected commits, newest first.
  final List<CommitEntry> commits;
  final List<DiffFileEntry> diffFiles;
  final bool isLoading;
  final String? error;

  /// The file whose patch is shown; null for the first listed file.
  final String? selectedFilePath;

  /// Whether changed files are grouped by directory, or listed flat.
  final bool filesAsTree;
  final ValueChanged<String> onSelectFile;
  final ValueChanged<String> onOpenFile;
  final ValueChanged<bool> onFilesAsTreeChanged;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    if (commits.isEmpty) {
      return Center(
        child: Text(
          'Select a commit to see its changes',
          style: TextStyle(color: b.muted),
        ),
      );
    }

    final listed = filesAsTree ? _treeOrder(diffFiles) : diffFiles;
    final selectedFile = listed.isEmpty
        ? null
        : listed.firstWhere(
            (f) => f.path == selectedFilePath,
            orElse: () => listed.first,
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
            files: listed,
            asTree: filesAsTree,
            selected: selectedFile,
            onSelect: onSelectFile,
            onOpen: onOpenFile,
            onAsTreeChanged: onFilesAsTreeChanged,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
              child: _PatchView(
                key: ValueKey(
                  '${commits.first.id}..${commits.last.id}:'
                  '${selectedFile.path}',
                ),
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
        if (commits.length == 1)
          _CommitHeader(commit: commits.single)
        else
          _RangeHeader(commits: commits),
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
              _CopyableHash(commit: commit),
            ],
          ),
        ],
      ),
    );
  }
}

/// Header for several selected commits: how many, who wrote them, and
/// the span they cover.
class _RangeHeader extends StatelessWidget {
  const _RangeHeader({required this.commits});

  /// Newest first.
  final List<CommitEntry> commits;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final meta = TextStyle(fontSize: 12, color: b.muted);
    final newest = commits.first;
    final oldest = commits.last;
    final authors = <String>{for (final c in commits) c.author}.toList();
    final authorsLabel = authors.length <= 3
        ? authors.join(', ')
        : '${authors.take(3).join(', ')} +${authors.length - 3}';
    return Container(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 20),
      decoration: BoxDecoration(border: Border(bottom: b.hairline)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${commits.length} commits selected',
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
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(authorsLabel, style: meta),
              Text(
                '${formatCommitDate(oldest.time)} – '
                '${formatCommitDate(newest.time)}',
                style: meta,
              ),
              Tooltip(
                message:
                    'Net change from the parent of the oldest selected '
                    'commit to the newest one',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CopyableHash(commit: oldest),
                    Text(' … ', style: meta),
                    _CopyableHash(commit: newest),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A commit's short hash; clicking copies the full hash.
class _CopyableHash extends StatelessWidget {
  const _CopyableHash({required this.commit});

  final CommitEntry commit;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return Tooltip(
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
    );
  }
}

/// A directory in the changed-files tree.
class _DirNode {
  _DirNode(this.name, this.path);

  /// Shown label; chains of single-child directories are joined into one
  /// node, e.g. `app/Http/Controllers`.
  String name;

  /// Full path from the repo root, used to remember collapsed folders.
  String path;
  final Map<String, _DirNode> dirs = {};
  final List<DiffFileEntry> files = [];

  int get fileCount =>
      files.length + dirs.values.fold(0, (sum, d) => sum + d.fileCount);

  List<_DirNode> get sortedDirs =>
      dirs.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  List<DiffFileEntry> get sortedFiles => files.toList()
    ..sort(
      (a, b) => _baseName(
        a.path,
      ).toLowerCase().compareTo(_baseName(b.path).toLowerCase()),
    );
}

String _baseName(String path) => path.substring(path.lastIndexOf('/') + 1);

_DirNode _buildTree(List<DiffFileEntry> files) {
  final root = _DirNode('', '');
  for (final file in files) {
    final parts = file.path.split('/');
    var node = root;
    for (var i = 0; i < parts.length - 1; i++) {
      final path = parts.sublist(0, i + 1).join('/');
      node = node.dirs.putIfAbsent(parts[i], () => _DirNode(parts[i], path));
    }
    node.files.add(file);
  }
  void compact(_DirNode node) {
    for (final child in node.dirs.values) {
      while (child.files.isEmpty && child.dirs.length == 1) {
        final only = child.dirs.values.single;
        child
          ..name = '${child.name}/${only.name}'
          ..path = only.path;
        child.dirs
          ..clear()
          ..addAll(only.dirs);
        child.files.addAll(only.files);
      }
      compact(child);
    }
  }

  compact(root);
  return root;
}

/// [files] in the order the tree lists them: folders first, then files,
/// each alphabetically.
List<DiffFileEntry> _treeOrder(List<DiffFileEntry> files) {
  final ordered = <DiffFileEntry>[];
  void walk(_DirNode node) {
    node.sortedDirs.forEach(walk);
    ordered.addAll(node.sortedFiles);
  }

  walk(_buildTree(files));
  return ordered;
}

/// The changed files, as a flat list of paths or grouped by directory.
/// The selected one is shown in full colour; the others are muted.
class _FileList extends StatefulWidget {
  const _FileList({
    required this.files,
    required this.asTree,
    required this.selected,
    required this.onSelect,
    required this.onOpen,
    required this.onAsTreeChanged,
  });

  final List<DiffFileEntry> files;
  final bool asTree;
  final DiffFileEntry selected;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onOpen;
  final ValueChanged<bool> onAsTreeChanged;

  @override
  State<_FileList> createState() => _FileListState();
}

class _FileListState extends State<_FileList> {
  /// Paths of the folders the user collapsed.
  final Set<String> _collapsed = {};

  Widget _fileRow(DiffFileEntry file, {String? label, int depth = 0}) {
    return _FileRow(
      file: file,
      label: label ?? file.path,
      indent: widget.asTree ? depth * 16.0 : null,
      selected: file.path == widget.selected.path,
      dimUnselected: widget.files.length > 1,
      onTap: () => widget.onSelect(file.path),
      onOpen: () => widget.onOpen(file.path),
    );
  }

  List<Widget> _treeRows(_DirNode node, int depth) {
    return [
      for (final dir in node.sortedDirs) ...[
        _DirRow(
          name: dir.name,
          fileCount: dir.fileCount,
          indent: depth * 16.0,
          expanded: !_collapsed.contains(dir.path),
          onTap: () => setState(() {
            if (!_collapsed.remove(dir.path)) _collapsed.add(dir.path);
          }),
        ),
        if (!_collapsed.contains(dir.path)) ..._treeRows(dir, depth + 1),
      ],
      for (final file in node.sortedFiles)
        _fileRow(file, label: _baseName(file.path), depth: depth),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final files = widget.files;
    final rows = widget.asTree
        ? _treeRows(_buildTree(files), 0)
        : [for (final file in files) _fileRow(file)];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Row(
              children: [
                Text(
                  files.length == 1
                      ? '1 file changed'
                      : '${files.length} files changed',
                  style: TextStyle(fontSize: 12, color: b.muted),
                ),
                const Spacer(),
                IconButton(
                  tooltip: widget.asTree
                      ? 'Show as flat list'
                      : 'Group by directory',
                  isSelected: widget.asTree,
                  icon: Icon(
                    Icons.account_tree_outlined,
                    size: 16,
                    color: widget.asTree ? b.accent : b.muted,
                  ),
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () => widget.onAsTreeChanged(!widget.asTree),
                ),
              ],
            ),
          ),
          if (rows.length <= _maxVisibleFileRows)
            Column(children: rows)
          else
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: _maxVisibleFileRows * _fileRowHeight,
              ),
              child: ListView(shrinkWrap: true, children: rows),
            ),
        ],
      ),
    );
  }
}

/// A folder row in the tree: click to collapse or expand it.
class _DirRow extends StatelessWidget {
  const _DirRow({
    required this.name,
    required this.fileCount,
    required this.indent,
    required this.expanded,
    required this.onTap,
  });

  final String name;
  final int fileCount;
  final double indent;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        hoverColor: b.hover,
        splashFactory: NoSplash.splashFactory,
        child: SizedBox(
          height: _fileRowHeight,
          child: Padding(
            padding: EdgeInsets.only(left: 12 + indent, right: 12),
            child: Row(
              children: [
                Icon(
                  expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 16,
                  color: b.muted,
                ),
                const SizedBox(width: 4),
                Icon(Icons.folder_outlined, size: 14, color: b.muted),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: b.mono(fontSize: 12, color: b.fg),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  fileCount == 1 ? '1 file' : '$fileCount files',
                  style: TextStyle(fontSize: 12, color: b.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FileRow extends StatefulWidget {
  const _FileRow({
    required this.file,
    required this.label,
    required this.indent,
    required this.selected,
    required this.dimUnselected,
    required this.onTap,
    required this.onOpen,
  });

  final DiffFileEntry file;

  /// The full path, or in the tree just the file name.
  final String label;

  /// Indent in the tree; null in the flat list.
  final double? indent;
  final bool selected;
  final bool dimUnselected;
  final VoidCallback onTap;
  final VoidCallback onOpen;

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final file = widget.file;
    final pathColor = widget.selected || !widget.dimUnselected ? b.fg : b.muted;
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
            height: _fileRowHeight,
            child: Padding(
              // In the tree, a file lines up with the folder icons at its
              // depth, past the folders' chevrons.
              padding: EdgeInsets.only(
                left: 12 + (widget.indent == null ? 0 : widget.indent! + 20),
                right: 12,
              ),
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
                    child: Tooltip(
                      message: widget.label == file.path ? '' : file.path,
                      waitDuration: const Duration(milliseconds: 600),
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: b.mono(fontSize: 12, color: pathColor),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '+${file.additions}',
                    style: TextStyle(fontSize: 12, color: b.add),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '−${file.deletions}',
                    style: TextStyle(fontSize: 12, color: b.del),
                  ),
                  const SizedBox(width: 8),
                  Opacity(
                    opacity: _hovered ? 1 : 0,
                    child: IconButton(
                      tooltip: 'Open in editor',
                      icon: Icon(Icons.open_in_new, size: 14, color: b.muted),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 24,
                      ),
                      onPressed: widget.onOpen,
                    ),
                  ),
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
  // The Rust core emits bare +/-/space lines without `@@` hunk headers;
  // in that case every line is content and line numbers are unknown.
  final hasHunks = raw.any(hunkHeader.hasMatch);
  var inHunk = !hasHunks;
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
      lines.add(
        _DiffLine(_LineKind.add, hasHunks ? newNo++ : null, line.substring(1)),
      );
    } else if (line.startsWith('-')) {
      lines.add(
        _DiffLine(_LineKind.del, hasHunks ? oldNo++ : null, line.substring(1)),
      );
    } else if (line.startsWith(' ')) {
      lines.add(
        _DiffLine(
          _LineKind.context,
          hasHunks ? newNo : null,
          line.substring(1),
        ),
      );
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
    final contentWidth = _numberWidth + _signWidth + _maxChars * charWidth + 24;

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
