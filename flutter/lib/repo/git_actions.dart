import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../logs/action_log.dart';
import 'git_ffi.dart';
import '../report/report_data.dart';
import 'models.dart';

/// Result of a git action: whether it succeeded and, on failure, a message
/// suitable for showing to the user.
class GitActionResult {
  const GitActionResult.success() : error = null;
  const GitActionResult.failure(this.error);

  final String? error;
  bool get isSuccess => error == null;
}

/// Git operations for the start-page actions (open/init/clone), backed by
/// the Rust core (`core/src/git.rs`, via `core/src/ffi.rs`) rather than
/// shelling out to a `git` binary.
class GitActions {
  GitActions._();

  static bool isGitRepository(String path) {
    final ffi = GitFfi.instanceOrNull;
    if (ffi != null) return ffi.isRepository(path);

    // Fallback if the native library hasn't been built yet: a plain
    // filesystem check is still correct, just less thorough than opening
    // the repo (it won't catch a corrupt .git directory).
    return Directory(p.join(path, '.git')).existsSync() ||
        File(p.join(path, '.git')).existsSync();
  }

  static Future<GitActionResult> init(String path) async {
    final ffi = GitFfi.instanceOrNull;
    if (ffi == null) return const GitActionResult.failure(_missingLibraryError);

    final error = ffi.init(path);
    ActionLog.instance.record(
      'init $path',
      success: error == null,
      detail: error,
    );
    return error == null
        ? const GitActionResult.success()
        : GitActionResult.failure(error);
  }

  /// Clones on a background isolate: a clone can take a while (network,
  /// large history) and the FFI call blocks its calling isolate for the
  /// duration, so running it on the UI isolate would freeze the app.
  static Future<GitActionResult> clone({
    required String sourceUrl,
    required String destinationDirectory,
  }) async {
    if (GitFfi.instanceOrNull == null) {
      return const GitActionResult.failure(_missingLibraryError);
    }

    final error = await Isolate.run(
      () => GitFfi.instanceOrNull!.clone(sourceUrl, destinationDirectory),
    );
    ActionLog.instance.record(
      'clone $sourceUrl -> $destinationDirectory',
      success: error == null,
      detail: error,
    );
    return error == null
        ? const GitActionResult.success()
        : GitActionResult.failure(error);
  }

  /// Derives a repository directory name from a clone URL, e.g.
  /// `https://github.com/user/repo.git` -> `repo`.
  static String repoNameFromUrl(String url) {
    var name = url.trim();
    if (name.endsWith('/')) {
      name = name.substring(0, name.length - 1);
    }
    name = name.split('/').last.split('\\').last;
    if (name.endsWith('.git')) {
      name = name.substring(0, name.length - 4);
    }
    return name;
  }

  /// Commit history reachable from HEAD, newest first, at most [limit]
  /// entries. Runs on a background isolate since it walks repo history.
  static Future<List<CommitEntry>> log(String path, {int limit = 200}) async {
    final ffi = GitFfi.instanceOrNull;
    if (ffi == null) throw StateError(_missingLibraryErrorWithPaths());

    final raw = await Isolate.run(() => ffi.log(path, limit));
    return raw
        .cast<Map<String, dynamic>>()
        .map(CommitEntry.fromJson)
        .toList();
  }

  /// The Report section's data for [period]: its commits with line
  /// counts, the previous period's commit count, every author's span and
  /// the local branches compared with the base branch. Runs on a
  /// background isolate since it diffs every commit in the period.
  static Future<ReportData> report(String path, ReportPeriod period) async {
    final ffi = GitFfi.instanceOrNull;
    if (ffi == null) throw StateError(_missingLibraryErrorWithPaths());

    final since = period.sinceSeconds;
    final until = period.untilSeconds;
    final previousSince = period.previousSinceSeconds;
    final (stats, branchReport) = await Isolate.run(
      () => (
        ffi.commitStats(path, since, until, previousSince),
        ffi.branchReport(path),
      ),
    );
    final authors = (stats['authors'] as List<dynamic>)
        .map((a) => AuthorSpan.fromJson(a as Map<String, dynamic>));
    return ReportData(
      period: period,
      commits: (stats['commits'] as List<dynamic>)
          .map((c) => ReportCommit.fromJson(c as Map<String, dynamic>))
          .toList(),
      previousCount: period.isAll ? 0 : stats['previous_count'] as int,
      authors: {for (final a in authors) a.key: a},
      baseBranch: branchReport['base'] as String?,
      branches: (branchReport['branches'] as List<dynamic>)
          .map((b) => BranchStat.fromJson(b as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Local and remote-tracking branches.
  static Future<List<BranchEntry>> branches(String path) async {
    final ffi = GitFfi.instanceOrNull;
    if (ffi == null) throw StateError(_missingLibraryErrorWithPaths());

    final raw = await Isolate.run(() => ffi.branches(path));
    return raw
        .cast<Map<String, dynamic>>()
        .map(BranchEntry.fromJson)
        .toList();
  }

  /// The file-level diff of [commitId] against its first parent.
  static Future<List<DiffFileEntry>> commitDiff(
    String path,
    String commitId,
  ) async {
    final ffi = GitFfi.instanceOrNull;
    if (ffi == null) throw StateError(_missingLibraryErrorWithPaths());

    final raw = await Isolate.run(() => ffi.commitDiff(path, commitId));
    return raw
        .cast<Map<String, dynamic>>()
        .map(DiffFileEntry.fromJson)
        .toList();
  }

  /// Unified-diff patch of the uncommitted changes to [filePath]: staged
  /// (index vs HEAD) or unstaged (working tree vs index).
  static Future<String> workingDiff(
    String path,
    String filePath, {
    required bool staged,
  }) async {
    final ffi = GitFfi.instanceOrNull;
    if (ffi == null) throw StateError(_missingLibraryErrorWithPaths());

    return Isolate.run(
      () => ffi.workingDiff(path, filePath, staged: staged),
    );
  }

  /// Checks out local branch [name].
  static Future<GitActionResult> checkoutBranch(String path, String name) async {
    final ffi = GitFfi.instanceOrNull;
    if (ffi == null) return const GitActionResult.failure(_missingLibraryError);

    final error = await Isolate.run(() => ffi.checkoutBranch(path, name));
    ActionLog.instance.record(
      'checkout $name',
      success: error == null,
      detail: error,
    );
    return error == null
        ? const GitActionResult.success()
        : GitActionResult.failure(error);
  }

  /// Creates local branch [name], tracking remote branch [from] (e.g.
  /// `origin/feature`) if given, or starting from HEAD otherwise.
  static Future<GitActionResult> createBranch(
    String path,
    String name, {
    String? from,
  }) async {
    final ffi = GitFfi.instanceOrNull;
    if (ffi == null) return const GitActionResult.failure(_missingLibraryError);

    final error =
        await Isolate.run(() => ffi.createBranch(path, name, from: from));
    ActionLog.instance.record(
      from == null ? 'branch $name' : 'branch $name (from $from)',
      success: error == null,
      detail: error,
    );
    return error == null
        ? const GitActionResult.success()
        : GitActionResult.failure(error);
  }

  /// Deletes branch [name] ([isRemote] selects a remote-tracking branch).
  static Future<GitActionResult> deleteBranch(
    String path,
    String name, {
    required bool isRemote,
  }) async {
    final ffi = GitFfi.instanceOrNull;
    if (ffi == null) return const GitActionResult.failure(_missingLibraryError);

    final error = await Isolate.run(
      () => ffi.deleteBranch(path, name, isRemote: isRemote),
    );
    ActionLog.instance.record(
      'delete ${isRemote ? 'remote ' : ''}branch $name',
      success: error == null,
      detail: error,
    );
    return error == null
        ? const GitActionResult.success()
        : GitActionResult.failure(error);
  }

  /// Updates branch [name] from its remote ([isRemote] selects a
  /// remote-tracking branch, which is just re-fetched; a local branch is
  /// fast-forwarded to its upstream).
  static Future<GitActionResult> updateBranch(
    String path,
    String name, {
    required bool isRemote,
  }) async {
    final ffi = GitFfi.instanceOrNull;
    if (ffi == null) return const GitActionResult.failure(_missingLibraryError);

    // A local branch's counts are what the fast-forward brought in.
    final (error, stats) = await Isolate.run(() {
      final ref = 'refs/heads/$name';
      final before = isRemote ? null : _tryResolve(ffi, path, ref);
      final error = ffi.updateBranch(path, name, isRemote: isRemote);
      final stats = error == null && before != null
          ? _tryStats(ffi, path, before, ref)
          : null;
      return (error, stats);
    });
    ActionLog.instance.record(
      'update ${isRemote ? 'remote ' : ''}branch $name',
      success: error == null,
      detail: error,
      stats: stats,
    );
    return error == null
        ? const GitActionResult.success()
        : GitActionResult.failure(error);
  }

  /// Fetches every configured remote (equivalent to `git fetch --all`),
  /// updating remote-tracking branches without touching local ones.
  static Future<GitActionResult> fetch(String path) async {
    final ffi = GitFfi.instanceOrNull;
    if (ffi == null) return const GitActionResult.failure(_missingLibraryError);

    List<RemoteEntry> remoteList;
    try {
      remoteList = await remotes(path);
    } catch (e) {
      final error = e.toString();
      ActionLog.instance.record('fetch', success: false, detail: error);
      return GitActionResult.failure(error);
    }
    if (remoteList.isEmpty) {
      const error = 'No remotes configured.';
      ActionLog.instance.record('fetch', success: false, detail: error);
      return const GitActionResult.failure(error);
    }

    final errors = <String>[];
    for (final remote in remoteList) {
      // The core fetches the remote named by the first path segment of a
      // remote-tracking branch name, so `<remote>/HEAD` fetches all of it.
      final remoteBranch = '${remote.name}/HEAD';
      final error = await Isolate.run(
        () => ffi.updateBranch(path, remoteBranch, isRemote: true),
      );
      if (error != null) errors.add(error);
    }
    final error = errors.isEmpty ? null : errors.join('\n');
    ActionLog.instance.record(
      remoteList.length == 1 ? 'fetch ${remoteList.first.name}' : 'fetch all',
      success: error == null,
      detail: error,
    );
    return error == null
        ? const GitActionResult.success()
        : GitActionResult.failure(error);
  }

  /// Working-tree/index status of every changed file.
  static Future<List<StatusEntry>> status(String path) async {
    final ffi = GitFfi.instanceOrNull;
    if (ffi == null) throw StateError(_missingLibraryErrorWithPaths());

    final raw = await Isolate.run(() => ffi.status(path));
    return raw
        .cast<Map<String, dynamic>>()
        .map(StatusEntry.fromJson)
        .toList();
  }

  /// Stages [filePath] (equivalent to `git add <filePath>`).
  static Future<GitActionResult> stage(String path, String filePath) async {
    final ffi = GitFfi.instanceOrNull;
    if (ffi == null) return const GitActionResult.failure(_missingLibraryError);

    final error = await Isolate.run(() => ffi.stage(path, filePath));
    ActionLog.instance.record(
      'stage $filePath',
      success: error == null,
      detail: error,
    );
    return error == null
        ? const GitActionResult.success()
        : GitActionResult.failure(error);
  }

  /// Unstages [filePath], leaving the working tree unchanged.
  static Future<GitActionResult> unstage(String path, String filePath) async {
    final ffi = GitFfi.instanceOrNull;
    if (ffi == null) return const GitActionResult.failure(_missingLibraryError);

    final error = await Isolate.run(() => ffi.unstage(path, filePath));
    ActionLog.instance.record(
      'unstage $filePath',
      success: error == null,
      detail: error,
    );
    return error == null
        ? const GitActionResult.success()
        : GitActionResult.failure(error);
  }

  /// Discards working-tree changes to [filePath].
  static Future<GitActionResult> revertFile(
    String path,
    String filePath,
  ) async {
    final ffi = GitFfi.instanceOrNull;
    if (ffi == null) return const GitActionResult.failure(_missingLibraryError);

    final error = await Isolate.run(() => ffi.revertFile(path, filePath));
    ActionLog.instance.record(
      'revert $filePath',
      success: error == null,
      detail: error,
    );
    return error == null
        ? const GitActionResult.success()
        : GitActionResult.failure(error);
  }

  /// Commits the current index with [message], using the repository's
  /// configured `user.name`/`user.email`.
  static Future<GitActionResult> commit(String path, String message) async {
    final ffi = GitFfi.instanceOrNull;
    if (ffi == null) return const GitActionResult.failure(_missingLibraryError);

    String? error;
    ActionStats? stats;
    try {
      stats = await Isolate.run(() {
        final before = _tryResolve(ffi, path, 'HEAD');
        ffi.commit(path, message);
        return _tryStats(ffi, path, before, 'HEAD', withCommits: false);
      });
    } on GitFfiException catch (e) {
      error = e.message;
    } catch (e) {
      error = e.toString();
    }
    ActionLog.instance.record(
      'commit',
      success: error == null,
      detail: error,
      stats: stats,
    );
    return error == null
        ? const GitActionResult.success()
        : GitActionResult.failure(error);
  }

  /// Pushes local branch [name] to its upstream remote.
  static Future<GitActionResult> push(String path, String name) async {
    final ffi = GitFfi.instanceOrNull;
    if (ffi == null) return const GitActionResult.failure(_missingLibraryError);

    // Counted before pushing: what the upstream doesn't have yet.
    final (error, stats) = await Isolate.run(() {
      final stats = _tryStats(ffi, path, '$name@{upstream}', 'refs/heads/$name');
      return (ffi.push(path, name), stats);
    });
    ActionLog.instance.record(
      'push $name',
      success: error == null,
      detail: error,
      stats: stats,
    );
    return error == null
        ? const GitActionResult.success()
        : GitActionResult.failure(error);
  }

  /// [rev]'s commit id, or null if it doesn't resolve or can't be read.
  static String? _tryResolve(GitFfi ffi, String path, String rev) {
    try {
      return ffi.resolveCommit(path, rev);
    } catch (_) {
      return null;
    }
  }

  /// Activity-panel counts for [from]..[to]; null if they can't be worked
  /// out, so a failure here never fails the action itself.
  static ActionStats? _tryStats(
    GitFfi ffi,
    String path,
    String? from,
    String to, {
    bool withCommits = true,
  }) {
    try {
      return ActionStats.fromJson(
        ffi.changeStats(path, from, to),
        withCommits: withCommits,
      );
    } catch (_) {
      return null;
    }
  }

  /// This repository's configured remotes.
  static Future<List<RemoteEntry>> remotes(String path) async {
    final ffi = GitFfi.instanceOrNull;
    if (ffi == null) throw StateError(_missingLibraryErrorWithPaths());

    final raw = await Isolate.run(() => ffi.remotes(path));
    return raw
        .cast<Map<String, dynamic>>()
        .map(RemoteEntry.fromJson)
        .toList();
  }

  /// Adds a new remote [name] pointing at [url].
  static Future<GitActionResult> addRemote(
    String path,
    String name,
    String url,
  ) async {
    final ffi = GitFfi.instanceOrNull;
    if (ffi == null) return const GitActionResult.failure(_missingLibraryError);

    final error = await Isolate.run(() => ffi.addRemote(path, name, url));
    ActionLog.instance.record(
      'add remote $name -> $url',
      success: error == null,
      detail: error,
    );
    return error == null
        ? const GitActionResult.success()
        : GitActionResult.failure(error);
  }

  /// Changes the URL of existing remote [name].
  static Future<GitActionResult> setRemoteUrl(
    String path,
    String name,
    String url,
  ) async {
    final ffi = GitFfi.instanceOrNull;
    if (ffi == null) return const GitActionResult.failure(_missingLibraryError);

    final error = await Isolate.run(() => ffi.setRemoteUrl(path, name, url));
    ActionLog.instance.record(
      'set remote $name url -> $url',
      success: error == null,
      detail: error,
    );
    return error == null
        ? const GitActionResult.success()
        : GitActionResult.failure(error);
  }

  /// Removes remote [name].
  static Future<GitActionResult> removeRemote(String path, String name) async {
    final ffi = GitFfi.instanceOrNull;
    if (ffi == null) return const GitActionResult.failure(_missingLibraryError);

    final error = await Isolate.run(() => ffi.removeRemote(path, name));
    ActionLog.instance.record(
      'remove remote $name',
      success: error == null,
      detail: error,
    );
    return error == null
        ? const GitActionResult.success()
        : GitActionResult.failure(error);
  }

  /// The `user.name`/`user.email` identity from git's global config.
  static Future<GlobalGitIdentity> globalGitConfig() async {
    final ffi = GitFfi.instanceOrNull;
    if (ffi == null) throw StateError(_missingLibraryErrorWithPaths());

    final raw = await Isolate.run(() => ffi.globalConfigGet());
    return GlobalGitIdentity(
      name: raw['name'] as String?,
      email: raw['email'] as String?,
    );
  }

  /// Writes [name]/[email] into git's global config. Pass an empty string
  /// to leave a field unset.
  static Future<GitActionResult> setGlobalGitConfig(
    String name,
    String email,
  ) async {
    final ffi = GitFfi.instanceOrNull;
    if (ffi == null) return const GitActionResult.failure(_missingLibraryError);

    final error = await Isolate.run(() => ffi.globalConfigSet(name, email));
    ActionLog.instance.record(
      'set global git config',
      success: error == null,
      detail: error,
    );
    return error == null
        ? const GitActionResult.success()
        : GitActionResult.failure(error);
  }

  static const _missingLibraryError =
      'branchi_core native library not found. Build it with '
      '`cargo build -p branchi-core` and rerun the app.';

  /// [_missingLibraryError] plus the exact paths that were tried, so a
  /// failure report says where to look instead of just "not found".
  static String _missingLibraryErrorWithPaths() {
    final tried = GitFfi.lastAttemptedPaths;
    if (tried.isEmpty) return _missingLibraryError;
    return '$_missingLibraryError\nTried:\n${tried.map((p) => '  $p').join('\n')}';
  }
}
