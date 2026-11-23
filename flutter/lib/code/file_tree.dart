import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_locale.dart';
import '../repo/file_explorer.dart';
import '../repo/git_actions.dart';
import '../repo/models.dart';
import '../theme/app_theme.dart';
import 'file_ops.dart';

/// Bumped whenever a file is written from the editor, so any visible
/// [FileTree] re-reads git status (and its M/A markers stay current).
final ValueNotifier<int> fileTreeRefreshSignal = ValueNotifier<int>(0);

/// A lazily-expanded directory tree rooted at [rootPath], skipping `.git`.
/// Selecting a file calls [onOpenFile] with its absolute path.
///
/// Files and folders can be created, cut, copied, pasted, renamed and moved
/// to the trash from the right-click menu or with the usual shortcuts while
/// the tree has focus (Ctrl/Cmd+X/C/V, F2, Delete), and moved by dragging
/// them onto a folder.
class FileTree extends StatefulWidget {
  const FileTree({
    super.key,
    required this.rootPath,
    required this.onOpenFile,
    this.selectedPath,
    this.width = 260,
    this.onBeforeChange,
    this.onPathMoved,
    this.onPathDeleted,
    this.onSearch,
    this.onSearchContent,
  });

  final String rootPath;
  final ValueChanged<String> onOpenFile;
  final String? selectedPath;
  final double width;

  /// Called before [path] is renamed, moved or deleted, e.g. to save open
  /// editor tabs first. Returning false cancels the operation.
  final Future<bool> Function(String path)? onBeforeChange;

  /// Called after a file or folder moved from the first path to the second.
  final void Function(String from, String to)? onPathMoved;

  /// Called after a file or folder was moved to the trash.
  final ValueChanged<String>? onPathDeleted;

  /// Opens the "go to file" search.
  final VoidCallback? onSearch;

  /// Switches the sidebar to "search in files".
  final VoidCallback? onSearchContent;

  @override
  State<FileTree> createState() => _FileTreeState();
}

class _FileTreeState extends State<FileTree> {
  final Set<String> _expanded = {};
  final FocusNode _focusNode = FocusNode(debugLabel: 'FileTree');

  /// Absolute path -> single-letter git status ("M", "A", "D", ...).
  Map<String, String> _status = const {};
  Timer? _statusTimer;

  /// The highlighted row (a file or folder), the target of shortcuts.
  String? _selected;

  /// The row currently showing the inline rename field.
  String? _renaming;

  /// Where a new file or folder is being named, if anywhere.
  ({String dir, bool isDir})? _creating;

  /// The folder a dragged item would be dropped into, for highlighting.
  String? _dropDir;

  /// Expands a collapsed folder when a drag hovers over it for a moment.
  Timer? _dragExpandTimer;
  String? _dragExpandPath;

  /// Guards against starting another operation while one is running.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _expanded.add(widget.rootPath);
    _selected = widget.selectedPath;
    fileTreeRefreshSignal.addListener(_loadStatus);
    fileClipboard.addListener(_onClipboardChanged);
    _loadStatus();
    _statusTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _loadStatus());
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _dragExpandTimer?.cancel();
    fileTreeRefreshSignal.removeListener(_loadStatus);
    fileClipboard.removeListener(_onClipboardChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onClipboardChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant FileTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rootPath != widget.rootPath) {
      _expanded
        ..clear()
        ..add(widget.rootPath);
      _status = const {};
      _selected = null;
      _renaming = null;
      _creating = null;
      _loadStatus();
    }
    if (oldWidget.selectedPath != widget.selectedPath &&
        widget.selectedPath != null) {
      _selected = widget.selectedPath;
      _revealPath(widget.selectedPath!);
    }
  }

  /// Expands every folder between the root and [path].
  void _revealPath(String path) {
    var dir = p.dirname(path);
    while (FileOps.isSameOrWithin(widget.rootPath, dir) &&
        _expanded.add(dir)) {
      final parent = p.dirname(dir);
      if (parent == dir) break;
      dir = parent;
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

  // ---- Operations ---------------------------------------------------------

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Runs [op] unless another operation is in flight, reporting
  /// [FileOpException]s to the user.
  Future<void> _run(Future<void> Function() op) async {
    if (_busy) return;
    _busy = true;
    try {
      await op();
    } on FileOpException catch (error) {
      _showError(error.message);
    } finally {
      _busy = false;
      if (mounted) setState(() {});
      fileTreeRefreshSignal.value++;
    }
  }

  void _cut(String path) =>
      fileClipboard.value = FileClipboardEntry(path, isCut: true);

  void _copy(String path) =>
      fileClipboard.value = FileClipboardEntry(path, isCut: false);

  /// The folder a paste lands in: [path] if it's a folder, else its parent.
  String _pasteTargetFor(String? path) {
    if (path == null) return widget.rootPath;
    return FileSystemEntity.isDirectorySync(path) ? path : p.dirname(path);
  }

  Future<void> _paste(String? at) async {
    final entry = fileClipboard.value;
    if (entry == null) return;
    await _pasteEntry(entry, _pasteTargetFor(at));
  }

  /// Copies or moves [entry] into [targetDir]; drag and drop moves too.
  Future<void> _pasteEntry(FileClipboardEntry entry, String targetDir) =>
      _run(() async {
        if (entry.isCut &&
            !(await widget.onBeforeChange?.call(entry.path) ?? true)) {
          return;
        }
        final dest = await FileOps.paste(entry, targetDir);
        if (entry.isCut) {
          // A cut can be pasted only once.
          final clip = fileClipboard.value;
          if (clip != null && FileOps.isSameOrWithin(entry.path, clip.path)) {
            fileClipboard.value = null;
          }
          if (dest != entry.path) widget.onPathMoved?.call(entry.path, dest);
          _moveExpanded(entry.path, dest);
        }
        if (!mounted) return;
        setState(() {
          _expanded.add(targetDir);
          _selected = dest;
        });
      });

  /// Keeps expanded folders expanded after [from] moved to [to].
  void _moveExpanded(String from, String to) {
    final moved = _expanded
        .where((dir) => FileOps.isSameOrWithin(from, dir))
        .toList();
    for (final dir in moved) {
      _expanded
        ..remove(dir)
        ..add(p.equals(from, dir) ? to : p.join(to, p.relative(dir, from: from)));
    }
  }

  void _startCreate(String? at, {required bool isDir}) {
    final dir = _pasteTargetFor(at);
    setState(() {
      _renaming = null;
      _expanded.add(dir);
      _revealPath(p.join(dir, 'x'));
      _creating = (dir: dir, isDir: isDir);
    });
  }

  Future<void> _commitCreate(String name) async {
    final creating = _creating;
    if (creating == null) return;
    setState(() => _creating = null);
    if (name.trim().isEmpty) {
      _focusNode.requestFocus();
      return;
    }
    await _run(() async {
      final path = await FileOps.create(
        creating.dir,
        name,
        isDir: creating.isDir,
      );
      _revealPath(path);
      _selected = path;
      if (creating.isDir) {
        _expanded.add(path);
      } else {
        widget.onOpenFile(path);
      }
    });
    if (creating.isDir) _focusNode.requestFocus();
  }

  void _cancelCreate() {
    setState(() => _creating = null);
    _focusNode.requestFocus();
  }

  Future<void> _copyPath(String path, {required bool relative}) async {
    final text = relative
        ? p.split(p.relative(path, from: widget.rootPath)).join('/')
        : path;
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> _reveal(String path) async {
    final error = await revealInFileExplorer(path);
    if (error != null) _showError(error);
  }

  // ---- Drag and drop ------------------------------------------------------

  /// The folder a drop on [path] lands in: the folder itself, or a file's
  /// parent; the root for null.
  String _dropDirFor(String? path) => _pasteTargetFor(path);

  bool _canDrop(String src, String targetDir) {
    if (FileOps.isSameOrWithin(src, targetDir)) return false;
    return !p.equals(p.dirname(src), targetDir);
  }

  void _onDragHover(String? rowPath, String src) {
    final dir = _dropDirFor(rowPath);
    final accept = _canDrop(src, dir);
    if (_dropDir != (accept ? dir : null)) {
      setState(() => _dropDir = accept ? dir : null);
    }
    // Hovering a collapsed folder opens it after a moment.
    if (rowPath != null &&
        rowPath == dir &&
        !_expanded.contains(dir) &&
        _dragExpandPath != dir) {
      _dragExpandTimer?.cancel();
      _dragExpandPath = dir;
      _dragExpandTimer = Timer(const Duration(milliseconds: 700), () {
        if (mounted && _dragExpandPath == dir) {
          setState(() => _expanded.add(dir));
        }
      });
    }
  }

  void _onDragLeave() {
    _dragExpandTimer?.cancel();
    _dragExpandPath = null;
    if (_dropDir != null) setState(() => _dropDir = null);
  }

  Future<void> _onDrop(String? rowPath, String src) async {
    final dir = _dropDirFor(rowPath);
    _onDragLeave();
    if (!_canDrop(src, dir)) return;
    await _pasteEntry(FileClipboardEntry(src, isCut: true), dir);
  }

  Widget _dropTarget({required String? rowPath, required Widget child}) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          _canDrop(details.data, _dropDirFor(rowPath)),
      onMove: (details) => _onDragHover(rowPath, details.data),
      onLeave: (_) => _onDragLeave(),
      onAcceptWithDetails: (details) => _onDrop(rowPath, details.data),
      builder: (context, _, _) => child,
    );
  }

  void _startRename(String path) {
    if (p.equals(path, widget.rootPath)) return;
    setState(() {
      _creating = null;
      _selected = path;
      _renaming = path;
    });
  }

  Future<void> _commitRename(String path, String newName) async {
    if (_renaming != path) return;
    setState(() => _renaming = null);
    if (newName.trim() == p.basename(path)) {
      _focusNode.requestFocus();
      return;
    }
    await _run(() async {
      if (!(await widget.onBeforeChange?.call(path) ?? true)) return;
      final dest = await FileOps.rename(path, newName);
      final clip = fileClipboard.value;
      if (clip != null && FileOps.isSameOrWithin(path, clip.path)) {
        fileClipboard.value = null;
      }
      widget.onPathMoved?.call(path, dest);
      _moveExpanded(path, dest);
      _selected = dest;
    });
    _focusNode.requestFocus();
  }

  void _cancelRename() {
    setState(() => _renaming = null);
    _focusNode.requestFocus();
  }

  Future<void> _delete(String path) async {
    if (p.equals(path, widget.rootPath)) return;
    final name = p.basename(path);
    final isDir = FileSystemEntity.isDirectorySync(path);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(translate('file_delete_title')),
        content: Text(
          translate(isDir ? 'file_delete_folder_confirm' : 'file_delete_confirm')
              .replaceAll('{name}', name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(translate('cancel')),
          ),
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(translate('file_move_to_trash')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      if (!(await widget.onBeforeChange?.call(path) ?? true)) return;
      await FileOps.moveToTrash(path);
      final clip = fileClipboard.value;
      if (clip != null && FileOps.isSameOrWithin(path, clip.path)) {
        fileClipboard.value = null;
      }
      _expanded.removeWhere((dir) => FileOps.isSameOrWithin(path, dir));
      if (_selected != null && FileOps.isSameOrWithin(path, _selected!)) {
        _selected = null;
      }
      widget.onPathDeleted?.call(path);
    });
    _focusNode.requestFocus();
  }

  Future<void> _showContextMenu(Offset globalPosition, String? path) async {
    _focusNode.requestFocus();
    if (path != null) setState(() => _selected = path);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final isRoot = path == null || p.equals(path, widget.rootPath);
    final mod = Platform.isMacOS ? '⌘' : 'Ctrl+';
    final revealLabel = translate(
      Platform.isWindows
          ? 'file_reveal_explorer'
          : Platform.isMacOS
              ? 'file_reveal_finder'
              : 'file_reveal_files',
    );

    PopupMenuItem<String> item(
      String value,
      String label, {
      String? shortcut,
      bool enabled = true,
    }) {
      final c = context.branchi;
      return PopupMenuItem<String>(
        value: value,
        enabled: enabled,
        height: 36,
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
            if (shortcut != null)
              Text(shortcut, style: TextStyle(fontSize: 12, color: c.muted)),
          ],
        ),
      );
    }

    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        item('new_file', translate('file_new_file')),
        item('new_folder', translate('file_new_folder')),
        const PopupMenuDivider(),
        if (!isRoot) ...[
          item('cut', translate('file_cut'), shortcut: '${mod}X'),
          item('copy', translate('copy'), shortcut: '${mod}C'),
        ],
        item(
          'paste',
          translate('paste'),
          shortcut: '${mod}V',
          enabled: fileClipboard.value != null,
        ),
        const PopupMenuDivider(),
        item('copy_path', translate('file_copy_path')),
        if (!isRoot)
          item('copy_relative_path', translate('file_copy_relative_path')),
        item('reveal', revealLabel),
        if (!isRoot) ...[
          const PopupMenuDivider(),
          item('rename', translate('file_rename'), shortcut: 'F2'),
          item(
            'delete',
            translate('file_delete'),
            shortcut: Platform.isMacOS ? '⌘⌫' : 'Del',
          ),
        ],
      ],
    );
    if (!mounted) return;
    final target = path ?? widget.rootPath;
    switch (action) {
      case 'new_file':
        _startCreate(path, isDir: false);
      case 'new_folder':
        _startCreate(path, isDir: true);
      case 'copy_path':
        await _copyPath(target, relative: false);
      case 'copy_relative_path':
        await _copyPath(target, relative: true);
      case 'reveal':
        await _reveal(target);
      case 'cut':
        _cut(path!);
      case 'copy':
        _copy(path!);
      case 'paste':
        await _paste(path);
      case 'rename':
        _startRename(path!);
      case 'delete':
        await _delete(path!);
    }
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts {
    void withSelected(void Function(String path) action) {
      final path = _selected;
      if (path == null || _renaming != null || _creating != null) return;
      if (FileSystemEntity.typeSync(path) == FileSystemEntityType.notFound) {
        return;
      }
      action(path);
    }

    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.f2): () =>
          withSelected(_startRename),
      const SingleActivator(LogicalKeyboardKey.delete): () =>
          withSelected(_delete),
    };
    for (final meta in [false, true]) {
      bindings.addAll({
        SingleActivator(LogicalKeyboardKey.keyX, control: !meta, meta: meta):
            () => withSelected(_cut),
        SingleActivator(LogicalKeyboardKey.keyC, control: !meta, meta: meta):
            () => withSelected(_copy),
        SingleActivator(LogicalKeyboardKey.keyV, control: !meta, meta: meta):
            () {
          if (_renaming == null && _creating == null) {
            unawaited(_paste(_selected));
          }
        },
      });
    }
    if (Platform.isMacOS) {
      bindings[const SingleActivator(LogicalKeyboardKey.backspace, meta: true)] =
          () => withSelected(_delete);
    }
    return bindings;
  }

  // ---- UI -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = context.branchi;
    final mod = Platform.isMacOS ? '⌘' : 'Ctrl+';
    return SizedBox(
      width: widget.width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.bg,
          border: Border(right: c.hairline),
        ),
        child: CallbackShortcuts(
          bindings: _shortcuts,
          child: Focus(
            focusNode: _focusNode,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              // Right-click on empty space: paste into the root.
              onSecondaryTapUp: (details) =>
                  _showContextMenu(details.globalPosition, null),
              onTap: () => _focusNode.requestFocus(),
              child: _dropTarget(
                rowPath: null,
                child: Container(
                color: _dropDir != null && p.equals(_dropDir!, widget.rootPath)
                    ? c.accent.withValues(alpha: 0.06)
                    : null,
                child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
                children: [
                  Padding(
                    padding:
                        const EdgeInsetsDirectional.fromSTEB(12, 0, 4, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            translate('editor_explorer'),
                            style: TextStyle(
                              fontSize: 11,
                              color: c.muted,
                              letterSpacing: 0.44,
                            ),
                          ),
                        ),
                        if (widget.onSearchContent != null)
                          IconButton(
                            icon: const Icon(Icons.manage_search, size: 17),
                            color: c.muted,
                            visualDensity: VisualDensity.compact,
                            tooltip:
                                '${translate('content_search')} (${mod}Shift+F)',
                            onPressed: widget.onSearchContent,
                          ),
                        if (widget.onSearch != null)
                          IconButton(
                            icon: const Icon(Icons.search, size: 16),
                            color: c.muted,
                            visualDensity: VisualDensity.compact,
                            tooltip:
                                '${translate('file_search')} (${mod}P)',
                            onPressed: widget.onSearch,
                          ),
                      ],
                    ),
                  ),
                  ..._buildEntries(widget.rootPath, 0),
                ],
              ),
              ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildEntries(String dir, int depth) {
    final widgets = <Widget>[];
    final clip = fileClipboard.value;
    final creating = _creating;
    if (creating != null && p.equals(creating.dir, dir)) {
      widgets.add(_FileTreeRow(
        key: const ValueKey('__new_entry__'),
        name: '',
        depth: depth,
        isDirectory: creating.isDir,
        isExpanded: false,
        isSelected: true,
        isCut: false,
        isRenaming: true,
        isDropTarget: false,
        statusLetter: null,
        onTap: () {},
        onSecondaryTap: (_) {},
        onRenameSubmit: _commitCreate,
        onRenameCancel: _cancelCreate,
      ));
    }
    for (final entity in _listDir(dir)) {
      final path = entity.path;
      final isDir = entity is Directory;
      final isExpanded = _expanded.contains(path);
      final row = _FileTreeRow(
        key: ValueKey(path),
        name: p.basename(path),
        depth: depth,
        isDirectory: isDir,
        isExpanded: isExpanded,
        isSelected: path == _selected,
        isCut: clip != null && clip.isCut && clip.path == path,
        isRenaming: path == _renaming,
        isDropTarget: isDir && _dropDir != null && p.equals(_dropDir!, path),
        statusLetter: isDir ? null : _status[p.normalize(path)],
        onTap: () {
          _focusNode.requestFocus();
          setState(() {
            _selected = path;
            if (isDir) {
              if (isExpanded) {
                _expanded.remove(path);
              } else {
                _expanded.add(path);
              }
            }
          });
          if (!isDir) widget.onOpenFile(path);
        },
        onSecondaryTap: (position) => _showContextMenu(position, path),
        onRenameSubmit: (name) => _commitRename(path, name),
        onRenameCancel: _cancelRename,
      );
      // Keyed on the outermost widget so a drag in progress stays with its
      // row when folders above it expand or collapse.
      widgets.add(KeyedSubtree(
        key: ValueKey('entry:$path'),
        child: path == _renaming
            ? row
            : _dropTarget(
                rowPath: path,
                child: Draggable<String>(
                  data: path,
                  dragAnchorStrategy: pointerDragAnchorStrategy,
                  feedback: _DragFeedback(name: p.basename(path), isDir: isDir),
                  childWhenDragging: Opacity(opacity: 0.5, child: row),
                  child: row,
                ),
              ),
      ));
      if (isDir && isExpanded) {
        widgets.addAll(_buildEntries(path, depth + 1));
      }
    }
    return widgets;
  }
}

class _FileTreeRow extends StatefulWidget {
  const _FileTreeRow({
    super.key,
    required this.name,
    required this.depth,
    required this.isDirectory,
    required this.isExpanded,
    required this.isSelected,
    required this.isCut,
    required this.isRenaming,
    required this.isDropTarget,
    required this.statusLetter,
    required this.onTap,
    required this.onSecondaryTap,
    required this.onRenameSubmit,
    required this.onRenameCancel,
  });

  final String name;
  final int depth;
  final bool isDirectory;
  final bool isExpanded;
  final bool isSelected;
  final bool isCut;
  final bool isRenaming;
  final bool isDropTarget;
  final String? statusLetter;
  final VoidCallback onTap;
  final ValueChanged<Offset> onSecondaryTap;
  final ValueChanged<String> onRenameSubmit;
  final VoidCallback onRenameCancel;

  @override
  State<_FileTreeRow> createState() => _FileTreeRowState();
}

class _FileTreeRowState extends State<_FileTreeRow> {
  bool _hovering = false;
  TextEditingController? _renameController;
  FocusNode? _renameFocus;

  @override
  void initState() {
    super.initState();
    if (widget.isRenaming) _beginRename();
  }

  @override
  void didUpdateWidget(covariant _FileTreeRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRenaming && !oldWidget.isRenaming) _beginRename();
    if (!widget.isRenaming && oldWidget.isRenaming) _endRename();
  }

  @override
  void dispose() {
    _endRename();
    super.dispose();
  }

  void _beginRename() {
    final name = widget.name;
    // Select the name without its extension, as in VS Code.
    final dot = name.lastIndexOf('.');
    final end = widget.isDirectory || dot <= 0 ? name.length : dot;
    _renameController = TextEditingController(text: name)
      ..selection = TextSelection(baseOffset: 0, extentOffset: end);
    _renameFocus = FocusNode()
      ..addListener(() {
        // Clicking elsewhere commits, as Enter does.
        if (!(_renameFocus?.hasFocus ?? true) && widget.isRenaming) {
          widget.onRenameSubmit(_renameController!.text);
        }
      });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _renameFocus?.requestFocus();
      // Focusing a desktop TextField selects everything; reapply the
      // name-only selection once focus has landed.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _renameController?.selection =
            TextSelection(baseOffset: 0, extentOffset: end);
      });
    });
  }

  void _endRename() {
    final controller = _renameController;
    final focus = _renameFocus;
    _renameController = null;
    _renameFocus = null;
    // Dispose after this frame: the field may still be mounted right now.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller?.dispose();
      focus?.dispose();
    });
  }

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
    final nameStyle = TextStyle(
      fontSize: 13,
      color: widget.isDirectory || widget.isSelected ? c.fg : c.muted,
    );

    final Widget label = widget.isRenaming && _renameController != null
        ? SizedBox(
            height: 20,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape):
                    widget.onRenameCancel,
              },
              child: TextField(
                controller: _renameController,
                focusNode: _renameFocus,
                style: nameStyle.copyWith(color: c.fg),
                cursorHeight: 14,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: c.accent),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: c.accent),
                  ),
                ),
                onSubmitted: widget.onRenameSubmit,
              ),
            ),
          )
        : Text(
            widget.name,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: nameStyle,
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.isRenaming ? null : widget.onTap,
          onSecondaryTapUp: widget.isRenaming
              ? null
              : (details) => widget.onSecondaryTap(details.globalPosition),
          child: Opacity(
            // A cut item looks faded until it's pasted.
            opacity: widget.isCut ? 0.5 : 1,
            child: Container(
              decoration: BoxDecoration(
                color: widget.isDropTarget
                    ? c.accent.withValues(alpha: 0.15)
                    : highlighted
                        ? c.hover
                        : null,
                borderRadius: BorderRadius.circular(6),
                border: widget.isDropTarget
                    ? Border.all(color: c.accent.withValues(alpha: 0.6))
                    : null,
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
                  Expanded(child: label),
                  if (letter != null && !widget.isRenaming) ...[
                    const SizedBox(width: 8),
                    Text(letter, style: c.mono(fontSize: 10, color: markColor)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What follows the pointer while dragging a tree item.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.name, required this.isDir});

  final String name;
  final bool isDir;

  @override
  Widget build(BuildContext context) {
    final c = context.branchi;
    return Transform.translate(
      offset: const Offset(12, 8),
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(6),
        color: c.bg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isDir ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
                size: 14,
                color: c.muted,
              ),
              const SizedBox(width: 6),
              Text(name, style: TextStyle(fontSize: 13, color: c.fg)),
            ],
          ),
        ),
      ),
    );
  }
}
