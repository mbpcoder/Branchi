import 'package:shared_preferences/shared_preferences.dart';

/// The branch each repo's local branches are compared with in the sidebar
/// ("3 ahead · 12 behind main"). Null means the default branch.
class BranchBasePrefs {
  BranchBasePrefs._();

  static const _keyPrefix = 'branchi_branch_base_';

  static Future<String?> load(String repoPath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyPrefix + repoPath);
    } catch (_) {
      return null;
    }
  }

  /// Saves [branch] as the base for [repoPath]; null resets to the default.
  static Future<void> save(String repoPath, String? branch) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (branch == null) {
        await prefs.remove(_keyPrefix + repoPath);
      } else {
        await prefs.setString(_keyPrefix + repoPath, branch);
      }
    } catch (_) {
      // Applies until the next reload only.
    }
  }

  /// "origin/main" -> "main", for labels. Local names stay as they are.
  static String displayName(String base, Iterable<String> remoteNames) {
    for (final remote in remoteNames) {
      if (base.startsWith('$remote/')) return base.substring(remote.length + 1);
    }
    return base;
  }
}
