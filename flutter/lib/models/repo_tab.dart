import 'package:flutter/widgets.dart';

import '../repo/folder_update_controller.dart';
import '../repo/models.dart';
import '../repo/repo_controller.dart';
import '../repo/repository_view.dart';
import '../terminal/terminal_session.dart';

/// A single tab in the window: an unattached "start page" tab, one bound to
/// an opened/created/cloned repository, or a folder tab ([folderPath]) that
/// updates all the repositories inside a folder. Each tab owns its own
/// terminal sessions (spawned in that tab's repo directory) so the terminal
/// panel follows whichever repo tab is active, and (when bound to a repo) a
/// [RepoController] shared by the top bar and the [RepositoryView].
class RepoTab {
  RepoTab({
    required this.id,
    required this.title,
    String? path,
    String? folderPath,
  }) : _path = path,
       _controller = path == null ? null : RepoController(path),
       _folderPath = folderPath,
       _folderUpdate = folderPath == null
           ? null
           : FolderUpdateController(folderPath);

  final int id;
  String title;

  String? _path;
  RepoController? _controller;

  String? get path => _path;

  /// Binds this tab to [newPath] (or unbinds it with `null`), replacing
  /// (and disposing) the previous [controller].
  set path(String? newPath) {
    if (newPath == _path) return;
    _controller?.dispose();
    _path = newPath;
    _controller = newPath == null ? null : RepoController(newPath);
  }

  /// Section, branch info, auto-pull watcher and remote actions for the
  /// bound repository; `null` for a start-page tab.
  RepoController? get controller => _controller;

  String? _folderPath;
  FolderUpdateController? _folderUpdate;

  /// The folder of a folder tab; `null` for any other tab.
  String? get folderPath => _folderPath;

  /// Binds this tab to [newPath] as a folder tab (or unbinds it with
  /// `null`), replacing (and disposing) the previous [folderUpdate].
  set folderPath(String? newPath) {
    if (newPath == _folderPath) return;
    _folderUpdate?.dispose();
    _folderPath = newPath;
    _folderUpdate = newPath == null ? null : FolderUpdateController(newPath);
  }

  /// Scan and update run of a folder tab; `null` for any other tab.
  FolderUpdateController? get folderUpdate => _folderUpdate;

  final List<TerminalSession> terminalSessions = [];
  int nextTerminalId = 0;
  int activeTerminalIndex = 0;
  bool isTerminalOpen = false;
  bool isLogsOpen = false;
  double terminalHeight = 200;
  double logsHeight = 200;

  /// Key onto this tab's [RepositoryView], used to drive imperative actions
  /// on the view.
  final GlobalKey<RepositoryViewState> repositoryViewKey = GlobalKey();

  /// The active editor tab's detected file type, shown in the bottom bar.
  String? fileTypeLabel;

  /// The repository's current (HEAD) branch, and the full branch list.
  String? get currentBranch => _controller?.currentBranch;
  List<BranchEntry> get branches => _controller?.branches ?? const [];

  /// Releases the [controller] (stops auto-pull). Call when the tab closes.
  void dispose() {
    _controller?.dispose();
    _controller = null;
    _folderUpdate?.dispose();
    _folderUpdate = null;
  }
}
