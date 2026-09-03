import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const String _prefsKey = 'branchi_app_state';

/// A single persisted tab: an unattached start-page tab has [path] == null.
/// Terminal state is per-tab, so restoring a terminal spawns it in that
/// tab's own repo directory rather than wherever the app process started.
class PersistedTab {
  const PersistedTab({
    required this.title,
    this.path,
    this.terminalTitles = const [],
    this.activeTerminalIndex = 0,
    this.isTerminalOpen = false,
  });

  final String title;
  final String? path;
  final List<String> terminalTitles;
  final int activeTerminalIndex;
  final bool isTerminalOpen;

  Map<String, dynamic> toJson() => {
        'title': title,
        'path': path,
        'terminalTitles': terminalTitles,
        'activeTerminalIndex': activeTerminalIndex,
        'isTerminalOpen': isTerminalOpen,
      };

  factory PersistedTab.fromJson(Map<String, dynamic> json) {
    final terminalTitlesJson =
        json['terminalTitles'] as List<dynamic>? ?? const [];
    return PersistedTab(
      title: json['title'] as String? ?? 'New Tab',
      path: json['path'] as String?,
      terminalTitles: terminalTitlesJson.map((t) => t as String).toList(),
      activeTerminalIndex: json['activeTerminalIndex'] as int? ?? 0,
      isTerminalOpen: json['isTerminalOpen'] as bool? ?? false,
    );
  }
}

/// The full window state we restore on the next launch: open tabs (and
/// which one was active), each with its own terminal tabs.
class AppSessionState {
  const AppSessionState({required this.tabs, required this.activeTabIndex});

  final List<PersistedTab> tabs;
  final int activeTabIndex;

  Map<String, dynamic> toJson() => {
        'tabs': tabs.map((t) => t.toJson()).toList(),
        'activeTabIndex': activeTabIndex,
      };

  factory AppSessionState.fromJson(Map<String, dynamic> json) {
    final tabsJson = json['tabs'] as List<dynamic>? ?? const [];
    return AppSessionState(
      tabs: tabsJson
          .map((t) => PersistedTab.fromJson(t as Map<String, dynamic>))
          .toList(),
      activeTabIndex: json['activeTabIndex'] as int? ?? 0,
    );
  }
}

/// Persists the window's last-known state (open tabs, each tab's terminal
/// tabs, and which tab was active) so the app can reopen exactly where the
/// user left it, the same way [AppLocale] persists the selected language.
class AppStateStore {
  AppStateStore._();

  static Future<AppSessionState?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return null;
    try {
      return AppSessionState.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(AppSessionState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(state.toJson()));
  }
}
