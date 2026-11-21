import 'package:flutter/foundation.dart';

import '../l10n/app_calendar.dart';
import '../repo/git_actions.dart';
import 'report_data.dart';

/// The Report section's state for one repository: the chosen period and
/// author, and the loaded data. Owned by the repo's [RepoController], so
/// the filters stay put while other sections or tabs are shown.
class ReportController extends ChangeNotifier {
  ReportController(this.repoPath);

  final String repoPath;

  PeriodPreset _preset = PeriodPreset.last90Days;
  ReportPeriod? _customPeriod;

  /// The author being looked at (lowercase email), or `null` for everyone.
  String? authorKey;

  ReportData? data;
  bool isLoading = false;
  String? error;
  bool _disposed = false;
  int _loadToken = 0;

  PeriodPreset get preset => _preset;

  /// The period in effect, worked out fresh so "last 30 days" always ends
  /// today and month presets follow the current calendar.
  ReportPeriod get period => _preset == PeriodPreset.custom
      ? _customPeriod!
      : ReportPeriod.fromPreset(_preset, AppCalendarSettings.current);

  void setPreset(PeriodPreset preset) {
    if (preset == PeriodPreset.custom) return;
    _preset = preset;
    load();
  }

  void setCustomPeriod(DateTime from, DateTime to) {
    _customPeriod = ReportPeriod.custom(from, to);
    _preset = PeriodPreset.custom;
    load();
  }

  void selectAuthor(String? key) {
    authorKey = key;
    _notify();
  }

  /// Loads the current period unless it's already loaded, or always when
  /// [force] (e.g. after new commits).
  Future<void> load({bool force = false}) async {
    final target = period;
    final loaded = data?.period;
    if (!force &&
        loaded != null &&
        loaded.from == target.from &&
        loaded.to == target.to &&
        error == null) {
      return;
    }
    final token = ++_loadToken;
    isLoading = true;
    error = null;
    _notify();
    try {
      final result = await GitActions.report(repoPath, target);
      if (_disposed || token != _loadToken) return;
      data = result;
    } catch (e) {
      if (_disposed || token != _loadToken) return;
      error = e.toString();
    }
    isLoading = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
