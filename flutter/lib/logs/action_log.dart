import 'package:flutter/foundation.dart';

import 'file_logger.dart';

/// What a commit, pull or push changed. [commits] is null for a commit
/// entry, where it would always be one.
class ActionStats {
  const ActionStats({
    this.commits,
    required this.files,
    required this.insertions,
    required this.deletions,
  });

  factory ActionStats.fromJson(
    Map<String, dynamic> json, {
    bool withCommits = true,
  }) =>
      ActionStats(
        commits: withCommits ? json['commits'] as int : null,
        files: json['files'] as int,
        insertions: json['insertions'] as int,
        deletions: json['deletions'] as int,
      );

  final int? commits;
  final int files;
  final int insertions;
  final int deletions;

  /// A pull or push that moved nothing.
  bool get isUpToDate => commits == 0;
}

/// A single recorded git action: what ran, when, and whether it succeeded.
class ActionLogEntry {
  ActionLogEntry({
    required this.action,
    required this.timestamp,
    required this.success,
    this.detail,
    this.stats,
  });

  final String action;
  final DateTime timestamp;
  final bool success;
  final String? detail;

  /// Counts shown beside the action; only commit, pull and push set it.
  final ActionStats? stats;
}

/// App-wide, in-memory log of git actions run through [GitActions], newest
/// first. Backs the logs panel toggled from [BottomToolbar].
class ActionLog extends ChangeNotifier {
  ActionLog._();

  static final ActionLog instance = ActionLog._();

  static const int _maxEntries = 500;

  final List<ActionLogEntry> _entries = [];

  List<ActionLogEntry> get entries => List.unmodifiable(_entries);

  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }

  void record(
    String action, {
    required bool success,
    String? detail,
    ActionStats? stats,
  }) {
    _entries.insert(
      0,
      ActionLogEntry(
        action: action,
        timestamp: DateTime.now(),
        success: success,
        detail: detail,
        stats: success ? stats : null,
      ),
    );
    if (_entries.length > _maxEntries) {
      _entries.removeRange(_maxEntries, _entries.length);
    }
    if (!success) {
      FileLogger.log('Action failed: $action${detail != null ? ' - $detail' : ''}');
    }
    notifyListeners();
  }
}
