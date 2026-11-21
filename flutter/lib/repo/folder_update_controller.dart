import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'git_actions.dart';

/// Where one repository is in a folder update run.
enum FolderRepoStatus {
  /// Not part of a run yet (before the first run, or after Stop).
  idle,
  waiting,
  updating,
  updated,
  upToDate,
  skipped,
  failed,
}

/// One git repository found directly inside the folder.
class FolderRepo {
  FolderRepo(this.path);

  final String path;
  String get name => p.basename(path);

  /// Current branch; `null` while loading or when HEAD is detached.
  String? branch;
  bool isDetached = false;

  FolderRepoStatus status = FolderRepoStatus.idle;

  /// Translation key for the detail column (e.g. why it was skipped).
  String? detailKey;

  /// Extra detail: the new-commit count or a raw error message.
  String? detail;
}

/// Finds the git repositories one level inside [folderPath] and updates
/// each one's current branch, fast-forward only. Owned by the tab, so a
/// run keeps going (and its results stay) while another tab is active.
class FolderUpdateController extends ChangeNotifier {
  FolderUpdateController(this.folderPath) {
    scan();
  }

  final String folderPath;

  /// How many repositories are updated at the same time.
  static const int _parallelism = 3;

  /// Enough history to count the new commits of a typical update.
  static const int _logLimit = 500;

  List<FolderRepo> repos = [];
  bool isScanning = false;
  String? scanError;
  bool isRunning = false;
  bool _stopRequested = false;
  DateTime? lastRunAt;
  bool _disposed = false;

  int countOf(FolderRepoStatus status) =>
      repos.where((r) => r.status == status).length;

  int get doneCount => repos
      .where(
        (r) => const {
          FolderRepoStatus.updated,
          FolderRepoStatus.upToDate,
          FolderRepoStatus.skipped,
          FolderRepoStatus.failed,
        }.contains(r.status),
      )
      .length;

  /// Lists the repositories in the folder (not recursive) and loads their
  /// current branches.
  Future<void> scan() async {
    if (isRunning) return;
    isScanning = true;
    scanError = null;
    _notify();

    final found = <FolderRepo>[];
    try {
      final entries = Directory(folderPath).listSync(followLinks: false)
        ..sort(
          (a, b) => p
              .basename(a.path)
              .toLowerCase()
              .compareTo(p.basename(b.path).toLowerCase()),
        );
      for (final entry in entries) {
        if (entry is! Directory) continue;
        if (p.basename(entry.path).startsWith('.')) continue;
        if (GitActions.isGitRepository(entry.path)) {
          found.add(FolderRepo(entry.path));
        }
      }
    } catch (e) {
      scanError = e.toString();
    }

    if (_disposed) return;
    repos = found;
    isScanning = false;
    _notify();

    for (final repo in found) {
      await _loadBranch(repo);
      if (_disposed) return;
      _notify();
    }
  }

  Future<void> _loadBranch(FolderRepo repo) async {
    try {
      final branches = await GitActions.branches(repo.path);
      final head = branches.where((b) => b.isHead && !b.isRemote);
      repo.isDetached = head.isEmpty;
      repo.branch = head.isEmpty ? null : head.first.name;
    } catch (_) {
      // Branch is shown for information only; the run reports real errors.
    }
  }

  /// Updates every repository, [_parallelism] at a time.
  Future<void> updateAll() async {
    if (isRunning || isScanning || repos.isEmpty) return;
    isRunning = true;
    _stopRequested = false;
    for (final repo in repos) {
      repo
        ..status = FolderRepoStatus.waiting
        ..detailKey = null
        ..detail = null;
    }
    _notify();

    var next = 0;
    Future<void> worker() async {
      while (!_stopRequested && !_disposed && next < repos.length) {
        final repo = repos[next++];
        repo.status = FolderRepoStatus.updating;
        _notify();
        await _updateOne(repo);
        _notify();
      }
    }

    await Future.wait([for (var i = 0; i < _parallelism; i++) worker()]);
    if (_disposed) return;

    for (final repo in repos) {
      if (repo.status == FolderRepoStatus.waiting) {
        repo.status = FolderRepoStatus.idle;
      }
    }
    isRunning = false;
    lastRunAt = DateTime.now();
    _notify();
  }

  /// Stops starting new repositories; ones already updating finish.
  void stop() {
    if (!isRunning) return;
    _stopRequested = true;
    _notify();
  }

  Future<void> _updateOne(FolderRepo repo) async {
    void skip(String key) {
      repo
        ..status = FolderRepoStatus.skipped
        ..detailKey = key;
    }

    try {
      await _loadBranch(repo);
      final branch = repo.branch;
      if (branch == null) {
        skip('folder_update_detached');
        return;
      }

      // The core's fast-forward does a forced checkout, which would
      // overwrite local edits, so any change at all means hands off.
      final status = await GitActions.status(repo.path);
      if (status.isNotEmpty) {
        skip('folder_update_uncommitted');
        return;
      }

      final before = await GitActions.log(repo.path, limit: 1);
      final beforeId = before.isEmpty ? null : before.first.id;

      final result = await GitActions.updateBranch(
        repo.path,
        branch,
        isRemote: false,
      );
      if (!result.isSuccess) {
        final error = result.error!;
        if (error.contains('has diverged')) {
          skip('folder_update_diverged');
        } else if (error.contains('has no upstream')) {
          skip('folder_update_no_upstream');
        } else {
          repo
            ..status = FolderRepoStatus.failed
            ..detail = error.split('\n').first;
        }
        return;
      }

      final after = await GitActions.log(repo.path, limit: _logLimit);
      if (after.isEmpty || after.first.id == beforeId) {
        repo.status = FolderRepoStatus.upToDate;
        return;
      }
      final index = after.indexWhere((c) => c.id == beforeId);
      repo
        ..status = FolderRepoStatus.updated
        ..detailKey = 'folder_update_new_commits'
        ..detail = index < 0 ? '$_logLimit+' : '$index';
    } catch (e) {
      repo
        ..status = FolderRepoStatus.failed
        ..detail = e.toString().split('\n').first;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopRequested = true;
    super.dispose();
  }
}
