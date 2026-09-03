import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'translations.dart';

const String _prefsKey = 'branchi_language_code';
const String _defaultLanguageCode = 'en';

/// Global, app-wide selected language.
///
/// Kept as a simple [ValueNotifier] rather than a full localization
/// framework so the rest of the app can just call `translate('key')` and
/// rebuild via [ValueListenableBuilder] when the user changes languages in
/// the settings page.
class AppLocale {
  AppLocale._();

  static final ValueNotifier<String> languageCode =
      ValueNotifier<String>(_defaultLanguageCode);

  static bool get isRtl => rtlLanguageCodes.contains(languageCode.value);

  static Locale get locale => Locale(languageCode.value);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved != null && translations.containsKey(saved)) {
      languageCode.value = saved;
    }
  }

  static Future<void> set(String code) async {
    if (!translations.containsKey(code)) return;
    languageCode.value = code;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, code);
  }
}

/// Looks up [key] in the currently selected language, falling back to
/// English and then to the key itself if no translation is found.
String translate(String key) {
  final code = AppLocale.languageCode.value;
  return translations[code]?[key] ??
      translations[_defaultLanguageCode]?[key] ??
      key;
}
