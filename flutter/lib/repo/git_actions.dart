import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import 'git_ffi.dart';

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

  static const _missingLibraryError =
      'rustgit_core native library not found. Build it with '
      '`cargo build -p rustgit-core` and rerun the app.';
}
