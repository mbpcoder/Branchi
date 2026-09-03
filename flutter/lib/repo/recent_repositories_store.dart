import 'package:shared_preferences/shared_preferences.dart';

const String _prefsKey = 'branchi_recent_repositories';
const int _maxEntries = 10;

/// Persists the list of recently opened/cloned repository paths, most
/// recent first, the same way [AppLocale] persists the selected language.
class RecentRepositoriesStore {
  RecentRepositoriesStore._();

  static Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_prefsKey) ?? const [];
  }

  /// Moves [path] to the front of the persisted list (adding it if it
  /// wasn't already there) and returns the updated list.
  static Future<List<String>> addOrPromote(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_prefsKey) ?? const [];
    final updated = [path, ...current.where((p) => p != path)];
    final trimmed = updated.take(_maxEntries).toList();
    await prefs.setStringList(_prefsKey, trimmed);
    return trimmed;
  }

  /// Drops [path] from the persisted list (e.g. because it no longer
  /// exists on disk) and returns the updated list.
  static Future<List<String>> remove(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_prefsKey) ?? const [];
    final updated = current.where((p) => p != path).toList();
    await prefs.setStringList(_prefsKey, updated);
    return updated;
  }
}
