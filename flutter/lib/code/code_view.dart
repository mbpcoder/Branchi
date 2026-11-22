import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../repo/column_resize_handle.dart';
import 'code_editor_panel.dart';
import 'content_search_panel.dart';
import 'file_languages.dart';
import 'file_search_dialog.dart';
import 'file_tree.dart';
import 'line_blame.dart';

const double _defaultTreeWidth = 260;
const double _minTreeWidth = 160;
const double _maxTreeWidth = 480;

/// The "Code" mode view: a sidebar on the left (the project file tree, or
/// "search in files"), a tab-based code editor on the right.
///
/// Ctrl/Cmd+P opens "go to file"; Ctrl/Cmd+Shift+F searches file contents;
/// Ctrl/Cmd+Alt+B shows or hides line blame in the editor footer.
class CodeView extends StatefulWidget {
  const CodeView({
    super.key,
    required this.repoPath,
    this.onLanguageChanged,
    this.onOpenCommit,
  });

  final String repoPath;

  /// Opens a commit in the History view (from the editor footer's blame).
  final ValueChanged<BlameHunk>? onOpenCommit;

  /// Forwarded to [CodeEditorPanel] so the app's bottom bar can show the
  /// active file's detected type.
  final ValueChanged<String?>? onLanguageChanged;

  @override
  State<CodeView> createState() => CodeViewState();
}

class CodeViewState extends State<CodeView> {
  final GlobalKey<CodeEditorPanelState> _editorKey = GlobalKey();
  final GlobalKey<ContentSearchPanelState> _searchKey = GlobalKey();
  double _treeWidth = _defaultTreeWidth;
  String? _selectedPath;
  bool _searchOpen = false;

  /// Whether the sidebar shows "search in files" instead of the tree.
  bool _showContentSearch = false;

  /// Takes focus when a click lands where nothing focusable is (or after
  /// focus was lost), so the view's shortcuts still work.
  final FocusNode _viewFocus = FocusNode(debugLabel: 'CodeView');

  @override
  void dispose() {
    _viewFocus.dispose();
    super.dispose();
  }

  void _resizeTree(double delta) {
    setState(() {
      _treeWidth = (_treeWidth + delta).clamp(_minTreeWidth, _maxTreeWidth);
    });
  }

  /// Opens [absolutePath] in the editor, e.g. from an "Open in editor"
  /// action elsewhere in the app. With [line] (1-based), jumps there.
  void openFile(
    String absolutePath, {
    int? line,
    int column = 0,
    int length = 0,
  }) {
    setState(() => _selectedPath = absolutePath);
    unawaited(RecentFiles.record(widget.repoPath, absolutePath));
    _editorKey.currentState?.openFile(
      absolutePath,
      line: line,
      column: column,
      length: length,
    );
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

  /// Shows "search in files" in the sidebar and focuses its query box.
  void openContentSearch() {
    setState(() => _showContentSearch = true);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _searchKey.currentState?.focusQuery(),
    );
  }

  @override
  Widget build(BuildContext context) {
    void search() => unawaited(openFileSearch());
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): search,
        const SingleActivator(LogicalKeyboardKey.keyP, meta: true): search,
        const SingleActivator(
          LogicalKeyboardKey.keyF,
          control: true,
          shift: true,
        ): openContentSearch,
        const SingleActivator(
          LogicalKeyboardKey.keyF,
          meta: true,
          shift: true,
        ): openContentSearch,
        const SingleActivator(
          LogicalKeyboardKey.keyB,
          control: true,
          alt: true,
        ): BlameSettings.toggle,
        const SingleActivator(
          LogicalKeyboardKey.keyB,
          meta: true,
          alt: true,
        ): BlameSettings.toggle,
      },
      child: Focus(
        focusNode: _viewFocus,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) {
            final focused = FocusManager.instance.primaryFocus;
            if (focused == null || focused.context == null ||
                focused is FocusScopeNode) {
              _viewFocus.requestFocus();
            }
          },
          child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Both stay mounted, so switching keeps the tree's expanded
          // folders and the last search's results.
          IndexedStack(
            index: _showContentSearch ? 1 : 0,
            sizing: StackFit.passthrough,
            children: [
              FileTree(
                rootPath: widget.repoPath,
                width: _treeWidth,
                selectedPath: _selectedPath,
                onOpenFile: openFile,
                onSearch: search,
                onSearchContent: openContentSearch,
                onBeforeChange: (path) async =>
                    await _editorKey.currentState?.flushPendingSaves(path) ??
                    true,
                onPathMoved: (from, to) {
                  _editorKey.currentState?.handlePathMoved(from, to);
                  unawaited(FileLanguageOverrides.movePath(from, to));
                  unawaited(RecentFiles.movePath(widget.repoPath, from, to));
                },
                onPathDeleted: (path) {
                  _editorKey.currentState?.handlePathDeleted(path);
                  unawaited(FileLanguageOverrides.removePath(path));
                },
              ),
              ContentSearchPanel(
                key: _searchKey,
                rootPath: widget.repoPath,
                width: _treeWidth,
                onClose: () => setState(() => _showContentSearch = false),
                onOpenMatch: (path, line, column, length) => openFile(
                  path,
                  line: line,
                  column: column,
                  length: length,
                ),
              ),
            ],
          ),
          ColumnResizeHandle(onDrag: _resizeTree),
          Expanded(
            child: CodeEditorPanel(
              key: _editorKey,
              repoRoot: widget.repoPath,
              onLanguageChanged: widget.onLanguageChanged,
              onOpenCommit: widget.onOpenCommit,
            ),
          ),
        ],
      ),
        ),
      ),
    );
  }
}
