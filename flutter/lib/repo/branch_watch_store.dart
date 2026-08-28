import 'package:shared_preferences/shared_preferences.dart';

const String _intervalMinutesKey = 'rustgit_branch_watch_interval_minutes';

/// Persists the selected auto-refresh interval for the branches column's
/// watch feature, the same way [PanelLayoutStore] persists layout, so the
/// choice survives app and repo reopening. `null`/absent means disabled.
class BranchWatchStore {
  BranchWatchStore._();

  static Future<int?> loadIntervalMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_intervalMinutesKey);
  }

  static Future<void> saveIntervalMinutes(int? minutes) async {
    final prefs = await SharedPreferences.getInstance();
    if (minutes == null) {
      await prefs.remove(_intervalMinutesKey);
    } else {
      await prefs.setInt(_intervalMinutesKey, minutes);
    }
  }
}
