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
            return MaterialApp(
              title: 'Branchi',
              locale: Locale(languageCode),
              supportedLocales:
                  supportedLanguages.map((lang) => Locale(lang.code)),
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              themeMode: themeMode,
              theme: ThemeData(
                colorScheme:
                    ColorScheme.fromSeed(seedColor: Colors.deepOrange),
                useMaterial3: true,
              ),
              darkTheme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.deepOrange,
                  brightness: Brightness.dark,
                ),
                useMaterial3: true,
              ),
              home: const WelcomeScreen(),
            );
          },
        );
      },
    );
  }
}
