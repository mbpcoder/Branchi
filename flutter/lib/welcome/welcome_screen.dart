import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import '../app_state_store.dart';
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

  @override
  void initState() {
    super.initState();
    _restoreState();
  }

  /// Reopens the tabs and each tab's terminal tabs that were open the last
  /// time the app was closed, so relaunching the app picks up where the
  /// user left off instead of always starting from a single blank tab.
  /// Each terminal is respawned in its own tab's repo directory, so the
  /// terminal panel keeps following the repo it belongs to.
  Future<void> _restoreState() async {
    final saved = await AppStateStore.load();
    if (saved == null || !mounted) return;

    List<RepoTab> restoredTabs;
    if (saved.tabs.isEmpty) {
      restoredTabs = [RepoTab(id: 0, title: 'New Tab')];
    } else {
      restoredTabs = [];
      for (var i = 0; i < saved.tabs.length; i++) {
        final persisted = saved.tabs[i];
        final tab = RepoTab(id: i, title: persisted.title, path: persisted.path);
        tab.terminalSessions.addAll([
          for (var j = 0; j < persisted.terminalTitles.length; j++)
            spawnTerminalSession(
              j,
              persisted.terminalTitles[j],
              workingDirectory: tab.path,
            ),
        ]);
        tab.nextTerminalId = tab.terminalSessions.length;
        tab.isTerminalOpen =
            persisted.isTerminalOpen && tab.terminalSessions.isNotEmpty;
        tab.activeTerminalIndex = tab.terminalSessions.isEmpty
            ? 0
            : persisted.activeTerminalIndex
                .clamp(0, tab.terminalSessions.length - 1);
        restoredTabs.add(tab);
      }
    }

    if (!mounted) {
      for (final tab in restoredTabs) {
        for (final session in tab.terminalSessions) {
          session.dispose();
        }
      }
      return;
    }

    setState(() {
      _tabs
        ..clear()
        ..addAll(restoredTabs);
      _nextTabId = restoredTabs.length;
      _activeTabIndex =
          saved.activeTabIndex.clamp(0, restoredTabs.length - 1);
    });
  }

  void _saveState() {
    AppStateStore.save(
      AppSessionState(
        tabs: [
          for (final tab in _tabs)
            PersistedTab(
              title: tab.title,
              path: tab.path,
              terminalTitles: [
                for (final session in tab.terminalSessions) session.title,
              ],
              activeTerminalIndex: tab.activeTerminalIndex,
              isTerminalOpen: tab.isTerminalOpen,
            ),
        ],
        activeTabIndex: _activeTabIndex,
      ),
    );
  }

  Future<void> _toggleTerminal() async {
    final tab = _tabs[_activeTabIndex];
    if (tab.isTerminalOpen) {
      setState(() => tab.isTerminalOpen = false);
      _saveState();
      return;
    }
    if (tab.terminalSessions.isEmpty) {
      await _addTerminalTab();
    }
    setState(() => tab.isTerminalOpen = true);
    _saveState();
  }

  Future<void> _addTerminalTab() async {
    final tab = _tabs[_activeTabIndex];
    final session = spawnTerminalSession(
      tab.nextTerminalId,
      '${translate('terminal')} ${tab.nextTerminalId + 1}',
      workingDirectory: tab.path,
    );
    tab.nextTerminalId++;
    if (!mounted) {
      session.dispose();
      return;
    }
    setState(() {
      tab.terminalSessions.add(session);
      tab.activeTerminalIndex = tab.terminalSessions.length - 1;
    });
    _saveState();
  }

  void _closeTerminalTab(int index) {
    final tab = _tabs[_activeTabIndex];
    final session = tab.terminalSessions[index];
    session.dispose();
    setState(() {
      tab.terminalSessions.removeAt(index);
      if (tab.terminalSessions.isEmpty) {
        tab.isTerminalOpen = false;
        tab.activeTerminalIndex = 0;
      } else if (tab.activeTerminalIndex >= tab.terminalSessions.length) {
        tab.activeTerminalIndex = tab.terminalSessions.length - 1;
      } else if (tab.activeTerminalIndex > index) {
        tab.activeTerminalIndex--;
      }
    });
    _saveState();
  }

  @override
  void dispose() {
    for (final tab in _tabs) {
      for (final session in tab.terminalSessions) {
        session.dispose();
      }
    }
    super.dispose();
  }

  void _addTab() {
    setState(() {
      _tabs.add(RepoTab(id: _nextTabId, title: 'New Tab'));
      _nextTabId++;
      _activeTabIndex = _tabs.length - 1;
    });
    _saveState();
  }

  void _closeTab(int index) {
    if (_tabs.length == 1) return;
    final removed = _tabs[index];
    setState(() {
      _tabs.removeAt(index);
      if (_activeTabIndex >= _tabs.length) {
        _activeTabIndex = _tabs.length - 1;
      } else if (_activeTabIndex > index) {
        _activeTabIndex--;
      }
    });
    for (final session in removed.terminalSessions) {
      session.dispose();
    }
    _saveState();
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
    _saveState();
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
                onSelect: (index) {
                  setState(() => _activeTabIndex = index);
                  _saveState();
                },
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
              if (_tabs[_activeTabIndex].isTerminalOpen)
                TerminalPanel(
                  key: ValueKey(_tabs[_activeTabIndex].id),
                  sessions: _tabs[_activeTabIndex].terminalSessions,
                  activeIndex: _tabs[_activeTabIndex].activeTerminalIndex,
                  onSelect: (index) {
                    setState(
                      () => _tabs[_activeTabIndex].activeTerminalIndex = index,
                    );
                    _saveState();
                  },
                  onClose: _closeTerminalTab,
                  onAddTab: _addTerminalTab,
                ),
              BottomToolbar(
                isTerminalOpen: _tabs[_activeTabIndex].isTerminalOpen,
                onToggleTerminal: _toggleTerminal,
              ),
            ],
          ),
        );
      },
    );
  }
}
