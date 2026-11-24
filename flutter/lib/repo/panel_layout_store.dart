import 'package:shared_preferences/shared_preferences.dart';

const String _sidebarWidthKey = 'branchi_panel_sidebar_width';
const String _commitListWidthKey = 'branchi_panel_commit_list_width';
const String _historyFilesAsTreeKey = 'branchi_history_files_as_tree';

/// Persists the user-adjusted widths of the branch sidebar and commit list
/// columns in [RepositoryView], and whether History lists changed files as
/// a directory tree, the same way [AppLocale] persists the selected
/// language, so the layout is restored the next time the app opens.
class PanelLayoutStore {
  PanelLayoutStore._();

  static Future<double?> loadSidebarWidth() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_sidebarWidthKey);
  }

  static Future<double?> loadCommitListWidth() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_commitListWidthKey);
  }

  static Future<void> saveSidebarWidth(double width) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_sidebarWidthKey, width);
  }

  static Future<void> saveCommitListWidth(double width) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_commitListWidthKey, width);
  }

  /// Whether History groups changed files by directory; null if never set.
  static Future<bool?> loadHistoryFilesAsTree() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_historyFilesAsTreeKey);
  }

  static Future<void> saveHistoryFilesAsTree(bool asTree) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_historyFilesAsTreeKey, asTree);
  }
}
