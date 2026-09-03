import 'package:shared_preferences/shared_preferences.dart';

const String _keyPrefix = 'branchi_branch_watch_interval_minutes_';

/// Persists the selected auto-refresh interval for the branches column's
/// watch feature, scoped per repository path so each repo remembers its own
/// setting independently, the same way [AppLocale] persists the selected
/// language. `null`/absent means disabled.
class BranchWatchStore {
  BranchWatchStore._();

  static Future<int?> loadIntervalMinutes(String repoPath) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyPrefix + repoPath);
  }

  static Future<void> saveIntervalMinutes(String repoPath, int? minutes) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keyPrefix + repoPath;
    if (minutes == null) {
      await prefs.remove(key);
    } else {
      await prefs.setInt(key, minutes);
    }
  }
}
