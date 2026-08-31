import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../code/code_view.dart';
import 'branch_sidebar.dart';
import 'column_resize_handle.dart';
import 'commit_detail.dart';
import 'commit_list.dart';
import 'git_actions.dart';
import 'mode_rail.dart';
import 'models.dart';
import 'panel_layout_store.dart';
import 'working_changes_panel.dart';

const double _defaultSidebarWidth = 220;
const double _defaultCommitListWidth = 360;
const double _minColumnWidth = 160;
const double _maxColumnWidth = 640;

/// The main view for an opened repository: a branch sidebar, the commit
/// log, and a detail/diff pane for the selected commit.
class RepositoryView extends StatefulWidget {
  const RepositoryView({super.key, required this.path});

  final String path;

  @override
  State<RepositoryView> createState() => _RepositoryViewState();
}

class _RepositoryViewState extends State<RepositoryView> {
  List<CommitEntry> _commits = [];
  List<BranchEntry> _branches = [];
  bool _isLoading = true;
  String? _loadError;

  CommitEntry? _selectedCommit;
  List<DiffFileEntry> _diffFiles = [];
  bool _isDiffLoading = false;
  String? _diffError;
  String? _selectedFilePath;

  List<StatusEntry> _status = [];
  bool _isStatusLoading = false;
  String? _statusError;
  bool _isViewingChanges = false;

  double _sidebarWidth = _defaultSidebarWidth;
  double _commitListWidth = _defaultCommitListWidth;

  RepoViewMode _mode = RepoViewMode.git;
  final GlobalKey<CodeViewState> _codeViewKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadRepository();
    _loadPanelLayout();
  }

  Future<void> _loadPanelLayout() async {
    final results = await Future.wait([
      PanelLayoutStore.loadSidebarWidth(),
      PanelLayoutStore.loadCommitListWidth(),
    ]);
    if (!mounted) return;
    setState(() {
      _sidebarWidth = results[0] ?? _defaultSidebarWidth;
      _commitListWidth = results[1] ?? _defaultCommitListWidth;
    });
  }

  void _resizeSidebar(double delta) {
    setState(() {
      _sidebarWidth = (_sidebarWidth + delta)
          .clamp(_minColumnWidth, _maxColumnWidth);
    });
  }

  void _resizeCommitList(double delta) {
    setState(() {
      _commitListWidth = (_commitListWidth + delta)
          .clamp(_minColumnWidth, _maxColumnWidth);
    });
  }

  @override
  void didUpdateWidget(covariant RepositoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _selectedCommit = null;
      _diffFiles = [];
      _selectedFilePath = null;
      _loadRepository();
    }
  }

  Future<void> _loadRepository() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final results = await Future.wait([
        GitActions.log(widget.path),
        GitActions.branches(widget.path),
      ]);
      if (!mounted) return;
      setState(() {
        _commits = results[0] as List<CommitEntry>;
        _branches = results[1] as List<BranchEntry>;
        _isLoading = false;
      });
      unawaited(_loadStatus());
      if (_commits.isNotEmpty && !_isViewingChanges) {
        _selectCommit(_commits.first);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = error.toString();
      });
    }
  }

  Future<void> _loadStatus() async {
    setState(() {
      _isStatusLoading = true;
      _statusError = null;
    });
    try {
      final status = await GitActions.status(widget.path);
      if (!mounted) return;
      setState(() {
        _status = status;
        _isStatusLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isStatusLoading = false;
        _statusError = error.toString();
      });
    }
  }

  void _selectWorkingChanges() {
    setState(() {
      _isViewingChanges = true;
      _selectedCommit = null;
    });
  }

  Future<bool> _stage(StatusEntry entry) async {
    final result = await GitActions.stage(widget.path, entry.path);
    if (!mounted) return false;
    if (result.isSuccess) {
      await _loadStatus();
    } else {
      _showError(result.error!);
    }
    return result.isSuccess;
  }

  Future<bool> _unstage(StatusEntry entry) async {
    final result = await GitActions.unstage(widget.path, entry.path);
    if (!mounted) return false;
    if (result.isSuccess) {
      await _loadStatus();
    } else {
      _showError(result.error!);
    }
    return result.isSuccess;
  }

  Future<bool> _revertFile(StatusEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revert file?'),
        content: Text(
          'This discards uncommitted working-tree changes to '
          '"${entry.path}". This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Revert'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;

    final result = await GitActions.revertFile(widget.path, entry.path);
    if (!mounted) return false;
    if (result.isSuccess) {
      await _loadStatus();
    } else {
      _showError(result.error!);
    }
    return result.isSuccess;
  }

  Future<bool> _commit(String message) async {
    final result = await GitActions.commit(widget.path, message);
    if (!mounted) return false;
    if (result.isSuccess) {
      await Future.wait([_loadStatus(), _loadRepository()]);
    } else {
      _showError(result.error!);
    }
    return result.isSuccess;
  }

  Future<bool> _commitAndPush(String message) async {
    final committed = await _commit(message);
    if (!committed || !mounted) return committed;

    String? headBranch;
    for (final branch in _branches) {
      if (!branch.isRemote && branch.isHead) {
        headBranch = branch.name;
        break;
      }
    }
    if (headBranch == null) {
      _showError('No current branch to push.');
      return true;
    }

    final result = await GitActions.push(widget.path, headBranch);
    if (!mounted) return true;
    if (!result.isSuccess) {
      _showError(result.error!);
    }
    return true;
  }

  /// Switches to Code mode and opens [relativePath] (relative to the repo
  /// root) in the editor, e.g. from a diff or working-changes file list.
  void _openFileInEditor(String relativePath) {
    final absolutePath = p.join(widget.path, relativePath);
    setState(() => _mode = RepoViewMode.code);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _codeViewKey.currentState?.openFile(absolutePath);
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _selectCommit(CommitEntry commit) async {
    setState(() {
      _isViewingChanges = false;
      _selectedCommit = commit;
      _diffFiles = [];
      _selectedFilePath = null;
      _isDiffLoading = true;
      _diffError = null;
    });

    try {
      final diff = await GitActions.commitDiff(widget.path, commit.id);
      if (!mounted || _selectedCommit?.id != commit.id) return;
      setState(() {
        _diffFiles = diff;
        _selectedFilePath = diff.isEmpty ? null : diff.first.path;
        _isDiffLoading = false;
      });
    } catch (error) {
      if (!mounted || _selectedCommit?.id != commit.id) return;
      setState(() {
        _isDiffLoading = false;
        _diffError = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(child: Text('Failed to load repository: $_loadError'));
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModeRail(
          mode: _mode,
          onChanged: (mode) => setState(() => _mode = mode),
        ),
        if (_mode == RepoViewMode.code)
          Expanded(
            child: CodeView(key: _codeViewKey, repoPath: widget.path),
          )
        else
          Expanded(child: _buildGitView(context)),
      ],
    );
  }

  Widget _buildGitView(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BranchSidebar(
          repoPath: widget.path,
          branches: _branches,
          width: _sidebarWidth,
          onChanged: _loadRepository,
        ),
        ColumnResizeHandle(
          onDrag: _resizeSidebar,
          onDragEnd: () => PanelLayoutStore.saveSidebarWidth(_sidebarWidth),
        ),
        SizedBox(
          width: _commitListWidth,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WorkingChangesBar(
                  status: _status,
                  selected: _isViewingChanges,
                  onTap: _selectWorkingChanges,
                ),
                const Divider(height: 1),
                Expanded(
                  child: CommitList(
                    commits: _commits,
                    selectedId: _isViewingChanges ? null : _selectedCommit?.id,
                    onSelect: _selectCommit,
                  ),
                ),
              ],
            ),
          ),
        ),
        ColumnResizeHandle(
          onDrag: _resizeCommitList,
          onDragEnd: () =>
              PanelLayoutStore.saveCommitListWidth(_commitListWidth),
        ),
        Expanded(
          child: _isViewingChanges
              ? WorkingChangesDetail(
                  status: _status,
                  isLoading: _isStatusLoading,
                  error: _statusError,
                  canPush: _branches.any((b) => !b.isRemote && b.isHead),
                  onStage: _stage,
                  onUnstage: _unstage,
                  onRevert: _revertFile,
                  onCommit: _commit,
                  onCommitAndPush: _commitAndPush,
                  onOpenFile: (entry) => _openFileInEditor(entry.path),
                )
              : CommitDetail(
                  commit: _selectedCommit,
                  diffFiles: _diffFiles,
                  isLoading: _isDiffLoading,
                  error: _diffError,
                  selectedFilePath: _selectedFilePath,
                  onSelectFile: (path) =>
                      setState(() => _selectedFilePath = path),
                  onOpenFile: _openFileInEditor,
                ),
        ),
      ],
    );
  }
}
