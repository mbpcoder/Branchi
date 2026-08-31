import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// A lazily-expanded directory tree rooted at [rootPath], skipping `.git`.
/// Selecting a file calls [onOpenFile] with its absolute path.
class FileTree extends StatefulWidget {
  const FileTree({
    super.key,
    required this.rootPath,
    required this.onOpenFile,
    this.selectedPath,
    this.width = 240,
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

  @override
  void initState() {
    super.initState();
    _expanded.add(widget.rootPath);
  }

  @override
  void didUpdateWidget(covariant FileTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rootPath != widget.rootPath) {
      _expanded
        ..clear()
        ..add(widget.rootPath);
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
    return SizedBox(
      width: widget.width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: _buildEntries(widget.rootPath, 0),
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

class _FileTreeRow extends StatelessWidget {
  const _FileTreeRow({
    required this.name,
    required this.depth,
    required this.isDirectory,
    required this.isExpanded,
    required this.isSelected,
    required this.onTap,
  });

  final String name;
  final int depth;
  final bool isDirectory;
  final bool isExpanded;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        color: isSelected
            ? theme.colorScheme.primary.withValues(alpha: 0.12)
            : null,
        padding: EdgeInsets.only(left: 8.0 + depth * 14, right: 8, top: 4, bottom: 4),
        child: Row(
          children: [
            Icon(
              isDirectory
                  ? (isExpanded ? Icons.folder_open : Icons.folder)
                  : Icons.insert_drive_file_outlined,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
