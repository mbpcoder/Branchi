import 'dart:io';

import 'package:path/path.dart' as p;

/// Result of a git command-line action: whether it succeeded and, on
/// failure, a message suitable for showing to the user.
class GitActionResult {
  const GitActionResult.success() : error = null;
  const GitActionResult.failure(this.error);

  final String? error;
  bool get isSuccess => error == null;
}

/// Thin wrapper around the system `git` binary.
///
/// The Rust core (`core/src/git.rs`) doesn't have a Flutter bridge wired
/// up yet, so the UI shells out to `git` directly for now, the same way a
/// terminal user would.
class GitActions {
  GitActions._();

  static bool isGitRepository(String path) {
    final dir = Directory(p.join(path, '.git'));
    final file = File(p.join(path, '.git'));
    return dir.existsSync() || file.existsSync();
  }

  static Future<GitActionResult> init(String path) async {
    try {
      final result = await Process.run('git', ['init', path]);
      if (result.exitCode != 0) {
        return GitActionResult.failure(result.stderr.toString().trim());
      }
      return const GitActionResult.success();
    } on ProcessException catch (e) {
      return GitActionResult.failure(e.message);
    }
  }

  static Future<GitActionResult> clone({
    required String sourceUrl,
    required String destinationDirectory,
  }) async {
    try {
      final result = await Process.run(
        'git',
        ['clone', sourceUrl, destinationDirectory],
      );
      if (result.exitCode != 0) {
        return GitActionResult.failure(result.stderr.toString().trim());
      }
      return const GitActionResult.success();
    } on ProcessException catch (e) {
      return GitActionResult.failure(e.message);
    }
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
}
