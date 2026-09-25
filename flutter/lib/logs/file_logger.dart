import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Writes exceptions and errors to a daily rotating log file under the
/// app's `logs/` folder, so a file can be pasted back for debugging.
///
/// One file per day (`branchi-app-YYYY-MM-DD.log`); files older than
/// [_retentionDays] are deleted on startup.
class FileLogger {
  FileLogger._();

  static const int _retentionDays = 30;

  static Directory? _logsDir;

  /// Resolves the `logs/` directory next to the running executable and
  /// prunes entries older than [_retentionDays]. Safe to call once at
  /// startup; a no-op on web.
  static Future<void> init() async {
    if (kIsWeb) return;
    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      final dir = Directory('${exeDir.path}${Platform.pathSeparator}logs');
      await dir.create(recursive: true);
      _logsDir = dir;
      await _pruneOldLogs(dir);
    } catch (_) {
      // Logging must never crash the app it's trying to log.
    }
  }

  static Future<void> _pruneOldLogs(Directory dir) async {
    final cutoff = DateTime.now().subtract(const Duration(days: _retentionDays));
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith('branchi-app-') || !name.endsWith('.log')) continue;
      try {
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) {
          await entity.delete();
        }
      } catch (_) {
        // Best-effort cleanup; leave the file if it can't be inspected.
      }
    }
  }

  static File? _fileForToday() {
    final dir = _logsDir;
    if (dir == null) return null;
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final name = 'branchi-app-${now.year}-${two(now.month)}-${two(now.day)}.log';
    return File('${dir.path}${Platform.pathSeparator}$name');
  }

  /// Appends one timestamped entry to today's log file. `stackTrace` is
  /// included when available (e.g. for uncaught exceptions).
  static void log(String message, {StackTrace? stackTrace}) {
    final file = _fileForToday();
    if (file == null) return;
    final buffer = StringBuffer()
      ..write(DateTime.now().toIso8601String())
      ..write(' ')
      ..write(message);
    if (stackTrace != null) {
      buffer
        ..write('\n')
        ..write(stackTrace.toString());
    }
    buffer.write('\n');
    unawaited(
      file.writeAsString(buffer.toString(), mode: FileMode.append).catchError((_) {
        return file;
      }),
    );
  }
}
