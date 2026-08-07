import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../l10n/translations.dart';

/// Settings page opened from the gear icon in the top toolbar.
///
/// For now this only exposes the language picker, but it's the natural
/// place to grow other app-wide preferences later.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppLocale.languageCode,
      builder: (context, currentCode, _) {
        return Scaffold(
          appBar: AppBar(title: Text(translate('settings'))),
          body: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  translate('language'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final lang in supportedLanguages)
                RadioListTile<String>(
                  title: Text(lang.name),
                  value: lang.code,
                  groupValue: currentCode,
                  onChanged: (code) {
                    if (code != null) {
                      AppLocale.set(code);
                    }
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}
