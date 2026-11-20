import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logs/action_log.dart';
import '../repo/git_actions.dart';
import '../repo/models.dart';

const String _onlyWhenCleanKey = 'branchi_watcher_only_when_clean';
const String _notifyKey = 'branchi_watcher_notify_new_commits';
const String _branchesKeyPrefix = 'branchi_watcher_branches_';

/// A notification raised by [runWatchedPull] when an automatic pull brought
/// in new commits (only while [WatcherPreferences.notifyOnNewCommits] is on).
@immutable
class WatcherNotification {
  const WatcherNotification({
    required this.repoPath,
    required this.branch,
    required this.newCommits,
  });

  final String repoPath;
  final String branch;
  final int newCommits;
}

/// Preferences of the branch watcher (auto-pull) edited in the settings
/// page's "Branch watcher" section:
///
/// * [onlyWhenClean] - skip an automatic pull while the working tree has
///   uncommitted changes (untracked files don't count). Global.
/// * [notifyOnNewCommits] - report pulls that brought in commits (action
///   log entry + [notifications]). Global.
/// * branches to pull - per repository; the set of local branch names that
///   each automatic pull fast-forwards. `null` (never configured) means just
///   the current branch, the watcher's original behaviour.
///
/// The interval itself stays in [BranchWatchStore] / [BranchWatcher].
class WatcherPreferences {
  WatcherPreferences._();

  static final ValueNotifier<bool> onlyWhenClean = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> notifyOnNewCommits =
      ValueNotifier<bool>(true);

  /// Fires for every automatic pull that brought in new commits while
  /// [notifyOnNewCommits] is on. A host widget with a [ScaffoldMessenger]
  /// can listen and show a SnackBar.
  static final StreamController<WatcherNotification> _notifications =
      StreamController<WatcherNotification>.broadcast();
  static Stream<WatcherNotification> get notifications =>
      _notifications.stream;

  /// When each repository was last pulled by [runWatchedPull].
  static final Map<String, DateTime> _lastPulledAt = {};

  static Future<void>? _loading;

  /// Loads the global toggles once; safe to call repeatedly.
  static Future<void> ensureLoaded() => _loading ??= _load();

  static Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    onlyWhenClean.value = prefs.getBool(_onlyWhenCleanKey) ?? true;
    notifyOnNewCommits.value = prefs.getBool(_notifyKey) ?? true;
  }

  static Future<void> setOnlyWhenClean(bool value) async {
    onlyWhenClean.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onlyWhenCleanKey, value);
  }

  static Future<void> setNotifyOnNewCommits(bool value) async {
    notifyOnNewCommits.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notifyKey, value);
  }

  /// The local branches to pull for [repoPath], or `null` when never
  /// configured (= the current branch only).
  static Future<Set<String>?> loadBranches(String repoPath) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_branchesKeyPrefix + repoPath);
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as List).cast<String>().toSet();
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveBranches(String repoPath, Set<String> branches) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _branchesKeyPrefix + repoPath,
      jsonEncode(branches.toList()..sort()),
    );
  }

  /// When [repoPath] was last pulled: the last [runWatchedPull] run, else the
  /// newest successful "update branch [branch]" entry in the action log.
  static DateTime? lastPulledAt(String repoPath, {String? branch}) {
    final recorded = _lastPulledAt[repoPath];
    if (recorded != null) return recorded;
    if (branch == null) return null;
    for (final entry in ActionLog.instance.entries) {
      if (entry.success && entry.action == 'update branch $branch') {
        return entry.timestamp;
      }
    }
    return null;
  }
}

/// Whether the working tree of [repoPath] has uncommitted changes
/// (staged or unstaged; untracked files are ignored).
Future<bool> hasUncommittedChanges(String repoPath) async {
  final entries = await GitActions.status(repoPath);
  return entries.any(
    (e) =>
        e.staged != null ||
        (e.unstaged != null && e.unstaged != FileChangeStatus.new_),
  );
}

/// One automatic pull, honouring the [WatcherPreferences]: meant as the
/// body of the [BranchWatcher]'s `onPull` callback, e.g. in
/// `RepoController._autoPull`:
///
/// ```dart
/// Future<void> _autoPull() => runWatchedPull(
///       repoPath: repoPath,
///       currentBranch: _currentBranch,
///       pullCurrent: _pull,
///     );
/// ```
///
/// Skips the pull while the tree is dirty (if [WatcherPreferences.
/// onlyWhenClean]), fast-forwards the other selected local branches, then
/// the current one via [pullCurrent] (when selected), and reports new
/// commits on the current branch (if [WatcherPreferences.
/// notifyOnNewCommits]).
Future<void> runWatchedPull({
  required String repoPath,
  required String? currentBranch,
  required Future<GitActionResult> Function() pullCurrent,
}) async {
  await WatcherPreferences.ensureLoaded();

  if (WatcherPreferences.onlyWhenClean.value) {
    try {
      if (await hasUncommittedChanges(repoPath)) {
        ActionLog.instance.record(
          'auto-pull skipped',
          success: true,
          detail: 'The working tree has uncommitted changes.',
        );
        return;
      }
    } catch (_) {
      // Status unavailable: fall through and let the pull report errors.
    }
  }

  final selected = await WatcherPreferences.loadBranches(repoPath);
  final pullHead = selected == null ||
      (currentBranch != null && selected.contains(currentBranch));

  if (selected != null) {
    for (final name in selected) {
      if (name == currentBranch) continue;
      await GitActions.updateBranch(repoPath, name, isRemote: false);
    }
  }

  if (pullHead && currentBranch != null) {
    final notify = WatcherPreferences.notifyOnNewCommits.value;
    String? before;
    if (notify) before = await _headId(repoPath);
    final result = await pullCurrent();
    if (notify && result.isSuccess && before != null) {
      final count = await _commitsSince(repoPath, before);
      if (count > 0) {
        ActionLog.instance.record(
          'auto-pull: $count new commit${count == 1 ? '' : 's'} on $currentBranch',
          success: true,
        );
        WatcherPreferences._notifications.add(
          WatcherNotification(
            repoPath: repoPath,
            branch: currentBranch,
            newCommits: count,
          ),
        );
      }
    }
  }
  WatcherPreferences._lastPulledAt[repoPath] = DateTime.now();
}

Future<String?> _headId(String repoPath) async {
  try {
    final log = await GitActions.log(repoPath, limit: 1);
    return log.isEmpty ? null : log.first.id;
  } catch (_) {
    return null;
  }
}

/// Commits reachable from HEAD that come after [oldHead] (capped at 200).
Future<int> _commitsSince(String repoPath, String oldHead) async {
  try {
    final log = await GitActions.log(repoPath, limit: 200);
    final index = log.indexWhere((c) => c.id == oldHead);
    return index < 0 ? log.length : index;
  } catch (_) {
    return 0;
  }
}
