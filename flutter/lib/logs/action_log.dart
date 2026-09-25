import 'package:flutter/foundation.dart';

import 'file_logger.dart';

/// A single recorded git action: what ran, when, and whether it succeeded.
class ActionLogEntry {
  ActionLogEntry({
    required this.action,
    required this.timestamp,
    required this.success,
    this.detail,
  });

  final String action;
  final DateTime timestamp;
  final bool success;
  final String? detail;
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

  void record(String action, {required bool success, String? detail}) {
    _entries.insert(
      0,
      ActionLogEntry(
        action: action,
        timestamp: DateTime.now(),
        success: success,
        detail: detail,
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
