import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_locale.dart';
import '../repo/git_actions.dart';
import '../repo/models.dart';
import '../theme/app_theme.dart';

/// Bumped whenever a file is written from the editor, so any visible
/// [FileTree] re-reads git status (and its M/A markers stay current).
final ValueNotifier<int> fileTreeRefreshSignal = ValueNotifier<int>(0);

/// A lazily-expanded directory tree rooted at [rootPath], skipping `.git`.
/// Selecting a file calls [onOpenFile] with its absolute path.
class FileTree extends StatefulWidget {
  const FileTree({
    super.key,
    required this.rootPath,
    required this.onOpenFile,
    this.selectedPath,
    this.width = 260,
  });

  final String rootPath;
  final ValueChanged<String> onOpenFile;
  final String? selectedPath;
  final double width;

  @override
  State<FileTree> createState() => _FileTreeState();
}

class _FileTreeState extends State<FileTree> {
  final Set<String> _expanded = {};

  /// Absolute path -> single-letter git status ("M", "A", "D", ...).
  Map<String, String> _status = const {};
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _expanded.add(widget.rootPath);
    fileTreeRefreshSignal.addListener(_loadStatus);
    _loadStatus();
    _statusTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _loadStatus());
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    fileTreeRefreshSignal.removeListener(_loadStatus);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FileTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rootPath != widget.rootPath) {
      _expanded
        ..clear()
        ..add(widget.rootPath);
      _status = const {};
      _loadStatus();
    }
  }

  Future<void> _loadStatus() async {
    final root = widget.rootPath;
    try {
      final entries = await GitActions.status(root);
      if (!mounted || root != widget.rootPath) return;
      final next = <String, String>{};
      for (final entry in entries) {
        final letter = _letterFor(entry.unstaged ?? entry.staged);
        if (letter == null) continue;
        next[p.normalize(p.join(root, entry.path))] = letter;
      }
      setState(() => _status = next);
    } catch (_) {
      // No git library / not a repo: just show the tree without markers.
    }
  }

  static String? _letterFor(FileChangeStatus? status) {
    switch (status) {
      case FileChangeStatus.new_:
        return 'A';
      case FileChangeStatus.modified:
      case FileChangeStatus.typechange:
        return 'M';
      case FileChangeStatus.deleted:
        return 'D';
      case FileChangeStatus.renamed:
        return 'R';
      case FileChangeStatus.conflicted:
        return 'U';
      case null:
        return null;
    }
  }

  List<FileSystemEntity> _listDir(String dir) {
    try {
      final entries = Directory(dir).listSync()
        ..removeWhere((e) => p.basename(e.path) == '.git');
      entries.sort((a, b) {
        final aDir = a is Directory;
        final bDir = b is Directory;
        if (aDir != bDir) return aDir ? -1 : 1;
        return p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase());
      });
      return entries;
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.branchi;
    return SizedBox(
      width: widget.width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.bg,
          border: Border(right: c.hairline),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 10),
              child: Text(
                translate('editor_explorer'),
                style: TextStyle(
                  fontSize: 11,
                  color: c.muted,
                  letterSpacing: 0.44,
                ),
              ),
            ),
            ..._buildEntries(widget.rootPath, 0),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildEntries(String dir, int depth) {
    final widgets = <Widget>[];
    for (final entity in _listDir(dir)) {
      final isDir = entity is Directory;
      final isExpanded = _expanded.contains(entity.path);
      final isSelected = entity.path == widget.selectedPath;
      widgets.add(_FileTreeRow(
        name: p.basename(entity.path),
        depth: depth,
        isDirectory: isDir,
        isExpanded: isExpanded,
        isSelected: isSelected,
        statusLetter: isDir ? null : _status[p.normalize(entity.path)],
        onTap: () {
          if (isDir) {
            setState(() {
              if (isExpanded) {
                _expanded.remove(entity.path);
              } else {
                _expanded.add(entity.path);
              }
            });
          } else {
            widget.onOpenFile(entity.path);
          }
        },
      ));
      if (isDir && isExpanded) {
        widgets.addAll(_buildEntries(entity.path, depth + 1));
      }
    }
    return widgets;
  }
}

class _FileTreeRow extends StatefulWidget {
  const _FileTreeRow({
    required this.name,
    required this.depth,
    required this.isDirectory,
    required this.isExpanded,
    required this.isSelected,
    required this.statusLetter,
    required this.onTap,
  });

  final String name;
  final int depth;
  final bool isDirectory;
  final bool isExpanded;
  final bool isSelected;
  final String? statusLetter;
  final VoidCallback onTap;

  @override
  State<_FileTreeRow> createState() => _FileTreeRowState();
}

class _FileTreeRowState extends State<_FileTreeRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final c = context.branchi;
    final letter = widget.statusLetter;
    final Color markColor = switch (letter) {
      'A' => c.add,
      'D' => c.del,
      'U' => c.del,
      _ => c.mod,
    };
    final highlighted = widget.isSelected || _hovering;
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            decoration: BoxDecoration(
              color: highlighted ? c.hover : null,
              borderRadius: BorderRadius.circular(6),
            ),
            padding: EdgeInsetsDirectional.only(
              start: 12.0 + widget.depth * 14,
              end: 12,
              top: 5,
              bottom: 5,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 10,
                  child: widget.isDirectory
                      ? Text(
                          widget.isExpanded ? '▾' : '▸',
                          style: TextStyle(fontSize: 10, color: c.muted),
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.name,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 13,
                      color: widget.isDirectory || widget.isSelected
                          ? c.fg
                          : c.muted,
                    ),
                  ),
                ),
                if (letter != null) ...[
                  const SizedBox(width: 8),
                  Text(letter, style: c.mono(fontSize: 10, color: markColor)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
