import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../code/code_view.dart';
import '../report/report_data.dart';
import '../report/report_view.dart';
import 'branch_sidebar.dart';
import 'column_resize_handle.dart';
import 'commit_detail.dart';
import 'commit_list.dart';
import 'git_actions.dart';
import 'git_ffi.dart';
import 'merge.dart';
import 'models.dart';
import 'panel_layout_store.dart';
import 'repo_controller.dart';
import 'working_changes_panel.dart';

const double _defaultSidebarWidth = 220;
const double _defaultCommitListWidth = 440;
const double _minColumnWidth = 160;
const double _maxColumnWidth = 640;

/// The main view for an opened repository. Which section is shown
/// (History: branches + commit log + commit detail; Changes: working
/// changes; Files: file tree + editor) is driven by [controller]'s
/// [RepoController.section], switched from the window's top bar.
class RepositoryView extends StatefulWidget {
  const RepositoryView({
    super.key,
    required this.path,
    required this.controller,
    this.onLanguageChanged,
    this.onOpenInTerminal,
  });

  final String path;

  /// Shared with the top bar: section, branch info, changes count, the
  /// auto-pull watcher and remote actions.
  final RepoController controller;

  /// Forwarded to the Code tab so the app's bottom bar can show the active
  /// file's detected type.
  final ValueChanged<String?>? onLanguageChanged;

  /// Opens a new built-in terminal tab in the repository folder.
  final VoidCallback? onOpenInTerminal;

  @override
  State<RepositoryView> createState() => RepositoryViewState();
}

class RepositoryViewState extends State<RepositoryView> {
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

  /// A merge stopped on conflicts, shown in Changes until finished.
  MergeState? _mergeState;

  double _sidebarWidth = _defaultSidebarWidth;
  double _commitListWidth = _defaultCommitListWidth;

  final GlobalKey<CodeViewState> _codeViewKey = GlobalKey();

  StreamSubscription<void>? _repositoryChangedSubscription;
  late RepoSection _lastSection;

  RepoController get _controller => widget.controller;
  RepoSection get _section => _controller.section;
  bool get _isViewingChanges => _section == RepoSection.changes;

  @override
  void initState() {
    super.initState();
    _attachController();
    _loadRepository();
    _loadPanelLayout();
  }

  @override
  void didUpdateWidget(covariant RepositoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detachController(oldWidget.controller);
      _attachController();
    }
    if (oldWidget.path != widget.path) {
      _selectedCommit = null;
      _diffFiles = [];
      _selectedFilePath = null;
      _loadRepository();
    }
  }

  @override
  void dispose() {
    _detachController(widget.controller);
    super.dispose();
  }

  void _attachController() {
    _lastSection = _controller.section;
    _controller.addListener(_onControllerChanged);
    _controller.watcher.addListener(_onWatcherChanged);
    _repositoryChangedSubscription = _controller.repositoryChanged.listen((_) {
      if (mounted) _loadRepository(showSpinner: false);
    });
  }

  void _detachController(RepoController controller) {
    controller.removeListener(_onControllerChanged);
    controller.watcher.removeListener(_onWatcherChanged);
    _repositoryChangedSubscription?.cancel();
    _repositoryChangedSubscription = null;
  }

  void _onWatcherChanged() {
    if (mounted) setState(() {});
  }

  /// Reacts to section switches from the top bar (and rebuilds for branch /
  /// busy-state changes).
  void _onControllerChanged() {
    if (!mounted) return;
    final previous = _lastSection;
    final current = _controller.section;
    _lastSection = current;
    if (previous != current) {
      if (previous == RepoSection.files) {
        widget.onLanguageChanged?.call(null);
        // Files edited in the editor change the working tree.
        unawaited(_loadStatus());
      }
      if (current == RepoSection.changes) {
        _selectedCommit = null;
        unawaited(_loadStatus());
      } else if (current == RepoSection.history &&
          _selectedCommit == null &&
          _commits.isNotEmpty) {
        _selectCommit(_commits.first);
      }
    }
    setState(() {});
  }

  void _setSection(RepoSection section) {
    _controller.section = section;
  }

  /// Switches to History with [commit] selected (from the Report).
  void _showCommit(ReportCommit commit) {
    _setSection(RepoSection.history);
    final listed = _commits.where((c) => c.id == commit.id);
    _selectCommit(
      listed.isNotEmpty
          ? listed.first
          : CommitEntry(
              id: commit.id,
              summary: commit.summary,
              author: commit.author,
              email: commit.email,
              time: commit.time.toUtc(),
              parentIds: const [],
            ),
    );
  }

  /// Switches to History with the commit [id] selected, e.g. from line
  /// blame in the editor. The other fields describe it when it's older
  /// than the loaded history.
  void _showCommitById(
    String id, {
    required String summary,
    required String author,
    required String email,
    DateTime? time,
  }) {
    _setSection(RepoSection.history);
    final listed = _commits.where((c) => c.id == id);
    _selectCommit(
      listed.isNotEmpty
          ? listed.first
          : CommitEntry(
              id: id,
              summary: summary,
              author: author,
              email: email,
              time: (time ?? DateTime.now()).toUtc(),
              parentIds: const [],
            ),
    );
  }

  /// Checks out [branchName] and reloads.
  Future<void> checkoutBranch(String branchName) async {
    final result = await GitActions.checkoutBranch(widget.path, branchName);
    if (!mounted) return;
    if (result.isSuccess) {
      await _loadRepository(showSpinner: false);
    } else {
      _showError(result.error!);
    }
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
      _sidebarWidth = (_sidebarWidth + delta).clamp(
        _minColumnWidth,
        _maxColumnWidth,
      );
    });
  }

  void _resizeCommitList(double delta) {
    setState(() {
      _commitListWidth = (_commitListWidth + delta).clamp(
        _minColumnWidth,
        _maxColumnWidth,
      );
    });
  }

  /// Loads the log and branches. [showSpinner] replaces the whole view with
  /// a progress indicator, which is only wanted for the initial load, not
  /// for background refreshes (e.g. after an auto-pull).
  Future<void> _loadRepository({bool showSpinner = true}) async {
    setState(() {
      if (showSpinner || _loadError != null) _isLoading = true;
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
      _notifyBranchInfo();
      unawaited(_loadStatus());
      if (_commits.isNotEmpty && !_isViewingChanges) {
        final previous = _selectedCommit?.id;
        final stillListed =
            previous != null && _commits.any((c) => c.id == previous);
        if (!stillListed) _selectCommit(_commits.first);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = error.toString();
      });
    }
  }

  void _notifyBranchInfo() {
    String? head;
    for (final branch in _branches) {
      if (!branch.isRemote && branch.isHead) {
        head = branch.name;
        break;
      }
    }
    _controller.updateBranchInfo(head, _branches);
  }

  Future<void> _loadStatus() async {
    setState(() {
      _isStatusLoading = true;
      _statusError = null;
    });
    try {
      final status = await GitActions.status(widget.path);
      final mergeState = await MergeActions.state(widget.path);
      if (!mounted) return;
      setState(() {
        _status = status;
        _mergeState = mergeState;
        _isStatusLoading = false;
      });
      _controller.updateChangesCount(status.length);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isStatusLoading = false;
        _statusError = error.toString();
      });
    }
  }

  void _selectWorkingChanges() {
    if (_isViewingChanges) {
      unawaited(_loadStatus());
      return;
    }
    // _onControllerChanged clears the selection and reloads the status.
    _setSection(RepoSection.changes);
  }

  /// Resolves a conflicted file by taking one side (`ours` / `theirs`).
  Future<void> _resolveConflict(String file, String side) async {
    // During a rebase git's "ours" is the new base; the user's own
    // commit is "theirs".
    if (_mergeState?.isRebase ?? false) {
      side = side == 'ours' ? 'theirs' : 'ours';
    }
    final error = await MergeActions.resolve(widget.path, file, side);
    if (!mounted) return;
    if (error != null) _showError(error);
    await _loadStatus();
  }

  Future<void> _abortMerge() async {
    final error = await MergeActions.abort(widget.path);
    if (!mounted) return;
    if (error != null) _showError(error);
    await Future.wait([_loadStatus(), _loadRepository(showSpinner: false)]);
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

  /// Continues (or with [skip], skips a commit of) a stopped rebase.
  Future<bool> _continueRebase(String? message, {bool skip = false}) async {
    try {
      final outcome = skip
          ? await MergeActions.skipRebaseCommit(widget.path)
          : await MergeActions.continueRebase(widget.path, message);
      if (!mounted) return false;
      await Future.wait([_loadStatus(), _loadRepository(showSpinner: false)]);
      return outcome.result != 'conflicts';
    } on GitFfiException catch (e) {
      if (mounted) _showError(e.message);
      return false;
    }
  }

  Future<bool> _commit(String message) async {
    if (_mergeState?.isRebase ?? false) return _continueRebase(message);
    final result = await GitActions.commit(widget.path, message);
    if (!mounted) return false;
    if (result.isSuccess) {
      await Future.wait([_loadStatus(), _loadRepository(showSpinner: false)]);
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

    final result = await _controller.push();
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
    _setSection(RepoSection.files);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _codeViewKey.currentState?.openFile(absolutePath);
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _selectCommit(CommitEntry commit) async {
    if (_section == RepoSection.changes) {
      _lastSection = RepoSection.history;
      _controller.section = RepoSection.history;
    }
    setState(() {
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

    if (_section == RepoSection.report) {
      return ReportView(
        controller: _controller.report,
        onOpenCommit: _showCommit,
      );
    }
    if (_section == RepoSection.files) {
      return CodeView(
        key: _codeViewKey,
        onOpenCommit: (hunk) => _showCommitById(
          hunk.commitId!,
          summary: hunk.summary,
          author: hunk.author,
          email: hunk.email,
          time: hunk.time,
        ),
        repoPath: widget.path,
        rebasing: _mergeState?.isRebase ?? false,
        onLanguageChanged: widget.onLanguageChanged,
      );
    }
    return _buildGitView(context);
  }

  Widget _buildGitView(BuildContext context) {
    // Changes is its own full-width screen: file lists + diff + commit box.
    if (_isViewingChanges) {
      return WorkingChangesDetail(
        branchName: _controller.currentBranch,
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
        onRefresh: () => unawaited(_loadStatus()),
        mergeState: _mergeState,
        onResolveConflict: _resolveConflict,
        onAbortMerge: _abortMerge,
        onSkipRebaseCommit: () async {
          await _continueRebase(null, skip: true);
        },
        loadDiff: (entry, {required staged}) =>
            GitActions.workingDiff(widget.path, entry.path, staged: staged),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BranchSidebar(
          repoPath: widget.path,
          branches: _branches,
          width: _sidebarWidth,
          onChanged: _loadRepository,
          watchIntervalMinutes: _controller.watcher.intervalMinutes,
          onWatchIntervalChanged: _controller.watcher.setIntervalMinutes,
          onOpenInTerminal: widget.onOpenInTerminal,
          onMergeConflicts: () => _setSection(RepoSection.changes),
          isUpdatingCurrentBranch: _controller.isPulling,
          onUpdateCurrentBranch: () async {
            final result = await _controller.pull();
            if (mounted && !result.isSuccess) _showError(result.error!);
          },
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
          child: CommitDetail(
            commit: _selectedCommit,
            diffFiles: _diffFiles,
            isLoading: _isDiffLoading,
            error: _diffError,
            selectedFilePath: _selectedFilePath,
            onSelectFile: (path) => setState(() => _selectedFilePath = path),
            onOpenFile: _openFileInEditor,
          ),
        ),
      ],
    );
  }
}
