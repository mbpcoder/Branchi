import 'dart:async';

import 'package:flutter/foundation.dart';

import '../l10n/app_locale.dart';
import 'branch_watch_store.dart';

/// Intervals offered by the auto-pull menu in the top bar, in minutes.
/// (The branch sidebar may offer more; any positive value is supported.)
const List<int> kAutoPullIntervalsMinutes = [1, 2, 3, 4];

/// Localized "1 minute" / "N minutes" label for an auto-pull interval.
String autoPullIntervalLabel(int minutes) => minutes == 1
    ? translate('minute_one')
    : translate('minutes_n').replaceAll('{n}', '$minutes');

/// Formats a countdown as `m:ss` (or `h:mm:ss` past an hour).
String formatCountdown(Duration duration) {
  final totalSeconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$ss';
  }
  return '$minutes:$ss';
}

/// The per-repository branch watcher ("auto-pull"): every
/// [intervalMinutes] it calls [onPull] to update the current branch from
/// its upstream. The interval is persisted per repo via [BranchWatchStore];
/// `null` means off.
///
/// Listen to the watcher itself ([ChangeNotifier]) for interval / running
/// state changes, and to [countdown] for the once-a-second time remaining
/// until the next pull (`null` while off).
class BranchWatcher extends ChangeNotifier {
  BranchWatcher({required this.repoPath, required this.onPull}) {
    _load();
  }

  final String repoPath;

  /// Performs the actual pull. Errors are the callback's concern (they are
  /// recorded in the action log by [GitActions]).
  final Future<void> Function() onPull;

  int? _intervalMinutes;
  DateTime? _nextPullAt;
  bool _isPulling = false;
  bool _loaded = false;
  bool _userChanged = false;
  bool _disposed = false;
  Timer? _ticker;

  /// Time remaining until the next automatic pull, updated every second;
  /// `null` while the watcher is off. [Duration.zero] while a pull runs.
  final ValueNotifier<Duration?> countdown = ValueNotifier<Duration?>(null);

  /// The selected interval in minutes, or `null` when auto-pull is off.
  int? get intervalMinutes => _intervalMinutes;

  bool get isEnabled => _intervalMinutes != null;

  /// Whether the persisted interval has been loaded yet.
  bool get isLoaded => _loaded;

  /// When the next automatic pull is due, or `null` while off.
  DateTime? get nextPullAt => _nextPullAt;

  /// Whether an automatic pull triggered by this watcher is running.
  bool get isPulling => _isPulling;

  Future<void> _load() async {
    final minutes = await BranchWatchStore.loadIntervalMinutes(repoPath);
    if (_disposed) return;
    _loaded = true;
    // A user choice made before the stored value arrived wins.
    if (!_userChanged && minutes != null && minutes > 0) {
      _intervalMinutes = minutes;
      _restart();
    }
    notifyListeners();
  }

  /// Sets the interval (`null` turns auto-pull off), persists it and
  /// restarts the countdown from the full interval.
  void setIntervalMinutes(int? minutes) {
    if (minutes != null && minutes <= 0) minutes = null;
    _loaded = true;
    _userChanged = true;
    if (minutes == _intervalMinutes) return;
    _intervalMinutes = minutes;
    _restart();
    BranchWatchStore.saveIntervalMinutes(repoPath, minutes);
    notifyListeners();
  }

  /// Resets the countdown to a full interval, e.g. after a manual pull.
  void resetCountdown() {
    if (_intervalMinutes == null) return;
    _nextPullAt = DateTime.now().add(Duration(minutes: _intervalMinutes!));
    _updateCountdown();
  }

  void _restart() {
    _ticker?.cancel();
    _ticker = null;
    final minutes = _intervalMinutes;
    if (minutes == null) {
      _nextPullAt = null;
      countdown.value = null;
      return;
    }
    _nextPullAt = DateTime.now().add(Duration(minutes: minutes));
    _updateCountdown();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final next = _nextPullAt;
    if (next == null || _isPulling) return;
    if (!DateTime.now().isBefore(next)) {
      unawaited(_runPull());
    } else {
      _updateCountdown();
    }
  }

  void _updateCountdown() {
    final next = _nextPullAt;
    if (next == null) {
      countdown.value = null;
      return;
    }
    final remaining = next.difference(DateTime.now());
    // Round up so a fresh 2-minute interval shows 2:00, not 1:59.
    final seconds = (remaining.inMilliseconds / 1000).ceil();
    countdown.value = Duration(seconds: seconds < 0 ? 0 : seconds);
  }

  Future<void> _runPull() async {
    _isPulling = true;
    countdown.value = Duration.zero;
    notifyListeners();
    try {
      await onPull();
    } catch (_) {
      // Recorded by GitActions; the watcher keeps running.
    } finally {
      if (!_disposed) {
        _isPulling = false;
        if (_intervalMinutes != null) resetCountdown();
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    countdown.dispose();
    super.dispose();
  }
}
