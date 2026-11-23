import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/styles/github-dark.dart';
import 'package:re_highlight/styles/github.dart';

import '../l10n/app_locale.dart';
import '../repo/commit_list.dart' show formatRelativeTime;
import '../theme/app_theme.dart';
import '../repo/git_actions.dart';
import 'conflict_markers.dart';
import 'file_languages.dart';
import 'file_ops.dart';
import 'file_preview.dart';
import 'file_tree.dart' show fileTreeRefreshSignal;
import 'language_picker.dart';
import 'line_blame.dart';

/// One open file in the editor's tab strip.
class _OpenFile {
  _OpenFile(this.path, String initialText, {this.kind = OpenFileKind.text})
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

  /// Mutable so the tab follows the file when it's renamed or moved.
  String path;

  /// Text files use [controller]; previews (image, SVG, binary) leave it
  /// empty and are never dirty.
  OpenFileKind kind;
  final CodeLineEditingController controller;
  bool isDirty = false;
  VoidCallback? onDirtyChanged;
  VoidCallback? onAutoSave;
  Timer? autoSaveTimer;
  late String savedText;

  /// Last known modification time of the file on disk, to notice changes
  /// made outside the editor (a branch switch, a pull, another app).
  DateTime? diskModified;

  /// Whether the file on disk changed under unsaved edits, or was deleted.
  /// Auto-save is paused until the user decides.
  _DiskConflict? conflict;

  /// Bumped when a preview's file changes on disk, to redraw it.
  int previewVersion = 0;

  /// Who last changed each line, for the footer; created on demand.
  BlameRunner? blame;

  void dispose() {
    autoSaveTimer?.cancel();
    blame?.dispose();
    blame = null;
    controller.dispose();
  }

  /// Replaces the text with [text] from disk, keeping the cursor where it
  /// was as far as the new text allows, without marking the file dirty.
  void loadFromDisk(String text) {
    final previous = controller.selection;
    savedText = text;
    controller.text = text;
    savedText = controller.text;
    autoSaveTimer?.cancel();
    autoSaveTimer = null;
    isDirty = false;
    final lines = controller.text.split('\n');
    final index = previous.extentIndex.clamp(0, lines.length - 1);
    controller.selection = CodeLineSelection.collapsed(
      index: index,
      offset: previous.extentOffset.clamp(0, lines[index].length),
    );
  }
}

enum _DiskConflict { changed, deleted }

Future<DateTime?> _modifiedOnDisk(String path) async {
  try {
    final stat = await FileStat.stat(path);
    return stat.type == FileSystemEntityType.notFound ? null : stat.modified;
  } catch (_) {
    return null;
  }
}

/// A VS Code-like tabbed text editor backed by `re_editor`, with syntax
/// highlighting from `re_highlight` chosen by file name or extension (or
/// picked by hand from the footer), plus previews for images and SVGs.
class CodeEditorPanel extends StatefulWidget {
  const CodeEditorPanel({
    super.key,
    this.initialFilePath,
    this.onLanguageChanged,
    this.repoRoot,
    this.rebasing = false,
    this.onOpenCommit,
  });

  final String? initialFilePath;

  /// The repository the files belong to, for blame in the footer.
  final String? repoRoot;

  /// During a rebase the lower conflict block is the user's own commit.
  final bool rebasing;

  /// Opens a commit (from the footer's blame) in the History view.
  final ValueChanged<BlameHunk>? onOpenCommit;

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

  /// Focus for the active text editor, so it can be refocused after e.g.
  /// a banner button takes focus away.
  final FocusNode _editorFocus = FocusNode(debugLabel: 'CodeEditor');

  /// Checks open files for changes made outside the editor.
  Timer? _diskTimer;
  bool _checkingDisk = false;

  @override
  void initState() {
    super.initState();
    _diskTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(checkDisk()),
    );
    FileLanguageOverrides.overrides.addListener(_onOverridesChanged);
    unawaited(FileLanguageOverrides.ensureLoaded());
    BlameSettings.enabled.addListener(_onBlameSettingChanged);
    unawaited(BlameSettings.ensureLoaded());
    if (widget.initialFilePath != null) {
      unawaited(openFile(widget.initialFilePath!));
    }
  }

  void _onOverridesChanged() {
    if (mounted) setState(() {});
  }

  void _onBlameSettingChanged() {
    if (!mounted) return;
    if (!BlameSettings.enabled.value) {
      for (final file in _open) {
        file.blame?.dispose();
        file.blame = null;
      }
    } else if (_activeIndex >= 0 && _activeIndex < _open.length) {
      _refreshBlame(_open[_activeIndex]);
    }
    setState(() {});
  }

  /// Shows or hides who last changed the current line (Ctrl/Cmd+Alt+B).
  void toggleBlame() => unawaited(BlameSettings.toggle());

  /// (Re)computes blame for [file]'s current text in the background, if
  /// blame is on and the file is in the repository.
  void _refreshBlame(_OpenFile file) {
    final root = widget.repoRoot;
    if (!BlameSettings.enabled.value ||
        root == null ||
        file.kind != OpenFileKind.text) {
      return;
    }
    final rel = repoRelativePath(root, file.path);
    if (rel == null) return;
    if (file.blame != null && file.blame!.relPath != rel) {
      file.blame!.dispose();
      file.blame = null;
    }
    final runner = file.blame ??= BlameRunner(repoRoot: root, relPath: rel);
    runner.request(file.controller.text);
  }

  @override
  void dispose() {
    FileLanguageOverrides.overrides.removeListener(_onOverridesChanged);
    BlameSettings.enabled.removeListener(_onBlameSettingChanged);
    _diskTimer?.cancel();
    _editorFocus.dispose();
    for (final file in _open) {
      file.autoSaveTimer?.cancel();
      // Flush edits still waiting on the auto-save delay.
      if (file.isDirty &&
          file.kind == OpenFileKind.text &&
          file.conflict == null) {
        try {
          File(file.path).writeAsStringSync(file.controller.text);
        } catch (_) {
          // Nowhere left to report the error once the panel is gone.
        }
      }
      file.dispose();
    }
    widget.onLanguageChanged?.call(null);
    super.dispose();
  }

  /// Opens [path] in a tab (or switches to it). With [line] (1-based),
  /// moves the cursor there and selects [length] characters from [column].
  Future<void> openFile(
    String path, {
    int? line,
    int column = 0,
    int length = 0,
  }) async {
    final existingIndex = _open.indexWhere((f) => f.path == path);
    if (existingIndex != -1) {
      setState(() => _activeIndex = existingIndex);
      _refreshBlame(_open[existingIndex]);
      if (line != null) _revealPosition(_open[existingIndex], line, column, length);
      return;
    }

    try {
      final kind = await detectOpenFileKind(path);
      final text =
          kind == OpenFileKind.text ? await File(path).readAsString() : '';
      if (!mounted) return;
      // Opened meanwhile (e.g. a double click): just switch to it.
      final openedIndex = _open.indexWhere((f) => f.path == path);
      if (openedIndex != -1) {
        setState(() => _activeIndex = openedIndex);
        return;
      }
      final file = _OpenFile(path, text, kind: kind)
        ..diskModified = await _modifiedOnDisk(path);
      if (!mounted) return;
      file.onDirtyChanged = () => setState(() {});
      file.onAutoSave = () => unawaited(_autoSave(file));
      setState(() {
        _open.add(file);
        _activeIndex = _open.length - 1;
        _error = null;
        if (text.contains('\n=======') && text.contains('<<<<<<<')) {
          _hadConflicts.add(path);
        }
      });
      _refreshBlame(file);
      if (line != null) _revealPosition(file, line, column, length);
    } on FileSystemException catch (error) {
      if (!mounted) return;
      // Not valid UTF-8 text: show it as a binary file instead of failing.
      if (error.message.contains('decode')) {
        final file = _OpenFile(path, '', kind: OpenFileKind.binary);
        setState(() {
          _open.add(file);
          _activeIndex = _open.length - 1;
          _error = null;
        });
        return;
      }
      setState(() => _error = 'Failed to open ${p.basename(path)}: $error');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Failed to open ${p.basename(path)}: $error');
    }
  }

  /// Reloads tabs whose file changed on disk. A tab with unsaved edits
  /// isn't reloaded; it shows a choice instead (see [_DiskConflict]).
  Future<void> checkDisk() async {
    if (_checkingDisk || !mounted) return;
    _checkingDisk = true;
    try {
      for (final file in List.of(_open)) {
        final path = file.path;
        final modified = await _modifiedOnDisk(path);
        // Skip results for a tab that closed or was renamed meanwhile.
        if (!mounted || !_open.contains(file) || file.path != path) continue;
        if (modified == null) {
          if (file.conflict != _DiskConflict.deleted) {
            file.autoSaveTimer?.cancel();
            setState(() => file.conflict = _DiskConflict.deleted);
          }
          continue;
        }
        if (modified == file.diskModified &&
            file.conflict != _DiskConflict.deleted) {
          continue;
        }
        if (file.kind != OpenFileKind.text) {
          setState(() {
            file.diskModified = modified;
            file.conflict = null;
            file.previewVersion++;
          });
          continue;
        }
        final String text;
        try {
          text = await File(file.path).readAsString();
        } catch (_) {
          continue; // Mid-write or no longer text; try again next time.
        }
        if (!mounted || !_open.contains(file) || file.path != path) continue;
        file.diskModified = modified;
        if (text == file.savedText ||
            (file.isDirty && text == file.controller.text)) {
          // Only the timestamp changed, or disk already matches the edits.
          if (file.conflict != null) setState(() => file.conflict = null);
          continue;
        }
        if (file.isDirty) {
          file.autoSaveTimer?.cancel();
          setState(() => file.conflict = _DiskConflict.changed);
        } else {
          setState(() {
            file.loadFromDisk(text);
        _refreshBlame(file);
            file.conflict = null;
          });
        }
      }
      // Pick up commits / checkouts made elsewhere for the shown file.
      if (mounted && _activeIndex >= 0 && _activeIndex < _open.length) {
        final active = _open[_activeIndex];
        active.blame?.checkHead(active.controller.text);
      }
    } finally {
      _checkingDisk = false;
    }
  }

  /// Saves [file] after a typing pause, unless the file changed on disk
  /// since it was loaded: then it asks instead of overwriting.
  Future<void> _autoSave(_OpenFile file) async {
    if (file.conflict != null) return;
    final modified = await _modifiedOnDisk(file.path);
    if (!mounted || !_open.contains(file) || file.conflict != null) return;
    if (modified == null) {
      setState(() => file.conflict = _DiskConflict.deleted);
      return;
    }
    if (file.diskModified != null && modified != file.diskModified) {
      // Let the disk check decide: reload silently if it only touched the
      // timestamp, otherwise show the conflict.
      await checkDisk();
      if (!mounted || !_open.contains(file) || file.conflict != null) return;
      if (file.diskModified != modified) {
        // A check already in flight skipped this file; try again shortly.
        file.autoSaveTimer?.cancel();
        file.autoSaveTimer =
            Timer(_OpenFile.autoSaveDelay, () => unawaited(_autoSave(file)));
        return;
      }
    }
    await _save(file);
  }

  /// Drops the unsaved edits in [file] and loads the version on disk.
  Future<void> _reloadFromDisk(_OpenFile file) async {
    try {
      final text = await File(file.path).readAsString();
      final modified = await _modifiedOnDisk(file.path);
      if (!mounted || !_open.contains(file)) return;
      setState(() {
        file.loadFromDisk(text);
        _refreshBlame(file);
        file.diskModified = modified;
        file.conflict = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Failed to reload ${p.basename(file.path)}: $error');
    }
  }

  /// Keeps the edits in [file] and writes them over the version on disk
  /// (or recreates a deleted file).
  Future<void> _keepMine(_OpenFile file) async {
    file.conflict = null;
    await _save(file);
  }

  /// Selects [length] characters at [line] (1-based) / [column] in [file]
  /// and scrolls them into view, once the editor for it is laid out.
  void _revealPosition(_OpenFile file, int line, int column, int length) {
    if (file.kind != OpenFileKind.text) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_open.contains(file)) return;
      final lines = file.controller.text.split('\n');
      final index = (line - 1).clamp(0, lines.length - 1);
      final start = column.clamp(0, lines[index].length);
      final end = (column + length).clamp(start, lines[index].length);
      file.controller.selection = CodeLineSelection(
        baseIndex: index,
        baseOffset: start,
        extentIndex: index,
        extentOffset: end,
      );
      file.controller.makeCursorCenterIfInvisible();
    });
  }

  /// Switches an SVG preview tab to its source text.
  Future<void> _showSource(_OpenFile file) async {
    try {
      final text = await File(file.path).readAsString();
      if (!mounted || !_open.contains(file)) return;
      setState(() {
        file.loadFromDisk(text);
        _refreshBlame(file);
        file.kind = OpenFileKind.text;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Failed to open ${p.basename(file.path)}: $error');
    }
  }

  /// Saves pending edits in tabs for [path] or anything under it, so a
  /// rename/move/delete doesn't race with auto-save. Returns false if a
  /// save failed.
  Future<bool> flushPendingSaves(String path) async {
    for (final file in List.of(_open)) {
      if (!FileOps.isSameOrWithin(path, file.path)) continue;
      if (file.isDirty && !await _save(file)) return false;
      file.autoSaveTimer?.cancel();
    }
    return true;
  }

  /// Points tabs for [from] (a file or folder) at [to] after a rename or
  /// move.
  void handlePathMoved(String from, String to) {
    var changed = false;
    for (final file in _open) {
      if (!FileOps.isSameOrWithin(from, file.path)) continue;
      file.path = p.equals(from, file.path)
          ? to
          : p.join(to, p.relative(file.path, from: from));
      if (file.conflict == _DiskConflict.deleted) file.conflict = null;
      // Blame is per path; recompute for the new one when shown.
      file.blame?.dispose();
      file.blame = null;
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  /// Closes tabs for [path] (a file or folder) after it was deleted,
  /// dropping any unsaved edits.
  void handlePathDeleted(String path) {
    final active = _activeIndex >= 0 && _activeIndex < _open.length
        ? _open[_activeIndex]
        : null;
    final removed = _open
        .where((f) => FileOps.isSameOrWithin(path, f.path))
        .toList();
    if (removed.isEmpty) return;
    for (final file in removed) {
      file.autoSaveTimer?.cancel();
      file.dispose();
    }
    setState(() {
      _open.removeWhere(removed.contains);
      final kept = active == null ? -1 : _open.indexOf(active);
      _activeIndex = kept != -1
          ? kept
          : (_open.isEmpty ? -1 : _activeIndex.clamp(0, _open.length - 1));
    });
  }

  /// Opens the language picker for the active text tab.
  Future<void> _pickLanguage(_OpenFile file) async {
    final choice = await showLanguagePicker(
      context,
      current: FileLanguageOverrides.languageFor(file.path),
      detected: detectFileLanguage(file.path),
      hasOverride: FileLanguageOverrides.hasOverride(file.path),
    );
    if (choice == null) return;
    await FileLanguageOverrides.set(
      file.path,
      choice == kAutoDetectLanguage ? null : choice,
    );
  }

  /// Writes [file] to disk. Returns false (and shows the error) on failure.
  /// Files opened with merge conflict markers; once their blocks are gone
  /// the conflict bar offers to mark them resolved.
  final Set<String> _hadConflicts = {};

  /// Saves [file] and stages it, which tells git its conflict is resolved.
  Future<void> _markResolved(_OpenFile file) async {
    final root = widget.repoRoot;
    if (root == null) return;
    final rel = repoRelativePath(root, file.path);
    if (rel == null) return;
    if (file.isDirty && !await _save(file)) return;
    final result = await GitActions.stage(root, rel);
    if (!mounted) return;
    setState(() {
      if (result.isSuccess) {
        _hadConflicts.remove(file.path);
      } else {
        _error = result.error;
      }
    });
  }

  Future<bool> _save(_OpenFile file) async {
    file.autoSaveTimer?.cancel();
    if (file.kind != OpenFileKind.text) return true;
    // Edits made while the write is in flight must keep the file dirty, so
    // compare against the text actually written rather than the live text.
    final text = file.controller.text;
    try {
      await File(file.path).writeAsString(text);
      final modified = await _modifiedOnDisk(file.path);
      if (!mounted || !_open.contains(file)) return true;
      setState(() {
        file.savedText = text;
        file.isDirty = file.controller.text != text;
        file.diskModified = modified;
        file.conflict = null;
      });
      _refreshBlame(file);
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
    file.dispose();
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
    final language = active.kind == OpenFileKind.text
        ? FileLanguageOverrides.languageFor(active.path) ?? kPlainText
        : null;
    final languageName = language?.grammar;
    final mode = languageName == null || languageName == kPlainTextGrammar
        ? null
        : builtinAllLanguages[languageName];
    final fileTypeLabel = switch (active.kind) {
      OpenFileKind.text => language!.label,
      OpenFileKind.image => translate('preview_image'),
      OpenFileKind.svg => 'SVG',
      OpenFileKind.binary => null,
    };
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
                    onSelect: (i) {
                      setState(() => _activeIndex = i);
                      unawaited(checkDisk());
                      _refreshBlame(_open[i]);
                    },
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
                      onPressed: active.isDirty && active.kind == OpenFileKind.text
                          ? () => _save(active)
                          : null,
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
          if (active.conflict != null)
            _DiskConflictBanner(
              conflict: active.conflict!,
              isDirty: active.isDirty,
              onReload: () {
                unawaited(_reloadFromDisk(active));
                _editorFocus.requestFocus();
              },
              onKeepMine: () {
                unawaited(_keepMine(active));
                _editorFocus.requestFocus();
              },
              onClose: () => handlePathDeleted(active.path),
            ),
          if (active.kind != OpenFileKind.text)
            Expanded(
              child: FilePreview(
                key: ValueKey('${active.path}#${active.previewVersion}'),
                path: active.path,
                kind: active.kind,
                onShowSource: active.kind == OpenFileKind.svg
                    ? () => _showSource(active)
                    : null,
              ),
            ),
          if (active.kind == OpenFileKind.text)
            ConflictBar(
              key: ValueKey('conflicts:${active.path}'),
              controller: active.controller,
              showResolved: _hadConflicts.contains(active.path),
              mineIsBottom: widget.rebasing,
              onDismissResolved: () =>
                  setState(() => _hadConflicts.remove(active.path)),
              onMarkResolved: widget.repoRoot == null
                  ? null
                  : () => unawaited(_markResolved(active)),
            ),
          if (active.kind == OpenFileKind.text)
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.keyS, control: true):
                    () => _save(active),
                const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
                    () => _save(active),
              },
              // Code always reads left to right, also in Arabic / Persian.
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Focus(
                autofocus: true,
                child: CodeEditor(
                  key: ValueKey(active.path),
                  focusNode: _editorFocus,
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
          ),
          if (active.kind == OpenFileKind.text)
            _EditorFooter(
              file: active,
              onOpenCommit: widget.onOpenCommit,
              languageLabel: fileTypeLabel,
              onPickLanguage: () => _pickLanguage(active),
            ),
        ],
      ),
    );
  }
}

/// 28px status footer: saved/modified on the left, cursor position,
/// encoding and language on the right.
class _EditorFooter extends StatelessWidget {
  const _EditorFooter({
    required this.file,
    required this.languageLabel,
    required this.onPickLanguage,
    this.onOpenCommit,
  });

  final _OpenFile file;
  final ValueChanged<BlameHunk>? onOpenCommit;
  final String? languageLabel;
  final VoidCallback onPickLanguage;

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
          final parts = [position, 'UTF-8'];
          return Row(
            children: [
              Text(
                translate(file.isDirty ? 'editor_modified' : 'editor_saved'),
                style: style,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _LineBlame(
                  blame: file.blame?.blame,
                  // 1-based; the footer rebuilds as the cursor moves.
                  line: selection.extentIndex + 1,
                  onOpenCommit: onOpenCommit,
                ),
              ),
              const SizedBox(width: 16),
              Text(parts.join('  ·  '), style: style),
              if (languageLabel != null) ...[
                Text('  ·  ', style: style),
                Tooltip(
                  message: translate('editor_select_language'),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: onPickLanguage,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Text(languageLabel!, style: style),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// "Alice, 3 months ago · Fix login" for the cursor's line; clicking it
/// opens the commit in History.
class _LineBlame extends StatelessWidget {
  const _LineBlame({
    required this.blame,
    required this.line,
    required this.onOpenCommit,
  });

  final ValueListenable<FileBlame?>? blame;
  final int line;
  final ValueChanged<BlameHunk>? onOpenCommit;

  @override
  Widget build(BuildContext context) {
    final source = blame;
    if (source == null) return const SizedBox.shrink();
    return ValueListenableBuilder<FileBlame?>(
      valueListenable: source,
      builder: (context, value, _) {
        final hunk = value?.at(line);
        if (hunk == null) return const SizedBox.shrink();
        final c = context.branchi;
        final style = TextStyle(fontSize: 12, color: c.muted);
        if (!hunk.isCommitted) {
          return Text(
            translate('blame_not_committed'),
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }
        final when = hunk.time == null
            ? ''
            : formatRelativeTime(hunk.time!, DateTime.now());
        final label = [
          hunk.author,
          if (when.isNotEmpty) when,
        ].join(', ');
        final tooltip = [
          '${hunk.commitId!.substring(0, 8)}  ${hunk.author} <${hunk.email}>',
          if (hunk.time != null) hunk.time!.toString().substring(0, 16),
          hunk.summary,
          '',
          translate('blame_open_in_history'),
        ].join('\n');
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: Tooltip(
            message: tooltip,
            waitDuration: const Duration(milliseconds: 400),
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: onOpenCommit == null ? null : () => onOpenCommit!(hunk),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history, size: 13, color: c.muted),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: label),
                          if (hunk.summary.isNotEmpty)
                            TextSpan(text: '  ·  ${hunk.summary}'),
                        ]),
                        style: style,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Shown above a tab whose file changed or vanished on disk.
class _DiskConflictBanner extends StatelessWidget {
  const _DiskConflictBanner({
    required this.conflict,
    required this.isDirty,
    required this.onReload,
    required this.onKeepMine,
    required this.onClose,
  });

  final _DiskConflict conflict;
  final bool isDirty;
  final VoidCallback onReload;
  final VoidCallback onKeepMine;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.branchi;
    final deleted = conflict == _DiskConflict.deleted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      decoration: BoxDecoration(
        color: c.mod.withValues(alpha: 0.12),
        border: Border(bottom: c.hairline),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: c.mod),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              translate(
                deleted ? 'editor_deleted_on_disk' : 'editor_changed_on_disk',
              ),
              style: TextStyle(fontSize: 12, color: c.fg),
            ),
          ),
          if (deleted) ...[
            if (isDirty)
              TextButton(
                onPressed: onKeepMine,
                child: Text(translate('editor_save_again')),
              ),
            TextButton(
              onPressed: onClose,
              child: Text(translate('editor_close_tab')),
            ),
          ] else ...[
            TextButton(
              onPressed: onReload,
              child: Text(translate('editor_reload')),
            ),
            TextButton(
              onPressed: onKeepMine,
              child: Text(translate('editor_keep_mine')),
            ),
          ],
        ],
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
