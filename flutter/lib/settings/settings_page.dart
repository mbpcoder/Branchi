import 'package:flutter/material.dart';

import '../l10n/app_calendar.dart';
import '../l10n/app_locale.dart';
import '../l10n/translations.dart';
import '../logs/action_log.dart';
import '../repo/git_actions.dart';
import '../repo/repo_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/form_row.dart';
import 'branch_watcher_section.dart';
import 'open_repo_lookup.dart';
import 'settings_route.dart';
import 'settings_widgets.dart';
import 'shell_preferences.dart';

/// The sections listed in the settings page's left navigation, with the
/// ids accepted by [SettingsPage.initialSection].
enum SettingsSection {
  appearance('appearance', 'settings_appearance'),
  gitIdentity('git_identity', 'settings_git_identity'),
  terminal('terminal', 'terminal'),
  branchWatcher(kSettingsSectionBranchWatcher, 'branch_watcher'),
  logs('logs', 'logs');

  const SettingsSection(this.id, this.labelKey);

  final String id;
  final String labelKey;

  static SettingsSection fromId(String? id) => SettingsSection.values
      .firstWhere((s) => s.id == id, orElse: () => SettingsSection.appearance);
}

/// Settings page opened from the gear icon in the top toolbar: a 52px
/// header with a back chevron, a 220px section list and the selected
/// section's content (max 720px wide).
///
/// Sections: appearance (theme, accent, language), git identity (global
/// user.name/user.email), terminal (shells), branch watcher (auto-pull for
/// the open repository + watcher preferences) and logs.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.initialSection});

  /// Id of the section to select when the page opens, e.g.
  /// [kSettingsSectionBranchWatcher] (`'branch_watcher'`); see
  /// [SettingsSection]. `null` opens Appearance. Open the page via
  /// [openSettings] rather than pushing it directly.
  final String? initialSection;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late SettingsSection _section = SettingsSection.fromId(widget.initialSection);
  RepoController? _repo;

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  bool _loadingGitConfig = true;
  bool _savingGitConfig = false;

  @override
  void initState() {
    super.initState();
    _loadGlobalGitConfig();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final repo = findOpenRepoController(context);
      if (repo != null) setState(() => _repo = repo);
    });
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
    ScaffoldMessenger.of(context).showSnackBar(
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
        content: SizedBox(
          width: 400,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FormRow(
                  label: translate('shell_name'),
                  child: TextFormField(
                    controller: nameController,
                    autofocus: true,
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? translate('shell_name_required')
                        : null,
                  ),
                ),
                const SizedBox(height: 14),
                FormRow(
                  label: translate('shell_executable'),
                  child: TextFormField(
                    controller: executableController,
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? translate('shell_executable_required')
                        : null,
                  ),
                ),
              ],
            ),
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
      builder: (context, _, _) {
        final b = context.branchi;
        return Scaffold(
          backgroundColor: b.bg,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(b),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _nav(b),
                    Expanded(
                      child: SingleChildScrollView(
                        key: PageStorageKey(_section),
                        padding: const EdgeInsets.symmetric(
                          vertical: 40,
                          horizontal: 64,
                        ),
                        child: Align(
                          alignment: AlignmentDirectional.topStart,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 592),
                            child: _content(),
                          ),
                        ),
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

  Widget _header(BranchiColors b) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(border: Border(bottom: b.hairline)),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              tooltip: translate('back'),
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.chevron_left, size: 18),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            translate('settings'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _nav(BranchiColors b) {
    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      decoration: BoxDecoration(border: BorderDirectional(end: b.hairline)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final section in SettingsSection.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: _NavItem(
                label: translate(section.labelKey),
                selected: section == _section,
                onTap: () => setState(() => _section = section),
              ),
            ),
        ],
      ),
    );
  }

  Widget _content() {
    return switch (_section) {
      SettingsSection.appearance => const _AppearanceSection(),
      SettingsSection.gitIdentity => _gitIdentity(),
      SettingsSection.terminal => _terminal(),
      SettingsSection.branchWatcher => BranchWatcherSection(controller: _repo),
      SettingsSection.logs => const _LogsSection(),
    };
  }

  Widget _gitIdentity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionTitle(
          title: translate('settings_git_identity'),
          subtitle: translate('global_git_config_description'),
        ),
        const SizedBox(height: 40),
        if (_loadingGitConfig)
          const Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else ...[
          FormRow(
            label: translate('git_user_name'),
            child: TextField(controller: _nameController),
          ),
          const SizedBox(height: 18),
          FormRow(
            label: translate('git_user_email'),
            child: TextField(controller: _emailController),
          ),
          const SizedBox(height: 24),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton(
              onPressed: _savingGitConfig ? null : _saveGlobalGitConfig,
              child: Text(translate('save')),
            ),
          ),
        ],
      ],
    );
  }

  Widget _terminal() {
    final b = context.branchi;
    Widget shellRow(ShellDefinition shell, {Widget? trailing}) => Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: trailing == null ? 10 : 4,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(shell.name),
                const SizedBox(height: 2),
                Text(
                  shell.executable,
                  style: b.mono(fontSize: 12, color: b.muted),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionTitle(
          title: translate('terminal'),
          subtitle: translate('shells_description'),
        ),
        ValueListenableBuilder<List<ShellDefinition>>(
          valueListenable: ShellPreferences.detected,
          builder: (context, detected, _) {
            if (detected.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 40),
              child: SettingsGroup(
                label: translate('detected_shells'),
                child: BorderedList(
                  children: [for (final shell in detected) shellRow(shell)],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 36),
        SettingsGroup(
          label: translate('custom_shells'),
          trailing: OutlinedButton.icon(
            onPressed: () => _addShell(context),
            icon: const Icon(Icons.add, size: 14),
            label: Text(translate('add_shell')),
          ),
          child: ValueListenableBuilder<List<ShellDefinition>>(
            valueListenable: ShellPreferences.custom,
            builder: (context, custom, _) {
              if (custom.isEmpty) {
                return Text(
                  translate('no_shells_configured'),
                  style: TextStyle(color: b.muted),
                );
              }
              return BorderedList(
                children: [
                  for (var i = 0; i < custom.length; i++)
                    shellRow(
                      custom[i],
                      trailing: IconButton(
                        tooltip: translate('remove'),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => ShellPreferences.removeAt(i),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? b.hover : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          hoverColor: b.hover,
          splashColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? b.fg : b.muted,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Theme cards, accent swatches and the language picker.
class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection();

  static const List<String> _accentNameKeys = [
    'accent_blue',
    'accent_green',
    'accent_orange',
    'accent_purple',
    'accent_gray',
  ];

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final lightBg = BranchiColors.light().bg;
    final darkBg = BranchiColors.dark().bg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionTitle(
          title: translate('settings_appearance'),
          subtitle: translate('settings_appearance_description'),
        ),
        const SizedBox(height: 40),
        SettingsGroup(
          label: translate('theme'),
          child: ValueListenableBuilder<ThemeMode>(
            valueListenable: AppTheme.themeMode,
            builder: (context, mode, _) => Row(
              children: [
                for (final (i, option) in [
                  (
                    ThemeMode.system,
                    'theme_system',
                    LinearGradient(
                      colors: [lightBg, lightBg, darkBg, darkBg],
                      stops: const [0, 0.5, 0.5, 1],
                    ),
                  ),
                  (
                    ThemeMode.light,
                    'theme_light',
                    LinearGradient(colors: [lightBg, lightBg]),
                  ),
                  (
                    ThemeMode.dark,
                    'theme_dark',
                    LinearGradient(colors: [darkBg, darkBg]),
                  ),
                ].indexed) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(
                    child: _ThemeCard(
                      label: translate(option.$2),
                      swatch: option.$3,
                      selected: mode == option.$1,
                      onTap: () => AppTheme.set(option.$1),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 40),
        SettingsGroup(
          label: translate('accent_color'),
          child: ValueListenableBuilder<Color>(
            valueListenable: AppTheme.accent,
            builder: (context, accent, _) => Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final (i, color) in kAccentOptions.indexed)
                  _AccentSwatch(
                    color: color,
                    label: i < _accentNameKeys.length
                        ? translate(_accentNameKeys[i])
                        : '',
                    selected: color.toARGB32() == accent.toARGB32(),
                    ringGap: b.bg,
                    onTap: () => AppTheme.setAccent(color),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 40),
        HairlineList(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Expanded(child: Text(translate('language'))),
                  _LanguageDropdown(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Expanded(child: Text(translate('calendar'))),
                  const _CalendarDropdown(),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.label,
    required this.swatch,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Gradient swatch;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: selected ? b.accent : b.line),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          hoverColor: b.hover,
          splashColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: swatch,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.fromBorderSide(b.hairline),
                  ),
                ),
                const SizedBox(height: 10),
                ExcludeSemantics(child: Text(label)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.color,
    required this.label,
    required this.selected,
    required this.ringGap,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool selected;
  final Color ringGap;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: selected
                      ? [
                          BoxShadow(color: color, spreadRadius: 4),
                          BoxShadow(color: ringGap, spreadRadius: 2),
                        ]
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageDropdown extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.fromBorderSide(b.hairline),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: AppLocale.languageCode.value,
          isDense: true,
          focusColor: Colors.transparent,
          dropdownColor: b.bg,
          borderRadius: BorderRadius.circular(8),
          icon: Icon(Icons.keyboard_arrow_down, size: 14, color: b.muted),
          style: TextStyle(fontSize: 13, color: b.fg),
          items: [
            for (final lang in supportedLanguages)
              DropdownMenuItem(value: lang.code, child: Text(lang.name)),
          ],
          onChanged: (code) {
            if (code != null) AppLocale.set(code);
          },
        ),
      ),
    );
  }
}

/// Calendar dates are shown in: automatic (by language), Gregorian or
/// Jalali.
class _CalendarDropdown extends StatelessWidget {
  const _CalendarDropdown();

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return ValueListenableBuilder<CalendarPreference>(
      valueListenable: AppCalendarSettings.preference,
      builder: (context, value, _) => Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border.fromBorderSide(b.hairline),
          borderRadius: BorderRadius.circular(6),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<CalendarPreference>(
            value: value,
            isDense: true,
            focusColor: Colors.transparent,
            dropdownColor: b.bg,
            borderRadius: BorderRadius.circular(8),
            icon: Icon(Icons.keyboard_arrow_down, size: 14, color: b.muted),
            style: TextStyle(fontSize: 13, color: b.fg),
            items: [
              for (final pref in CalendarPreference.values)
                DropdownMenuItem(
                  value: pref,
                  child: Text(translate('calendar_${pref.name}')),
                ),
            ],
            onChanged: (pref) {
              if (pref != null) AppCalendarSettings.set(pref);
            },
          ),
        ),
      ),
    );
  }
}

/// Recent git actions (the same log the logs panel shows) and a clear
/// button.
class _LogsSection extends StatelessWidget {
  const _LogsSection();

  static String _time(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return ListenableBuilder(
      listenable: ActionLog.instance,
      builder: (context, _) {
        final entries = ActionLog.instance.entries;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsSectionTitle(
              title: translate('logs'),
              subtitle: translate('settings_logs_description'),
            ),
            const SizedBox(height: 40),
            SettingsGroup(
              label: translate(
                'settings_logs_count',
              ).replaceAll('{n}', '${entries.length}'),
              trailing: OutlinedButton(
                onPressed: entries.isEmpty ? null : ActionLog.instance.clear,
                child: Text(translate('clear_logs')),
              ),
              child: entries.isEmpty
                  ? Text(
                      translate('no_logged_actions'),
                      style: TextStyle(color: b.muted),
                    )
                  : BorderedList(
                      children: [
                        for (final entry in entries.take(50))
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 5),
                                  child: Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: entry.success ? b.add : b.del,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  _time(entry.timestamp),
                                  style: b.mono(fontSize: 12, color: b.muted),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(entry.action),
                                      if (entry.detail != null)
                                        Text(
                                          entry.detail!,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: b.muted,
                                          ),
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}
