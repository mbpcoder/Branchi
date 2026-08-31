import 'package:flutter/material.dart';

import '../repo/column_resize_handle.dart';
import 'code_editor_panel.dart';
import 'file_tree.dart';

const double _defaultTreeWidth = 240;
const double _minTreeWidth = 160;
const double _maxTreeWidth = 480;

/// The "Code" mode view: a project file tree on the left, a tab-based code
/// editor on the right.
class CodeView extends StatefulWidget {
  const CodeView({super.key, required this.repoPath});

  final String repoPath;

  @override
  State<CodeView> createState() => _CodeViewState();
}

class _CodeViewState extends State<CodeView> {
  final GlobalKey<CodeEditorPanelState> _editorKey = GlobalKey();
  double _treeWidth = _defaultTreeWidth;
  String? _selectedPath;

  void _resizeTree(double delta) {
    setState(() {
      _treeWidth = (_treeWidth + delta).clamp(_minTreeWidth, _maxTreeWidth);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
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
        ),
        ColumnResizeHandle(onDrag: _resizeTree),
        Expanded(
          child: CodeEditorPanel(key: _editorKey),
        ),
      ],
    );
  }
}
