import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const String _prefsKey = 'rustgit_app_state';

/// A single persisted tab: an unattached start-page tab has [path] == null.
class PersistedTab {
  const PersistedTab({required this.title, this.path});

  final String title;
  final String? path;

  Map<String, dynamic> toJson() => {'title': title, 'path': path};

  factory PersistedTab.fromJson(Map<String, dynamic> json) => PersistedTab(
        title: json['title'] as String? ?? 'New Tab',
        path: json['path'] as String?,
      );
}

/// The full window state we restore on the next launch: open tabs (and
/// which one was active), plus how many terminal tabs were open (and
/// whether the terminal panel itself was visible).
class AppSessionState {
  const AppSessionState({
    required this.tabs,
    required this.activeTabIndex,
    required this.terminalTitles,
    required this.activeTerminalIndex,
    required this.isTerminalOpen,
  });

  final List<PersistedTab> tabs;
  final int activeTabIndex;
  final List<String> terminalTitles;
  final int activeTerminalIndex;
  final bool isTerminalOpen;

  Map<String, dynamic> toJson() => {
        'tabs': tabs.map((t) => t.toJson()).toList(),
        'activeTabIndex': activeTabIndex,
        'terminalTitles': terminalTitles,
        'activeTerminalIndex': activeTerminalIndex,
        'isTerminalOpen': isTerminalOpen,
      };

  factory AppSessionState.fromJson(Map<String, dynamic> json) {
    final tabsJson = json['tabs'] as List<dynamic>? ?? const [];
    final terminalTitlesJson =
        json['terminalTitles'] as List<dynamic>? ?? const [];
    return AppSessionState(
      tabs: tabsJson
          .map((t) => PersistedTab.fromJson(t as Map<String, dynamic>))
          .toList(),
      activeTabIndex: json['activeTabIndex'] as int? ?? 0,
      terminalTitles: terminalTitlesJson.map((t) => t as String).toList(),
      activeTerminalIndex: json['activeTerminalIndex'] as int? ?? 0,
      isTerminalOpen: json['isTerminalOpen'] as bool? ?? false,
    );
  }
}

/// Persists the window's last-known state (open tabs, active tab/terminal,
/// whether the terminal panel was open) so the app can reopen exactly where
/// the user left it, the same way [AppLocale] persists the selected
/// language.
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
