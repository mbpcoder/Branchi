import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../l10n/translations.dart';
import 'shell_preferences.dart';

/// Settings page opened from the gear icon in the top toolbar.
///
/// Exposes the language picker and the list of shells available to the
/// terminal panel.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> _addShell(BuildContext context) async {
    final nameController = TextEditingController();
    final executableController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final shell = await showDialog<ShellDefinition>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(translate('add_shell')),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: InputDecoration(labelText: translate('shell_name')),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? translate('shell_name_required')
                    : null,
              ),
              TextFormField(
                controller: executableController,
                decoration:
                    InputDecoration(labelText: translate('shell_executable')),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? translate('shell_executable_required')
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(translate('cancel')),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.of(context).pop(
                ShellDefinition(
                  name: nameController.text.trim(),
                  executable: executableController.text.trim(),
                ),
              );
            },
            child: Text(translate('add')),
          ),
        ],
      ),
    );

    if (shell != null) {
      await ShellPreferences.add(shell);
    }
  }

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
              const Divider(height: 32),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  translate('shells'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  translate('shells_description'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              ValueListenableBuilder<List<ShellDefinition>>(
                valueListenable: ShellPreferences.shells,
                builder: (context, shells, _) {
                  if (shells.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(translate('no_shells_configured')),
                    );
                  }
                  return Column(
                    children: [
                      for (var i = 0; i < shells.length; i++)
                        ListTile(
                          title: Text(shells[i].name),
                          subtitle: Text(shells[i].executable),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => ShellPreferences.removeAt(i),
                          ),
                        ),
                    ],
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: OutlinedButton.icon(
                  onPressed: () => _addShell(context),
                  icon: const Icon(Icons.add),
                  label: Text(translate('add_shell')),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
