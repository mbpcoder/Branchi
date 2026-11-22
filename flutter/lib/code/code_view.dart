import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../repo/column_resize_handle.dart';
import 'code_editor_panel.dart';
import 'file_languages.dart';
import 'file_search_dialog.dart';
import 'file_tree.dart';

const double _defaultTreeWidth = 260;
const double _minTreeWidth = 160;
const double _maxTreeWidth = 480;

/// The "Code" mode view: a project file tree on the left, a tab-based code
/// editor on the right. Ctrl/Cmd+P opens the "go to file" search.
class CodeView extends StatefulWidget {
  const CodeView({super.key, required this.repoPath, this.onLanguageChanged});

  final String repoPath;

  /// Forwarded to [CodeEditorPanel] so the app's bottom bar can show the
  /// active file's detected type.
  final ValueChanged<String?>? onLanguageChanged;

  @override
  State<CodeView> createState() => CodeViewState();
}

class CodeViewState extends State<CodeView> {
  final GlobalKey<CodeEditorPanelState> _editorKey = GlobalKey();
  double _treeWidth = _defaultTreeWidth;
  String? _selectedPath;
  bool _searchOpen = false;

  void _resizeTree(double delta) {
    setState(() {
      _treeWidth = (_treeWidth + delta).clamp(_minTreeWidth, _maxTreeWidth);
    });
  }

  /// Opens [absolutePath] in the editor, e.g. from an "Open in editor"
  /// action elsewhere in the app.
  void openFile(String absolutePath) {
    setState(() => _selectedPath = absolutePath);
    _editorKey.currentState?.openFile(absolutePath);
  }

  /// Shows the "go to file" search and opens the chosen file.
  Future<void> openFileSearch() async {
    if (_searchOpen) return;
    _searchOpen = true;
    try {
      final path = await showFileSearch(context, widget.repoPath);
      if (path != null && mounted) openFile(path);
    } finally {
      _searchOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyP, control: true):
            () => unawaited(openFileSearch()),
        const SingleActivator(LogicalKeyboardKey.keyP, meta: true):
            () => unawaited(openFileSearch()),
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FileTree(
            rootPath: widget.repoPath,
            width: _treeWidth,
            selectedPath: _selectedPath,
            onOpenFile: (path) {
              setState(() => _selectedPath = path);
              _editorKey.currentState?.openFile(path);
            },
            onSearch: () => unawaited(openFileSearch()),
            onBeforeChange: (path) async =>
                await _editorKey.currentState?.flushPendingSaves(path) ?? true,
            onPathMoved: (from, to) {
              _editorKey.currentState?.handlePathMoved(from, to);
              unawaited(FileLanguageOverrides.movePath(from, to));
            },
            onPathDeleted: (path) {
              _editorKey.currentState?.handlePathDeleted(path);
              unawaited(FileLanguageOverrides.removePath(path));
            },
          ),
          ColumnResizeHandle(onDrag: _resizeTree),
          Expanded(
            child: CodeEditorPanel(
              key: _editorKey,
              onLanguageChanged: widget.onLanguageChanged,
            ),
          ),
        ],
      ),
    );
  }
}
