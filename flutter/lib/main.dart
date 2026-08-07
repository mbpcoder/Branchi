import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import 'l10n/app_locale.dart';
import 'l10n/translations.dart';
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
  RepoTab({required this.id, required this.title});

  final int id;
  String title;
}

class TerminalSession {
  TerminalSession({required this.id, required this.title});

  final int id;
  String title;
  Process? process;
}

/// Launches the operating system's default terminal application.
///
/// There is no cross-platform API for this, so each platform's common
/// terminal launch mechanism is used. On Linux this tries a handful of
/// widely available terminal emulators until one succeeds.
Future<Process?> launchDefaultTerminal() async {
  if (kIsWeb) return null;
  try {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return await Process.start('open', ['-a', 'Terminal']);
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return await Process.start('cmd.exe', ['/c', 'start', 'cmd.exe']);
    }
    if (defaultTargetPlatform == TargetPlatform.linux) {
      const candidates = [
        'x-terminal-emulator',
        'gnome-terminal',
        'konsole',
        'xfce4-terminal',
        'xterm',
      ];
      for (final terminal in candidates) {
        try {
          return await Process.start(terminal, []);
        } on ProcessException {
          continue;
        }
      }
    }
  } catch (_) {
    return null;
  }
  return null;
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
    final session = TerminalSession(
      id: _nextTerminalId,
      title: '${translate('terminal')} ${_nextTerminalId + 1}',
    );
    _nextTerminalId++;
    session.process = await launchDefaultTerminal();
    if (!mounted) return;
    setState(() {
      _terminalSessions.add(session);
      _activeTerminalIndex = _terminalSessions.length - 1;
    });
  }

  void _closeTerminalTab(int index) {
    final session = _terminalSessions[index];
    session.process?.kill();
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
      session.process?.kill();
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
                child: Center(
                  child: Text(
                    '${translate('welcome')}\n(${_tabs[_activeTabIndex].title})',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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
            child: Center(
              child: Text(
                sessions.isEmpty
                    ? ''
                    : '${sessions[activeIndex].title}\n${translate('terminal_opened_externally')}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
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
