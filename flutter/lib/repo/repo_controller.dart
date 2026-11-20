import 'dart:async';

import 'package:flutter/foundation.dart';

import 'branch_watcher.dart';
import 'git_actions.dart';
import 'models.dart';

/// The three top-level sections of an opened repository, switched from the
/// segmented control in the top bar.
enum RepoSection {
  /// Branches + commit log + commit detail.
  history,

  /// Working-tree changes (stage / commit).
  changes,

  /// File tree + code editor.
  files,
}

/// Per-repository-tab state shared between the window's top bar and the
/// [RepositoryView]: the active [section], branch info and changed-file
/// count (pushed in by the view after it loads), the [watcher]
/// (auto-pull), and the remote actions (fetch / pull / push).
///
/// Owned by [RepoTab] and lives as long as the tab is bound to [repoPath],
/// so auto-pull keeps running while another tab is active.
class RepoController extends ChangeNotifier {
  RepoController(this.repoPath) {
    watcher = BranchWatcher(repoPath: repoPath, onPull: _autoPull);
  }

  final String repoPath;

  late final BranchWatcher watcher;

  final StreamController<void> _repositoryChanged =
      StreamController<void>.broadcast();

  /// Fires after a fetch / pull / push / checkout run from outside the
  /// view (top bar, auto-pull), so the [RepositoryView] reloads.
  Stream<void> get repositoryChanged => _repositoryChanged.stream;

  RepoSection _section = RepoSection.history;
  RepoSection get section => _section;
  set section(RepoSection value) {
    if (value == _section) return;
    _section = value;
    notifyListeners();
  }

  String? _currentBranch;
  List<BranchEntry> _branches = const [];
  int _changesCount = 0;

  /// The current (HEAD) local branch, or `null` (detached / not loaded).
  String? get currentBranch => _currentBranch;

  /// All branches (local and remote-tracking).
  List<BranchEntry> get branches => _branches;

  /// Number of changed files in the working tree / index.
  int get changesCount => _changesCount;

  bool _isFetching = false;
  bool _isPulling = false;
  bool _isPushing = false;

  bool get isFetching => _isFetching;

  /// True during a manual or automatic pull.
  bool get isPulling => _isPulling;
  bool get isPushing => _isPushing;
  bool get isBusy => _isFetching || _isPulling || _isPushing;

  bool _disposed = false;

  /// Called by [RepositoryView] whenever it (re)loads branches.
  void updateBranchInfo(String? headBranch, List<BranchEntry> branches) {
    _currentBranch = headBranch;
    _branches = branches;
    _notify();
  }

  /// Called by [RepositoryView] whenever it (re)loads the status.
  void updateChangesCount(int count) {
    if (count == _changesCount) return;
    _changesCount = count;
    _notify();
  }

  Future<GitActionResult> fetch() async {
    if (_isFetching) return const GitActionResult.success();
    _isFetching = true;
    _notify();
    try {
      return await GitActions.fetch(repoPath);
    } finally {
      _isFetching = false;
      _notify();
      _emitChanged();
    }
  }

  /// Fast-forwards the current branch to its upstream (fetching first).
  Future<GitActionResult> pull() async {
    final result = await _pull();
    if (result.isSuccess) watcher.resetCountdown();
    return result;
  }

  Future<GitActionResult> push() async {
    if (_isPushing) return const GitActionResult.success();
    final branch = _currentBranch;
    if (branch == null) {
      return const GitActionResult.failure('No current branch to push.');
    }
    _isPushing = true;
    _notify();
    try {
      return await GitActions.push(repoPath, branch);
    } finally {
      _isPushing = false;
      _notify();
      _emitChanged();
    }
  }

  Future<GitActionResult> checkout(String branchName) async {
    final result = await GitActions.checkoutBranch(repoPath, branchName);
    _emitChanged();
    return result;
  }

  Future<void> _autoPull() async {
    await _pull();
  }

  Future<GitActionResult> _pull() async {
    if (_isPulling) return const GitActionResult.success();
    final branch = _currentBranch;
    if (branch == null) {
      return const GitActionResult.failure('No current branch to pull.');
    }
    _isPulling = true;
    _notify();
    try {
      return await GitActions.updateBranch(repoPath, branch, isRemote: false);
    } finally {
      _isPulling = false;
      _notify();
      _emitChanged();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _emitChanged() {
    if (!_disposed) _repositoryChanged.add(null);
  }

  @override
  void dispose() {
    _disposed = true;
    watcher.dispose();
    _repositoryChanged.close();
    super.dispose();
  }
}
