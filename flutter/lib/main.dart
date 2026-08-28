import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';
import 'package:xterm/xterm.dart';

import 'l10n/app_locale.dart';
import 'l10n/translations.dart';
import 'repo/git_actions.dart';
import 'repo/recent_repositories_store.dart';
import 'settings/settings_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS)) {
    await windowManager.ensureInitialized();
  }
  await AppLocale.load();
  runApp(const RustGitApp());
}

class RustGitApp extends StatelessWidget {
  const RustGitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppLocale.languageCode,
      builder: (context, languageCode, _) {
        return MaterialApp(
          title: 'RustGit',
          locale: Locale(languageCode),
          supportedLocales:
              supportedLanguages.map((lang) => Locale(lang.code)),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
            useMaterial3: true,
          ),
          home: const WelcomeScreen(),
        );
      },
    );
  }
}

class RepoTab {
  RepoTab({required this.id, required this.title, this.path});

  final int id;
  String title;
  String? path;
}

class TerminalSession {
  TerminalSession({
    required this.id,
    required this.title,
    required this.pty,
    required this.terminal,
  });

  final int id;
  String title;
  final Pty pty;
  final Terminal terminal;

  void dispose() {
    pty.kill();
  }
}

/// The shell to launch inside the embedded terminal.
String _defaultShell() {
  if (Platform.isWindows) {
    return Platform.environment['COMSPEC'] ?? 'powershell.exe';
  }
  return Platform.environment['SHELL'] ?? '/bin/bash';
}

/// Spawns a real shell in a pseudo-terminal and wires it up to an in-app
/// [Terminal], so the terminal panel runs inside the app itself rather than
/// opening a separate OS terminal window (which isn't available in headless
/// / containerized environments).
TerminalSession _spawnTerminalSession(int id, String title) {
  final pty = Pty.start(
    _defaultShell(),
    columns: 80,
    rows: 24,
    workingDirectory: Directory.current.path,
  );

  final terminal = Terminal(maxLines: 10000);
  terminal.onOutput = (data) => pty.write(const Utf8Encoder().convert(data));
  terminal.onResize = (width, height, pixelWidth, pixelHeight) {
    pty.resize(height, width);
  };

  pty.output
      .cast<List<int>>()
      .transform(const Utf8Decoder(allowMalformed: true))
      .listen(terminal.write);

  return TerminalSession(id: id, title: title, pty: pty, terminal: terminal);
}

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final List<RepoTab> _tabs = [RepoTab(id: 0, title: 'New Tab')];
  int _nextTabId = 1;
  int _activeTabIndex = 0;
  bool _isPinned = false;

  final List<TerminalSession> _terminalSessions = [];
  int _nextTerminalId = 0;
  int _activeTerminalIndex = 0;
  bool _isTerminalOpen = false;

  Future<void> _toggleTerminal() async {
    if (_isTerminalOpen) {
      setState(() => _isTerminalOpen = false);
      return;
    }
    if (_terminalSessions.isEmpty) {
      await _addTerminalTab();
    }
    setState(() => _isTerminalOpen = true);
  }

  Future<void> _addTerminalTab() async {
    final session = _spawnTerminalSession(
      _nextTerminalId,
      '${translate('terminal')} ${_nextTerminalId + 1}',
    );
    _nextTerminalId++;
    if (!mounted) {
      session.dispose();
      return;
    }
    setState(() {
      _terminalSessions.add(session);
      _activeTerminalIndex = _terminalSessions.length - 1;
    });
  }

  void _closeTerminalTab(int index) {
    final session = _terminalSessions[index];
    session.dispose();
    setState(() {
      _terminalSessions.removeAt(index);
      if (_terminalSessions.isEmpty) {
        _isTerminalOpen = false;
        _activeTerminalIndex = 0;
      } else if (_activeTerminalIndex >= _terminalSessions.length) {
        _activeTerminalIndex = _terminalSessions.length - 1;
      } else if (_activeTerminalIndex > index) {
        _activeTerminalIndex--;
      }
    });
  }

  @override
  void dispose() {
    for (final session in _terminalSessions) {
      session.dispose();
    }
    super.dispose();
  }

  void _addTab() {
    setState(() {
      _tabs.add(RepoTab(id: _nextTabId, title: 'New Tab'));
      _nextTabId++;
      _activeTabIndex = _tabs.length - 1;
    });
  }

  void _closeTab(int index) {
    if (_tabs.length == 1) return;
    setState(() {
      _tabs.removeAt(index);
      if (_activeTabIndex >= _tabs.length) {
        _activeTabIndex = _tabs.length - 1;
      } else if (_activeTabIndex > index) {
        _activeTabIndex--;
      }
    });
  }

  Future<void> _togglePin() async {
    final pinned = !_isPinned;
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      await windowManager.setAlwaysOnTop(pinned);
    }
    setState(() => _isPinned = pinned);
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const SettingsPage()),
    );
  }

  /// Attaches [path] to the currently active tab, e.g. after a repository
  /// is opened, created, or cloned from that tab's start form.
  void _setActiveTabRepository(String path) {
    setState(() {
      final tab = _tabs[_activeTabIndex];
      tab.path = path;
      tab.title = p.basename(path);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppLocale.languageCode,
      builder: (context, _, __) {
        return Scaffold(
          appBar: AppBar(
            title: Text(translate('app_title')),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(40),
              child: _TabBarRow(
                tabs: _tabs,
                activeIndex: _activeTabIndex,
                onSelect: (index) => setState(() => _activeTabIndex = index),
                onClose: _closeTab,
                onAddTab: _addTab,
              ),
            ),
            actions: [
              IconButton(
                tooltip: translate('settings'),
                icon: const Icon(Icons.settings),
                onPressed: _openSettings,
              ),
              IconButton(
                tooltip: _isPinned
                    ? translate('unpin_window')
                    : translate('pin_window'),
                icon: Icon(
                  _isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                ),
                onPressed: _togglePin,
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: _tabs[_activeTabIndex].path != null
                    ? _RepositoryOpenedPlaceholder(
                        path: _tabs[_activeTabIndex].path!,
                      )
                    : _WelcomeForm(
                        key: ValueKey(_tabs[_activeTabIndex].id),
                        onRepositoryOpened: _setActiveTabRepository,
                      ),
              ),
              if (_isTerminalOpen)
                _TerminalPanel(
                  sessions: _terminalSessions,
                  activeIndex: _activeTerminalIndex,
                  onSelect: (index) =>
                      setState(() => _activeTerminalIndex = index),
                  onClose: _closeTerminalTab,
                  onAddTab: _addTerminalTab,
                ),
              _BottomToolbar(
                isTerminalOpen: _isTerminalOpen,
                onToggleTerminal: _toggleTerminal,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BottomToolbar extends StatelessWidget {
  const _BottomToolbar({
    required this.isTerminalOpen,
    required this.onToggleTerminal,
  });

  final bool isTerminalOpen;
  final VoidCallback onToggleTerminal;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 32,
      color: colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          IconButton(
            iconSize: 18,
            tooltip: translate('terminal'),
            isSelected: isTerminalOpen,
            style: IconButton.styleFrom(
              padding: EdgeInsets.zero,
              backgroundColor:
                  isTerminalOpen ? colorScheme.surface : Colors.transparent,
            ),
            icon: const Icon(Icons.terminal),
            onPressed: onToggleTerminal,
          ),
        ],
      ),
    );
  }
}

class _TerminalPanel extends StatelessWidget {
  const _TerminalPanel({
    required this.sessions,
    required this.activeIndex,
    required this.onSelect,
    required this.onClose,
    required this.onAddTab,
  });

  final List<TerminalSession> sessions;
  final int activeIndex;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;
  final VoidCallback onAddTab;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 32,
            child: Row(
              children: [
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: sessions.length,
                    itemBuilder: (context, index) {
                      final session = sessions[index];
                      final isActive = index == activeIndex;
                      return InkWell(
                        onTap: () => onSelect(index),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: isActive
                                ? colorScheme.surfaceContainerHighest
                                : Colors.transparent,
                            border: Border(
                              right:
                                  BorderSide(color: colorScheme.outlineVariant),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                session.title,
                                style: TextStyle(
                                  fontWeight: isActive
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () => onClose(index),
                                child: const Icon(Icons.close, size: 16),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                IconButton(
                  tooltip: translate('new_tab'),
                  icon: const Icon(Icons.add),
                  onPressed: onAddTab,
                ),
              ],
            ),
          ),
          Expanded(
            child: sessions.isEmpty
                ? const SizedBox.shrink()
                : TerminalView(
                    key: ValueKey(sessions[activeIndex].id),
                    sessions[activeIndex].terminal,
                    autofocus: true,
                  ),
          ),
        ],
      ),
    );
  }
}

class _TabBarRow extends StatelessWidget {
  const _TabBarRow({
    required this.tabs,
    required this.activeIndex,
    required this.onSelect,
    required this.onClose,
    required this.onAddTab,
  });

  final List<RepoTab> tabs;
  final int activeIndex;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;
  final VoidCallback onAddTab;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 40,
      color: colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              itemBuilder: (context, index) {
                final tab = tabs[index];
                final isActive = index == activeIndex;
                return InkWell(
                  onTap: () => onSelect(index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isActive
                          ? colorScheme.surface
                          : Colors.transparent,
                      border: Border(
                        right: BorderSide(color: colorScheme.outlineVariant),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tab.title,
                          style: TextStyle(
                            fontWeight:
                                isActive ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () => onClose(index),
                          child: const Icon(Icons.close, size: 16),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            tooltip: translate('new_tab'),
            icon: const Icon(Icons.add),
            onPressed: onAddTab,
          ),
        ],
      ),
    );
  }
}

/// A minimal placeholder shown once a tab has a repository attached, until
/// an actual repository view (log, diff, branches, ...) is built.
class _RepositoryOpenedPlaceholder extends StatelessWidget {
  const _RepositoryOpenedPlaceholder({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open,
              size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(path, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// The "start page" shown as the content of the default tab and every new
/// tab: pick a local repository, browse recent ones, or clone a remote one.
class _WelcomeForm extends StatefulWidget {
  const _WelcomeForm({super.key, required this.onRepositoryOpened});

  final ValueChanged<String> onRepositoryOpened;

  @override
  State<_WelcomeForm> createState() => _WelcomeFormState();
}

class _WelcomeFormState extends State<_WelcomeForm> {
  List<String> _recentRepositories = [];
  bool _isBusy = false;

  final TextEditingController _sourceUrlController = TextEditingController();
  final TextEditingController _repoNameController = TextEditingController();
  final TextEditingController _destinationPathController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRecentRepositories();
  }

  Future<void> _loadRecentRepositories() async {
    final recent = await RecentRepositoriesStore.load();
    if (!mounted) return;
    setState(() => _recentRepositories = recent);
  }

  @override
  void dispose() {
    _sourceUrlController.dispose();
    _repoNameController.dispose();
    _destinationPathController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openRepository() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null) return;

    if (!GitActions.isGitRepository(path)) {
      _showMessage(translate('not_a_git_repository'));
      return;
    }

    await RecentRepositoriesStore.addOrPromote(path);
    widget.onRepositoryOpened(path);
  }

  Future<void> _newRepository() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null) return;

    setState(() => _isBusy = true);
    final result = await GitActions.init(path);
    if (!mounted) return;
    setState(() => _isBusy = false);

    if (!result.isSuccess) {
      _showMessage(result.error ?? translate('not_a_git_repository'));
      return;
    }

    await RecentRepositoriesStore.addOrPromote(path);
    _showMessage(translate('repository_created'));
    widget.onRepositoryOpened(path);
  }

  Future<void> _pickDestinationPath() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null) return;
    _destinationPathController.text = path;
  }

  Future<void> _openRecentRepository(String path) async {
    if (!GitActions.isGitRepository(path)) {
      _showMessage(translate('repository_no_longer_exists'));
      final updated = await RecentRepositoriesStore.remove(path);
      if (!mounted) return;
      setState(() => _recentRepositories = updated);
      return;
    }
    await RecentRepositoriesStore.addOrPromote(path);
    widget.onRepositoryOpened(path);
  }

  Future<void> _cloneRepository() async {
    final sourceUrl = _sourceUrlController.text.trim();
    final destinationPath = _destinationPathController.text.trim();

    if (sourceUrl.isEmpty) {
      _showMessage(translate('source_url_required'));
      return;
    }
    if (destinationPath.isEmpty) {
      _showMessage(translate('destination_path_required'));
      return;
    }

    final repoName = _repoNameController.text.trim().isNotEmpty
        ? _repoNameController.text.trim()
        : GitActions.repoNameFromUrl(sourceUrl);
    final targetDirectory = p.join(destinationPath, repoName);

    setState(() => _isBusy = true);
    final result = await GitActions.clone(
      sourceUrl: sourceUrl,
      destinationDirectory: targetDirectory,
    );
    if (!mounted) return;
    setState(() => _isBusy = false);

    if (!result.isSuccess) {
      _showMessage(result.error ?? translate('not_a_git_repository'));
      return;
    }

    await RecentRepositoriesStore.addOrPromote(targetDirectory);
    _showMessage(translate('repository_cloned'));
    widget.onRepositoryOpened(targetDirectory);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              translate('local_repositories'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: _isBusy ? null : _openRepository,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(translate('open_repository')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: _isBusy ? null : _newRepository,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(translate('new_repository')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Text(
              translate('recent_repositories'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (_recentRepositories.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  translate('no_recent_repositories'),
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              )
            else
              ...List.generate(_recentRepositories.length, (index) {
                final path = _recentRepositories[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: InkWell(
                    onTap: _isBusy ? null : () => _openRecentRepository(path),
                    child: Row(
                      children: [
                        Icon(
                          Icons.folder,
                          size: 20,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(path)),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 32),
            Text(
              translate('clone_repository'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _FormRow(
              label: translate('source_url'),
              child: TextField(
                controller: _sourceUrlController,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _FormRow(
              label: translate('repository_name'),
              child: TextField(
                controller: _repoNameController,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _FormRow(
              label: translate('destination_path'),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _destinationPathController,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _isBusy ? null : _pickDestinationPath,
                    child: const Text('...'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _isBusy ? null : _cloneRepository,
                child: _isBusy
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(translate('cloning')),
                        ],
                      )
                    : Text(translate('clone')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A label + input row used by the clone-repository form.
class _FormRow extends StatelessWidget {
  const _FormRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 140,
          child: Text(label),
        ),
        Expanded(child: child),
      ],
    );
  }
}
