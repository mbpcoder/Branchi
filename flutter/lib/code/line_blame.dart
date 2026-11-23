import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../repo/git_ffi.dart';

/// A run of lines last changed by one commit (see `GitRepo::blame`).
class BlameHunk {
  const BlameHunk({
    required this.startLine,
    required this.lines,
    required this.commitId,
    required this.author,
    required this.email,
    required this.time,
    required this.summary,
  });

  factory BlameHunk.fromJson(Map<String, dynamic> json) => BlameHunk(
        startLine: json['start_line'] as int,
        lines: json['lines'] as int,
        commitId: json['commit_id'] as String?,
        author: json['author'] as String? ?? '',
        email: json['email'] as String? ?? '',
        time: json['time'] == null
            ? null
            : DateTime.parse(json['time'] as String).toLocal(),
        summary: json['summary'] as String? ?? '',
      );

  /// 1-based.
  final int startLine;
  final int lines;

  /// Null for lines not committed yet.
  final String? commitId;
  final String author;
  final String email;
  final DateTime? time;
  final String summary;

  bool get isCommitted => commitId != null;

  bool contains(int line) => line >= startLine && line < startLine + lines;
}

/// The blame for one file's text, with the commit it was computed at.
class FileBlame {
  const FileBlame(this.hunks, this.headId);

  final List<BlameHunk> hunks;
  final String? headId;

  /// The hunk covering 1-based [line], if any.
  BlameHunk? at(int line) {
    // Hunks are in line order: binary search.
    var lo = 0;
    var hi = hunks.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final h = hunks[mid];
      if (line < h.startLine) {
        hi = mid - 1;
      } else if (line >= h.startLine + h.lines) {
        lo = mid + 1;
      } else {
        return h;
      }
    }
    return null;
  }
}

/// Whether the editor footer shows who last changed the current line.
/// Toggled with Ctrl/Cmd+Alt+B; remembered.
class BlameSettings {
  BlameSettings._();

  static const _prefsKey = 'editor_show_blame';
  static final ValueNotifier<bool> enabled = ValueNotifier(true);
  static Future<void>? _loading;

  static Future<void> ensureLoaded() => _loading ??= () async {
        try {
          final prefs = await SharedPreferences.getInstance();
          enabled.value = prefs.getBool(_prefsKey) ?? true;
        } catch (_) {}
      }();

  static Future<void> toggle() async {
    enabled.value = !enabled.value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, enabled.value);
    } catch (_) {}
  }
}

/// Files above this many lines aren't blamed (it can take long on large,
/// old files, and the footer is only a convenience).
const int _maxBlameLines = 20000;

/// Runs blame off the UI thread. Top-level so the isolate captures only
/// these arguments. Returns null when HEAD hasn't moved and [knownHead] is
/// given and [onlyIfHeadChanged] (a cheap check).
Future<(List<dynamic>?, String?)> _blameInIsolate(
  GitFfi ffi,
  String repo,
  String relPath,
  String? contents, {
  String? knownHead,
  bool onlyIfHeadChanged = false,
}) =>
    Isolate.run(() {
      String? head;
      try {
        head = ffi.resolveCommit(repo, 'HEAD');
      } catch (_) {
        // No commits yet.
      }
      if (onlyIfHeadChanged && head == knownHead) return (null, head);
      return (ffi.blame(repo, relPath, contents: contents), head);
    });

/// The `/`-separated path of [path] inside [repoRoot], or null if it's
/// outside it.
String? repoRelativePath(String repoRoot, String path) {
  if (!p.isWithin(repoRoot, path)) return null;
  return p.split(p.relative(path, from: repoRoot)).join('/');
}

/// Computes blame for one file at a time: at most one request runs, and
/// a request made meanwhile replaces any queued one.
class BlameRunner {
  BlameRunner({required this.repoRoot, required this.relPath});

  final String repoRoot;

  /// `/`-separated, relative to [repoRoot].
  String relPath;

  final ValueNotifier<FileBlame?> blame = ValueNotifier(null);

  String? _lastText;
  bool _running = false;
  String? _queuedText;
  bool _queued = false;
  bool _disposed = false;

  void dispose() {
    _disposed = true;
    blame.dispose();
  }

  /// Blames [text] unless it was the last text blamed at the same HEAD.
  void request(String text) {
    if (text == _lastText && blame.value != null) return;
    _queuedText = text;
    _queued = true;
    unawaited(_drain());
  }

  /// Re-blames if HEAD moved since the last result (e.g. after a commit
  /// or checkout); cheap otherwise.
  void checkHead(String text) {
    if (_running || _queued || blame.value == null) return;
    unawaited(_run(text, onlyIfHeadChanged: true));
  }

  Future<void> _drain() async {
    while (_queued && !_running && !_disposed) {
      _queued = false;
      await _run(_queuedText!);
    }
  }

  Future<void> _run(String text, {bool onlyIfHeadChanged = false}) async {
    final ffi = GitFfi.instanceOrNull;
    if (ffi == null || _disposed) return;
    if ('\n'.allMatches(text).length > _maxBlameLines) {
      blame.value = null;
      return;
    }
    _running = true;
    try {
      final (raw, head) = await _blameInIsolate(
        ffi,
        repoRoot,
        relPath,
        text,
        knownHead: blame.value?.headId,
        onlyIfHeadChanged: onlyIfHeadChanged,
      );
      if (_disposed || raw == null) return;
      _lastText = text;
      blame.value = FileBlame(
        raw.cast<Map<String, dynamic>>().map(BlameHunk.fromJson).toList(),
        head,
      );
    } catch (_) {
      // Not in a repo, ignored file, etc.: just show nothing.
      if (!_disposed && !onlyIfHeadChanged) blame.value = null;
    } finally {
      _running = false;
      if (!_disposed) unawaited(_drain());
    }
  }
}
