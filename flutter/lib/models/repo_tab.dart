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
}
