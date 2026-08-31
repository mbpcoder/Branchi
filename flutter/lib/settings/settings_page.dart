import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../l10n/translations.dart';
import '../repo/git_actions.dart';
import 'shell_preferences.dart';

/// Settings page opened from the gear icon in the top toolbar.
///
/// Exposes the language picker, the list of shells available to the
/// terminal panel, and the global git identity (user.name/user.email).
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  bool _loadingGitConfig = true;
  bool _savingGitConfig = false;

  @override
  void initState() {
    super.initState();
    _loadGlobalGitConfig();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadGlobalGitConfig() async {
    try {
      final identity = await GitActions.globalGitConfig();
      if (!mounted) return;
      setState(() {
        _nameController.text = identity.name ?? '';
        _emailController.text = identity.email ?? '';
        _loadingGitConfig = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingGitConfig = false);
    }
  }

  Future<void> _saveGlobalGitConfig() async {
    setState(() => _savingGitConfig = true);
    final result = await GitActions.setGlobalGitConfig(
      _nameController.text.trim(),
      _emailController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _savingGitConfig = false);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(result.isSuccess ? translate('saved') : result.error!),
      ),
    );
  }

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
                valueListenable: ShellPreferences.detected,
                builder: (context, detected, _) {
                  if (detected.isEmpty) return const SizedBox.shrink();
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            translate('detected_shells'),
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                      ),
                      for (final shell in detected)
                        ListTile(
                          leading: const Icon(Icons.terminal),
                          title: Text(shell.name),
                          subtitle: Text(shell.executable),
                        ),
                    ],
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    translate('custom_shells'),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ),
              ValueListenableBuilder<List<ShellDefinition>>(
                valueListenable: ShellPreferences.custom,
                builder: (context, custom, _) {
                  if (custom.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(translate('no_shells_configured')),
                    );
                  }
                  return Column(
                    children: [
                      for (var i = 0; i < custom.length; i++)
                        ListTile(
                          leading: const Icon(Icons.terminal),
                          title: Text(custom[i].name),
                          subtitle: Text(custom[i].executable),
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
              const Divider(height: 32),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  translate('global_git_config'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  translate('global_git_config_description'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (_loadingGitConfig)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    children: [
                      TextField(
                        controller: _nameController,
                        decoration:
                            InputDecoration(labelText: translate('git_user_name')),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _emailController,
                        decoration: InputDecoration(
                          labelText: translate('git_user_email'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: FilledButton(
                          onPressed:
                              _savingGitConfig ? null : _saveGlobalGitConfig,
                          child: Text(translate('save')),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
