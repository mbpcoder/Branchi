import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/styles/github-dark.dart';
import 'package:re_highlight/styles/github.dart';

/// One open file in the editor's tab strip.
class _OpenFile {
  _OpenFile(this.path, String initialText)
      : controller = CodeLineEditingController.fromText(initialText) {
    controller.addListener(() {
      final nowDirty = controller.text != initialText;
      if (nowDirty != isDirty) {
        isDirty = nowDirty;
        onDirtyChanged?.call();
      }
    });
  }

  final String path;
  final CodeLineEditingController controller;
  bool isDirty = false;
  VoidCallback? onDirtyChanged;
  String savedText = '';
}

/// A VS Code-like tabbed text editor backed by `re_editor`, with syntax
/// highlighting from `re_highlight` chosen by file extension.
class CodeEditorPanel extends StatefulWidget {
  const CodeEditorPanel({super.key, this.initialFilePath});

  final String? initialFilePath;

  @override
  State<CodeEditorPanel> createState() => CodeEditorPanelState();
}

class CodeEditorPanelState extends State<CodeEditorPanel> {
  final List<_OpenFile> _open = [];
  int _activeIndex = -1;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialFilePath != null) {
      unawaited(openFile(widget.initialFilePath!));
    }
  }

  @override
  void dispose() {
    for (final file in _open) {
      file.controller.dispose();
    }
    super.dispose();
  }

  Future<void> openFile(String path) async {
    final existingIndex = _open.indexWhere((f) => f.path == path);
    if (existingIndex != -1) {
      setState(() => _activeIndex = existingIndex);
      return;
    }

    try {
      final text = await File(path).readAsString();
      final file = _OpenFile(path, text)..savedText = text;
      file.onDirtyChanged = () => setState(() {});
      setState(() {
        _open.add(file);
        _activeIndex = _open.length - 1;
        _error = null;
      });
    } catch (error) {
      setState(() => _error = 'Failed to open ${p.basename(path)}: $error');
    }
  }

  Future<void> _save(_OpenFile file) async {
    try {
      await File(file.path).writeAsString(file.controller.text);
      setState(() {
        file.savedText = file.controller.text;
        file.isDirty = false;
      });
    } catch (error) {
      setState(() => _error = 'Failed to save ${p.basename(file.path)}: $error');
    }
  }

  Future<void> _closeTab(int index) async {
    final file = _open[index];
    if (file.isDirty) {
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Unsaved changes'),
          content: Text('"${p.basename(file.path)}" has unsaved changes.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('cancel'),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('discard'),
              child: const Text('Discard'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop('save'),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (action == 'cancel' || action == null) return;
      if (action == 'save') await _save(file);
    }

    file.controller.dispose();
    setState(() {
      _open.removeAt(index);
      if (_open.isEmpty) {
        _activeIndex = -1;
      } else if (_activeIndex >= _open.length) {
        _activeIndex = _open.length - 1;
      } else if (index < _activeIndex) {
        _activeIndex -= 1;
      }
    });
  }

  String? _languageNameFor(String path) {
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    const extToLanguage = {
      'dart': 'dart',
      'rs': 'rust',
      'js': 'javascript',
      'jsx': 'javascript',
      'mjs': 'javascript',
      'cjs': 'javascript',
      'ts': 'typescript',
      'tsx': 'typescript',
      'json': 'json',
      'yaml': 'yaml',
      'yml': 'yaml',
      'md': 'markdown',
      'markdown': 'markdown',
      'sh': 'bash',
      'bash': 'bash',
      'py': 'python',
      'xml': 'xml',
      'html': 'xml',
      'php': 'php',
      'css': 'css',
      'scss': 'scss',
      'cs': 'csharp',
      'java': 'java',
      'ini': 'ini',
      'blade': 'php',
      'vue': 'vue',
      'env': 'properties',
    };
    final basename = p.basename(path).toLowerCase();
    if (basename.endsWith('.blade.php')) return 'php';
    if (basename == '.env' || basename.startsWith('.env.')) return 'properties';
    return extToLanguage[ext];
  }

  @override
  Widget build(BuildContext context) {
    if (_open.isEmpty) {
      return const Center(
        child: Text('Select a file from the project tree to start editing.'),
      );
    }

    final active = _open[_activeIndex];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final languageName = _languageNameFor(active.path);
    final mode = languageName == null ? null : builtinAllLanguages[languageName];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TabStrip(
          files: _open,
          activeIndex: _activeIndex,
          onSelect: (i) => setState(() => _activeIndex = i),
          onClose: _closeTab,
        ),
        if (_error != null)
          MaterialBanner(
            content: Text(_error!),
            actions: [
              TextButton(
                onPressed: () => setState(() => _error = null),
                child: const Text('Dismiss'),
              ),
            ],
          ),
        const Divider(height: 1),
        Expanded(
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.keyS, control: true):
                  () => _save(active),
              const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
                  () => _save(active),
            },
            child: Focus(
              autofocus: true,
              child: CodeEditor(
                key: ValueKey(active.path),
                controller: active.controller,
                wordWrap: false,
                style: CodeEditorStyle(
                  codeTheme: mode == null
                      ? null
                      : CodeHighlightTheme(
                          languages: {
                            languageName!: CodeHighlightThemeMode(mode: mode),
                          },
                          theme: isDark ? githubDarkTheme : githubTheme,
                        ),
                ),
                indicatorBuilder: (context, editingController, chunkController, notifier) {
                  return Row(
                    children: [
                      DefaultCodeLineNumber(
                        controller: editingController,
                        notifier: notifier,
                      ),
                      DefaultCodeChunkIndicator(
                        width: 20,
                        controller: chunkController,
                        notifier: notifier,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.files,
    required this.activeIndex,
    required this.onSelect,
    required this.onClose,
  });

  final List<_OpenFile> files;
  final int activeIndex;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: files.length,
        itemBuilder: (context, index) {
          final file = files[index];
          final isActive = index == activeIndex;
          return InkWell(
            onTap: () => onSelect(index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: isActive
                    ? theme.colorScheme.surfaceContainerHighest
                    : null,
                border: Border(
                  right: BorderSide(color: theme.dividerColor),
                  bottom: BorderSide(
                    color: isActive
                        ? theme.colorScheme.primary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(p.basename(file.path), style: theme.textTheme.bodySmall),
                  if (file.isDirty) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.circle, size: 8),
                  ],
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => onClose(index),
                    child: const Icon(Icons.close, size: 14),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
