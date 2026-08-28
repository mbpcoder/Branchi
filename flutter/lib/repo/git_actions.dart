import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../logs/action_log.dart';
import 'git_ffi.dart';
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

    final error = await Isolate.run(
      () => ffi.updateBranch(path, name, isRemote: isRemote),
    );
    ActionLog.instance.record(
      'update ${isRemote ? 'remote ' : ''}branch $name',
      success: error == null,
      detail: error,
    );
    return error == null
        ? const GitActionResult.success()
        : GitActionResult.failure(error);
  }

  static const _missingLibraryError =
      'rustgit_core native library not found. Build it with '
      '`cargo build -p rustgit-core` and rerun the app.';

  /// [_missingLibraryError] plus the exact paths that were tried, so a
  /// failure report says where to look instead of just "not found".
  static String _missingLibraryErrorWithPaths() {
    final tried = GitFfi.lastAttemptedPaths;
    if (tried.isEmpty) return _missingLibraryError;
    return '$_missingLibraryError\nTried:\n${tried.map((p) => '  $p').join('\n')}';
  }
}
