import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import '../app_state_store.dart';
import '../l10n/app_locale.dart';
import '../logs/logs_panel.dart';
import '../models/repo_tab.dart';
import '../repo/recent_repositories_store.dart';
import '../repo/repository_view.dart';
import '../settings/settings_route.dart';
import '../settings/shell_preferences.dart';
import '../terminal/terminal_panel.dart';
import '../terminal/terminal_session.dart';
import '../theme/app_theme.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/bottom_toolbar.dart';
import '../update/update_banner.dart';
import 'folder_update_view.dart';
import 'welcome_form.dart';

/// The app's main window: the top bar (with repo switcher, section tabs and
/// remote actions), the tab strip (always visible), the
/// active tab's content (start page or an opened repository), the terminal
/// and logs panels, and the footer.
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
    HardwareKeyboard.instance.addHandler(_onKey);
    _restoreState();
  }

  /// Alt+F12 shows or hides the terminal. Handled before the focus system,
  /// so it also works while the terminal itself has focus (it would
  /// otherwise send the keys to the shell).
  bool _onKey(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.f12 ||
        !keyboard.isAltPressed ||
        keyboard.isControlPressed ||
        keyboard.isShiftPressed ||
        keyboard.isMetaPressed ||
        !mounted ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return false;
    }
    _toggleTerminal();
    return true;
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
        final tab = RepoTab(
          id: i,
          title: persisted.title,
          path: persisted.path,
          folderPath: persisted.path == null ? persisted.folderPath : null,
        );
        tab.terminalSessions.addAll([
          for (var j = 0; j < persisted.terminalTitles.length; j++)
            spawnTerminalSession(
              j,
              persisted.terminalTitles[j],
              workingDirectory: tab.path ?? tab.folderPath,
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
        tab.dispose();
      }
      return;
    }

    setState(() {
      for (final tab in _tabs) {
        tab.dispose();
      }
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
              folderPath: tab.folderPath,
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

  /// Opens the terminal panel with a fresh terminal tab in the active
  /// tab's repository folder.
  Future<void> _openNewTerminal() async {
    final tab = _tabs[_activeTabIndex];
    await _addTerminalTab();
    if (!mounted) return;
    setState(() => tab.isTerminalOpen = true);
    _saveState();
  }

  void _toggleLogs() {
    final tab = _tabs[_activeTabIndex];
    setState(() => tab.isLogsOpen = !tab.isLogsOpen);
  }

  Future<void> _addTerminalTab([ShellDefinition? shell]) async {
    final tab = _tabs[_activeTabIndex];
    final session = spawnTerminalSession(
      tab.nextTerminalId,
      '${translate('terminal')} ${tab.nextTerminalId + 1}',
      workingDirectory: tab.path ?? tab.folderPath,
      shellExecutable: shell?.executable,
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
    HardwareKeyboard.instance.removeHandler(_onKey);
    for (final tab in _tabs) {
      for (final session in tab.terminalSessions) {
        session.dispose();
      }
      tab.dispose();
    }
    super.dispose();
  }

  /// Opens [path] as a folder tab: a new tab next to the others, listing
  /// the repositories inside it.
  void _openFolderTab(String path) {
    setState(() {
      _tabs.add(
        RepoTab(id: _nextTabId, title: p.basename(path), folderPath: path),
      );
      _nextTabId++;
      _activeTabIndex = _tabs.length - 1;
    });
    _saveState();
  }

  /// Points the active folder tab at another folder.
  void _changeActiveTabFolder(String path) {
    setState(() {
      final tab = _tabs[_activeTabIndex];
      tab.folderPath = path;
      tab.title = p.basename(path);
    });
    _saveState();
  }

  /// Index of the tab that has the repository at [path] open, or -1.
  int _tabIndexForRepository(String path) =>
      _tabs.indexWhere((t) => t.path != null && p.equals(t.path!, path));

  /// Opens the repository at [path] in a new tab, e.g. from a folder tab.
  /// If a tab already has it open, switches to that tab instead.
  Future<void> _openRepositoryInNewTab(String path) async {
    final existing = _tabIndexForRepository(path);
    if (existing != -1) {
      _selectTab(existing);
      return;
    }
    await RecentRepositoriesStore.addOrPromote(path);
    if (!mounted) return;
    setState(() {
      _tabs.add(RepoTab(id: _nextTabId, title: p.basename(path), path: path));
      _nextTabId++;
      _activeTabIndex = _tabs.length - 1;
    });
    _saveState();
  }

  void _addTab() {
    setState(() {
      _tabs.add(RepoTab(id: _nextTabId, title: 'New Tab'));
      _nextTabId++;
      _activeTabIndex = _tabs.length - 1;
    });
    _saveState();
  }

  /// Closes the tab at [index]. If it's the only tab left, there's nothing
  /// to fall back to, so it's reset to a blank "New Tab" instead — this is
  /// what lets a tab with a repository open be closed even when it's the
  /// last one.
  void _closeTab(int index) {
    final removed = _tabs[index];
    if (_tabs.length == 1) {
      final oldSessions = List.of(removed.terminalSessions);
      setState(() {
        removed
          ..path = null
          ..folderPath = null
          ..title = 'New Tab'
          ..isTerminalOpen = false
          ..isLogsOpen = false
          ..terminalSessions.clear()
          ..nextTerminalId = 0
          ..activeTerminalIndex = 0;
      });
      for (final session in oldSessions) {
        session.dispose();
      }
      _saveState();
      return;
    }
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
    removed.dispose();
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
    openSettings(context);
  }

  void _selectTab(int index) {
    if (index == _activeTabIndex) return;
    setState(() => _activeTabIndex = index);
    _saveState();
  }

  /// Attaches [path] to the currently active tab, e.g. after a repository
  /// is opened, created, or cloned from that tab's start form.
  ///
  /// If another tab already has [path] open, switches to that tab and
  /// closes the start-page tab it was picked from instead of opening the
  /// repository twice.
  void _setActiveTabRepository(String path) {
    final existing = _tabIndexForRepository(path);
    if (existing != -1 && existing != _activeTabIndex) {
      final startTab = _activeTabIndex;
      setState(() => _activeTabIndex = existing);
      _closeTab(startTab);
      return;
    }
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
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final tab = _tabs[_activeTabIndex];
        return Scaffold(
          body: Column(
            children: [
              AppTopBar(
                tabs: _tabs,
                activeIndex: _activeTabIndex,
                onSelectTab: _selectTab,
                onCloseTab: _closeTab,
                onAddTab: _addTab,
                controller: tab.controller,
                onOpenSettings: _openSettings,
                isDark: isDark,
                onToggleTheme: AppTheme.toggle,
                isPinned: _isPinned,
                onTogglePin: _togglePin,
              ),
              const UpdateBanner(),
              Expanded(
                child: tab.path != null && tab.controller != null
                    ? RepositoryView(
                        key: tab.repositoryViewKey,
                        path: tab.path!,
                        controller: tab.controller!,
                        onLanguageChanged: (label) =>
                            setState(() => tab.fileTypeLabel = label),
                        onOpenInTerminal: _openNewTerminal,
                      )
                    : tab.folderUpdate != null
                        ? FolderUpdateView(
                            key: ValueKey(tab.id),
                            controller: tab.folderUpdate!,
                            onOpenRepository: _openRepositoryInNewTab,
                            isRepositoryOpen: (path) =>
                                _tabIndexForRepository(path) != -1,
                            onChangeFolder: _changeActiveTabFolder,
                          )
                        : WelcomeForm(
                            key: ValueKey(tab.id),
                            onRepositoryOpened: _setActiveTabRepository,
                            onUpdateFolderSelected: _openFolderTab,
                          ),
              ),
              if (tab.isTerminalOpen)
                TerminalPanel(
                  key: ValueKey(tab.id),
                  sessions: tab.terminalSessions,
                  activeIndex: tab.activeTerminalIndex,
                  onSelect: (index) {
                    setState(() => tab.activeTerminalIndex = index);
                    _saveState();
                  },
                  onClose: _closeTerminalTab,
                  onAddTab: _addTerminalTab,
                  height: tab.terminalHeight,
                  onHeightChanged: (value) =>
                      setState(() => tab.terminalHeight = value),
                ),
              if (tab.isLogsOpen)
                LogsPanel(
                  height: tab.logsHeight,
                  onHeightChanged: (value) =>
                      setState(() => tab.logsHeight = value),
                ),
              BottomToolbar(
                isTerminalOpen: tab.isTerminalOpen,
                onToggleTerminal: _toggleTerminal,
                isLogsOpen: tab.isLogsOpen,
                onToggleLogs: _toggleLogs,
                fileTypeLabel: tab.fileTypeLabel,
              ),
            ],
          ),
        );
      },
    );
  }
}
