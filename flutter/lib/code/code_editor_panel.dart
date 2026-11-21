import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/styles/github-dark.dart';
import 'package:re_highlight/styles/github.dart';

import '../l10n/app_locale.dart';
import '../theme/app_theme.dart';
import 'file_tree.dart' show fileTreeRefreshSignal;

/// One open file in the editor's tab strip.
class _OpenFile {
  _OpenFile(this.path, String initialText)
      : controller = CodeLineEditingController.fromText(initialText) {
    // Compare against the controller's own (re_editor-normalized) text
    // rather than the raw file contents: re_editor may normalize line
    // endings or a missing trailing newline on load, which would otherwise
    // make the file look dirty before the user has typed anything.
    savedText = controller.text;
    controller.addListener(() {
      final nowDirty = controller.text != savedText;
      if (nowDirty != isDirty) {
        isDirty = nowDirty;
        onDirtyChanged?.call();
      }
      // Auto-save once typing pauses; any further edit restarts the wait.
      autoSaveTimer?.cancel();
      autoSaveTimer =
          isDirty ? Timer(autoSaveDelay, () => onAutoSave?.call()) : null;
    });
  }

  /// How long after the last edit a dirty file is saved automatically.
  static const autoSaveDelay = Duration(seconds: 1);

  final String path;
  final CodeLineEditingController controller;
  bool isDirty = false;
  VoidCallback? onDirtyChanged;
  VoidCallback? onAutoSave;
  Timer? autoSaveTimer;
  late String savedText;
}

/// A VS Code-like tabbed text editor backed by `re_editor`, with syntax
/// highlighting from `re_highlight` chosen by file extension.
class CodeEditorPanel extends StatefulWidget {
  const CodeEditorPanel({super.key, this.initialFilePath, this.onLanguageChanged});

  final String? initialFilePath;

  /// Called whenever the detected language of the active tab changes (e.g.
  /// "PHP", "TypeScript"), or with `null` when no file is open, so the app's
  /// bottom bar can show it.
  final ValueChanged<String?>? onLanguageChanged;

  @override
  State<CodeEditorPanel> createState() => CodeEditorPanelState();
}

class CodeEditorPanelState extends State<CodeEditorPanel> {
  final List<_OpenFile> _open = [];
  int _activeIndex = -1;
  String? _error;
  String? _lastNotifiedLanguageLabel;

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
      file.autoSaveTimer?.cancel();
      // Flush edits still waiting on the auto-save delay.
      if (file.isDirty) {
        try {
          File(file.path).writeAsStringSync(file.controller.text);
        } catch (_) {
          // Nowhere left to report the error once the panel is gone.
        }
      }
      file.controller.dispose();
    }
    widget.onLanguageChanged?.call(null);
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
      final file = _OpenFile(path, text);
      file.onDirtyChanged = () => setState(() {});
      file.onAutoSave = () => unawaited(_save(file));
      setState(() {
        _open.add(file);
        _activeIndex = _open.length - 1;
        _error = null;
      });
    } catch (error) {
      setState(() => _error = 'Failed to open ${p.basename(path)}: $error');
    }
  }

  /// Writes [file] to disk. Returns false (and shows the error) on failure.
  Future<bool> _save(_OpenFile file) async {
    file.autoSaveTimer?.cancel();
    // Edits made while the write is in flight must keep the file dirty, so
    // compare against the text actually written rather than the live text.
    final text = file.controller.text;
    try {
      await File(file.path).writeAsString(text);
      if (!mounted || !_open.contains(file)) return true;
      setState(() {
        file.savedText = text;
        file.isDirty = file.controller.text != text;
      });
      fileTreeRefreshSignal.value++;
      return true;
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = 'Failed to save ${p.basename(file.path)}: $error',
        );
      }
      return false;
    }
  }

  Future<void> _closeTab(int index) async {
    final file = _open[index];
    // Auto-save is always on: save pending edits instead of prompting, and
    // keep the tab open if that fails so nothing is lost.
    if (file.isDirty && !await _save(file)) return;
    if (!mounted) return;
    index = _open.indexOf(file);
    if (index == -1) return;

    file.autoSaveTimer?.cancel();
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

  /// The label shown in the bottom bar for the active file's detected type,
  /// e.g. "PHP", "TypeScript". Kept separate from [_languageNameFor] (which
  /// returns the `re_highlight` grammar key) since a few types share a
  /// grammar but should still read with their own name (Blade, .env).
  static const Map<String, String> _fileTypeLabels = {
    'dart': 'Dart',
    'rs': 'Rust',
    'js': 'JavaScript',
    'jsx': 'JSX',
    'mjs': 'JavaScript',
    'cjs': 'JavaScript',
    'ts': 'TypeScript',
    'tsx': 'TSX',
    'json': 'JSON',
    'yaml': 'YAML',
    'yml': 'YAML',
    'md': 'Markdown',
    'markdown': 'Markdown',
    'sh': 'Shell',
    'bash': 'Shell',
    'py': 'Python',
    'xml': 'XML',
    'html': 'HTML',
    'php': 'PHP',
    'css': 'CSS',
    'scss': 'SCSS',
    'cs': 'C#',
    'java': 'Java',
    'ini': 'INI',
    'blade': 'Blade',
    'vue': 'Vue',
    'env': 'Env',
  };

  String? _fileTypeLabelFor(String path) {
    final basename = p.basename(path).toLowerCase();
    if (basename.endsWith('.blade.php')) return 'Blade';
    if (basename == '.env' || basename.startsWith('.env.')) return 'Env';
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    return _fileTypeLabels[ext];
  }

  void _notifyLanguage(String? label) {
    if (label == _lastNotifiedLanguageLabel) return;
    _lastNotifiedLanguageLabel = label;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onLanguageChanged?.call(label);
    });
  }

  /// The active file's path relative to its enclosing git repository (or
  /// just its basename), split into breadcrumb segments.
  static String _breadcrumbFor(String path) {
    var dir = p.dirname(path);
    while (true) {
      try {
        if (Directory(p.join(dir, '.git')).existsSync() ||
            File(p.join(dir, '.git')).existsSync()) {
          return p.split(p.relative(path, from: dir)).join(' / ');
        }
      } catch (_) {
        break;
      }
      final parent = p.dirname(dir);
      if (parent == dir) break;
      dir = parent;
    }
    return p.basename(path);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.branchi;
    if (_open.isEmpty) {
      _notifyLanguage(null);
      return ColoredBox(
        color: c.bg,
        child: Center(
          child: Text(
            translate('editor_select_file'),
            style: TextStyle(color: c.muted),
          ),
        ),
      );
    }

    final active = _open[_activeIndex];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final languageName = _languageNameFor(active.path);
    final mode = languageName == null ? null : builtinAllLanguages[languageName];
    final fileTypeLabel = _fileTypeLabelFor(active.path);
    _notifyLanguage(fileTypeLabel);

    final baseCodeTheme = isDark ? githubDarkTheme : githubTheme;
    final codeTheme = <String, TextStyle>{
      ...baseCodeTheme,
      'root': TextStyle(color: c.fg),
    };
    const codeFontSize = 13.0;
    final gutterStyle = c.mono(fontSize: codeFontSize, color: c.muted);

    return ColoredBox(
      color: c.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 40,
            decoration: BoxDecoration(border: Border(bottom: c.hairline)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _TabStrip(
                    files: _open,
                    activeIndex: _activeIndex,
                    onSelect: (i) => setState(() => _activeIndex = i),
                    onClose: _closeTab,
                  ),
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      _breadcrumbFor(active.path),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                  ),
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: IconButton(
                      icon: const Icon(Icons.save_outlined, size: 16),
                      color: c.muted,
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Save (Ctrl+S)',
                      onPressed: active.isDirty ? () => _save(active) : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: c.delBg,
                border: Border(bottom: c.hairline),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(fontSize: 12, color: c.del),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _error = null),
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
            ),
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
                  // re_editor binds Ctrl/Cmd+S to its own (no-op) save intent
                  // and swallows the key, so the CallbackShortcuts above
                  // never see it while the editor is focused.
                  shortcutOverrideActions: {
                    CodeShortcutSaveIntent:
                        CallbackAction<CodeShortcutSaveIntent>(
                      onInvoke: (_) {
                        unawaited(_save(active));
                        return null;
                      },
                    ),
                  },
                  wordWrap: false,
                  padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                  style: CodeEditorStyle(
                    fontSize: codeFontSize,
                    fontFamily: kMonoFontFamily,
                    fontFamilyFallback: kMonoFontFallback,
                    fontHeight: 22 / codeFontSize,
                    textColor: c.fg,
                    hintTextColor: c.muted,
                    backgroundColor: c.bg,
                    selectionColor: c.accent.withValues(alpha: 0.25),
                    highlightColor: c.mod.withValues(alpha: 0.25),
                    cursorColor: c.accent,
                    cursorLineColor: c.hover,
                    chunkIndicatorColor: c.muted,
                    codeTheme: mode == null
                        ? null
                        : CodeHighlightTheme(
                            languages: {
                              languageName!: CodeHighlightThemeMode(mode: mode),
                            },
                            theme: codeTheme,
                          ),
                  ),
                  indicatorBuilder:
                      (context, editingController, chunkController, notifier) {
                    return Row(
                      children: [
                        SizedBox(
                          width: 52,
                          child: Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: DefaultCodeLineNumber(
                              controller: editingController,
                              notifier: notifier,
                              textStyle: gutterStyle,
                              focusedTextStyle:
                                  gutterStyle.copyWith(color: c.fg),
                            ),
                          ),
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
          _EditorFooter(file: active, languageLabel: fileTypeLabel),
        ],
      ),
    );
  }
}

/// 28px status footer: saved/modified on the left, cursor position,
/// encoding and language on the right.
class _EditorFooter extends StatelessWidget {
  const _EditorFooter({required this.file, required this.languageLabel});

  final _OpenFile file;
  final String? languageLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.branchi;
    final style = TextStyle(fontSize: 12, color: c.muted);
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(border: Border(top: c.hairline)),
      child: ListenableBuilder(
        listenable: file.controller,
        builder: (context, _) {
          final selection = file.controller.selection;
          final position = translate('editor_cursor_position')
              .replaceAll('{line}', '${selection.extentIndex + 1}')
              .replaceAll('{col}', '${selection.extentOffset + 1}');
          final parts = [
            position,
            'UTF-8',
            ?languageLabel,
          ];
          return Row(
            children: [
              Text(
                translate(file.isDirty ? 'editor_modified' : 'editor_saved'),
                style: style,
              ),
              const Spacer(),
              Text(parts.join('  ·  '), style: style),
            ],
          );
        },
      ),
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
    final c = context.branchi;
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        final isActive = index == activeIndex;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelect(index),
            // Middle-click closes the tab, as in browsers.
            onTertiaryTapUp: (_) => onClose(index),
            child: Container(
              padding: const EdgeInsetsDirectional.only(start: 16, end: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isActive ? c.accent : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    p.basename(file.path),
                    style: TextStyle(
                      fontSize: 13,
                      color: isActive ? c.fg : c.muted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 6,
                    height: 6,
                    child: file.isDirty
                        ? DecoratedBox(
                            decoration: BoxDecoration(
                              color: c.mod,
                              shape: BoxShape.circle,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => onClose(index),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(Icons.close, size: 12, color: c.muted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
