import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _prefsKey = 'rustgit_theme_mode';
const String _defaultThemeMode = 'system';

/// Global, app-wide selected theme mode (light/dark/system).
///
/// Mirrors [AppLocale]: a simple [ValueNotifier] persisted via
/// [SharedPreferences] so the rest of the app can rebuild via
/// [ValueListenableBuilder] when the user toggles the theme.
class AppTheme {
  AppTheme._();

  static final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey) ?? _defaultThemeMode;
    themeMode.value = _decode(saved);
  }

  static Future<void> toggle() async {
    final isDark = themeMode.value == ThemeMode.dark ||
        (themeMode.value == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    await set(isDark ? ThemeMode.light : ThemeMode.dark);
  }

  static Future<void> set(ThemeMode mode) async {
    themeMode.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, _encode(mode));
  }

  static String _encode(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  static ThemeMode _decode(String value) => switch (value) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}
