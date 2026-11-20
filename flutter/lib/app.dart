import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/app_locale.dart';
import 'l10n/translations.dart';
import 'theme/app_theme.dart';
import 'welcome/welcome_screen.dart';

class BranchiApp extends StatelessWidget {
  const BranchiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppLocale.languageCode,
      builder: (context, languageCode, _) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: AppTheme.themeMode,
          builder: (context, themeMode, _) {
            return ValueListenableBuilder<Color>(
              valueListenable: AppTheme.accent,
              builder: (context, accent, _) {
                return MaterialApp(
                  title: 'Branchi',
                  debugShowCheckedModeBanner: false,
                  locale: Locale(languageCode),
                  supportedLocales:
                      supportedLanguages.map((lang) => Locale(lang.code)),
                  localizationsDelegates: const [
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  themeMode: themeMode,
                  theme: AppTheme.light(accent),
                  darkTheme: AppTheme.dark(accent),
                  home: const WelcomeScreen(),
                );
              },
            );
          },
        );
      },
    );
  }
}
