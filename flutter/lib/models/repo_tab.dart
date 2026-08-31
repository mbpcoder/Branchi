import 'package:flutter/widgets.dart';

import '../repo/models.dart';
import '../repo/repository_view.dart';
import '../terminal/terminal_session.dart';

/// A single tab in the top tab bar: either an unattached "start page" tab
/// or one bound to an opened/created/cloned repository. Each tab owns its
/// own terminal sessions (spawned in that tab's repo directory) so the
/// terminal panel follows whichever repo tab is active.
class RepoTab {
  RepoTab({required this.id, required this.title, this.path});

  final int id;
  String title;
  String? path;

  final List<TerminalSession> terminalSessions = [];
  int nextTerminalId = 0;
  int activeTerminalIndex = 0;
  bool isTerminalOpen = false;
  bool isLogsOpen = false;
  double terminalHeight = 200;
  double logsHeight = 200;

  /// Key onto this tab's [RepositoryView], used to drive imperative actions
  /// (e.g. checking out a branch) from the bottom bar.
  final GlobalKey<RepositoryViewState> repositoryViewKey = GlobalKey();

  /// The active editor tab's detected file type, shown in the bottom bar.
  String? fileTypeLabel;

  /// The repository's current (HEAD) branch, and the full branch list, kept
  /// in sync from [RepositoryView] for the bottom bar's branch switcher.
  String? currentBranch;
  List<BranchEntry> branches = const [];
}
