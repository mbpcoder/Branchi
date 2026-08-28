import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import '../l10n/app_locale.dart';
import '../l10n/translations.dart';
import '../models/repo_tab.dart';
import '../repo/repository_view.dart';
import '../settings/settings_page.dart';
import '../terminal/terminal_panel.dart';
import '../terminal/terminal_session.dart';
import '../widgets/bottom_toolbar.dart';
import '../widgets/tab_bar_row.dart';
import 'welcome_form.dart';

/// The app's main screen: the tab bar, the active tab's content (start
/// page or an opened repository), and the terminal panel.
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
    final session = spawnTerminalSession(
      _nextTerminalId,
      '${translate('terminal')} ${_nextTerminalId + 1}',
      workingDirectory: _tabs[_activeTabIndex].path,
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
              child: TabBarRow(
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
                    ? RepositoryView(
                        key: ValueKey(_tabs[_activeTabIndex].path),
                        path: _tabs[_activeTabIndex].path!,
                      )
                    : WelcomeForm(
                        key: ValueKey(_tabs[_activeTabIndex].id),
                        onRepositoryOpened: _setActiveTabRepository,
                      ),
              ),
              if (_isTerminalOpen)
                TerminalPanel(
                  sessions: _terminalSessions,
                  activeIndex: _activeTerminalIndex,
                  onSelect: (index) =>
                      setState(() => _activeTerminalIndex = index),
                  onClose: _closeTerminalTab,
                  onAddTab: _addTerminalTab,
                ),
              BottomToolbar(
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
