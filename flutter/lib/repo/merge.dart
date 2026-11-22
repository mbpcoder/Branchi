import 'dart:isolate';

import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../logs/action_log.dart';
import '../theme/app_theme.dart';
import 'git_ffi.dart';
import 'models.dart';

/// How a branch is brought into the current one.
enum MergeMode { merge, squash }

/// What merging a branch into the current one would bring in.
class MergePreview {
  MergePreview.fromJson(Map<String, dynamic> json)
      : source = json['source'] as String,
        target = json['target'] as String?,
        incoming = (json['incoming'] as List)
            .map((c) => CommitEntry.fromJson(c as Map<String, dynamic>))
            .toList(),
        incomingCount = json['incoming_count'] as int,
        upToDate = json['up_to_date'] as bool,
        canFastForward = json['can_fast_forward'] as bool,
        dirty = json['dirty'] as bool;

  final String source;
  final String? target;
  final List<CommitEntry> incoming;
  final int incomingCount;
  final bool upToDate;
  final bool canFastForward;
  final bool dirty;
}

/// A merge that stopped on conflicts.
class MergeState {
  MergeState.fromJson(Map<String, dynamic> json)
      : isSquash = json['kind'] == 'squash',
        message = json['message'] as String,
        conflicts = (json['conflicts'] as List).cast<String>();

  final bool isSquash;
  final String message;
  final List<String> conflicts;
}

/// How a merge ended: `up_to_date`, `fast_forward`, `committed` or
/// `conflicts`.
typedef MergeOutcome = ({String result, List<String> conflicts});

String _missing() => 'branchi_core library not loaded';

/// Merge calls into the core, run off the UI thread and logged in Activity.
class MergeActions {
  MergeActions._();

  static Future<MergePreview> preview(String repo, String source) async {
    final ffi = GitFfi.instanceOrNull;
    if (ffi == null) throw StateError(_missing());
    final json = await Isolate.run(() => ffi.mergePreview(repo, source));
    return MergePreview.fromJson(json);
  }

  /// Throws a [GitFfiException] with a readable message on failure.
  static Future<MergeOutcome> merge(
    String repo,
    String source,
    String mode,
    String message,
  ) async {
    final ffi = GitFfi.instanceOrNull;
    if (ffi == null) throw StateError(_missing());
    try {
      final json =
          await Isolate.run(() => ffi.merge(repo, source, mode, message));
      final outcome = (
        result: json['result'] as String,
        conflicts: (json['conflicts'] as List).cast<String>(),
      );
      ActionLog.instance.record(
        '$mode $source',
        success: true,
        detail: outcome.result == 'conflicts'
            ? '${outcome.conflicts.length} conflicted file(s)'
            : null,
      );
      return outcome;
    } on GitFfiException catch (e) {
      ActionLog.instance.record('$mode $source', success: false, detail: e.message);
      rethrow;
    }
  }

  static Future<MergeState?> state(String repo) async {
    final ffi = GitFfi.instanceOrNull;
    if (ffi == null) return null;
    final json = await Isolate.run(() => ffi.mergeState(repo));
    return json == null ? null : MergeState.fromJson(json);
  }

  /// Null on success, else the error.
  static Future<String?> abort(String repo) async {
    final ffi = GitFfi.instanceOrNull;
    if (ffi == null) return _missing();
    final error = await Isolate.run(() => ffi.abortMerge(repo));
    ActionLog.instance.record('abort merge', success: error == null, detail: error);
    return error;
  }

  /// Takes `ours` or `theirs` whole for [file]. Null on success.
  static Future<String?> resolve(String repo, String file, String side) async {
    final ffi = GitFfi.instanceOrNull;
    if (ffi == null) return _missing();
    final error = await Isolate.run(() => ffi.resolveConflict(repo, file, side));
    ActionLog.instance.record(
      'resolve $file ($side)',
      success: error == null,
      detail: error,
    );
    return error;
  }
}

/// Asks how to bring [source] into the current branch and does it. Returns
/// the outcome, or null when cancelled or failed (failures are shown).
Future<MergeOutcome?> showMergeDialog(
  BuildContext context, {
  required String repo,
  required String source,
}) {
  return showDialog<MergeOutcome>(
    context: context,
    builder: (_) => _MergeDialog(repo: repo, source: source),
  );
}

class _MergeDialog extends StatefulWidget {
  const _MergeDialog({required this.repo, required this.source});

  final String repo;
  final String source;

  @override
  State<_MergeDialog> createState() => _MergeDialogState();
}

class _MergeDialogState extends State<_MergeDialog> {
  final _message = TextEditingController();
  MergePreview? _preview;
  String? _error;
  MergeMode _mode = MergeMode.merge;
  bool _noFastForward = false;
  bool _busy = false;

  /// Whether the user edited the message (then switching modes keeps it).
  bool _messageEdited = false;

  @override
  void initState() {
    super.initState();
    MergeActions.preview(widget.repo, widget.source).then((preview) {
      if (!mounted) return;
      setState(() => _preview = preview);
      _fillMessage();
    }, onError: (Object e) {
      if (mounted) setState(() => _error = e.toString());
    });
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  String get _target => _preview?.target ?? 'HEAD';

  void _fillMessage() {
    final preview = _preview;
    if (preview == null || _messageEdited) return;
    if (_mode == MergeMode.merge) {
      _message.text = "Merge branch '${widget.source}' into $_target";
    } else {
      _message.text = [
        "Squash merge branch '${widget.source}'",
        '',
        for (final c in preview.incoming.reversed) '* ${c.summary}',
      ].join('\n');
    }
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final mode = _mode == MergeMode.squash
        ? 'squash'
        : (_noFastForward ? 'no_ff' : 'merge');
    try {
      final outcome = await MergeActions.merge(
        widget.repo,
        widget.source,
        mode,
        _message.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(outcome);
    } on GitFfiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final preview = _preview;
    String t(String key) => translate(key)
        .replaceAll('{source}', widget.source)
        .replaceAll('{target}', _target)
        .replaceAll('{count}', '${preview?.incomingCount ?? 0}');
    final bold = TextStyle(color: b.fg, fontWeight: FontWeight.w600);
    final canRun = preview != null &&
        !preview.upToDate &&
        !preview.dirty &&
        !_busy &&
        _message.text.trim().isNotEmpty;

    Widget body;
    if (preview == null) {
      body = _error != null
          ? Text(_error!, style: TextStyle(color: b.del))
          : const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
    } else if (preview.upToDate) {
      body = Text(t('merge_up_to_date'), style: TextStyle(color: b.muted));
    } else {
      final shown = preview.incoming.take(6).toList();
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text.rich(
            TextSpan(
              style: TextStyle(color: b.muted, fontSize: 13),
              children: _withBold(
                t(_mode == MergeMode.squash
                    ? 'merge_squash_summary'
                    : 'merge_summary'),
                [widget.source, _target],
                bold,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SegmentedButton<MergeMode>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: MergeMode.merge,
                label: Text(translate('merge_mode_merge')),
              ),
              ButtonSegment(
                value: MergeMode.squash,
                label: Text(translate('merge_mode_squash')),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: _busy
                ? null
                : (s) {
                    setState(() => _mode = s.first);
                    _fillMessage();
                  },
          ),
          const SizedBox(height: 6),
          Text(
            translate(_mode == MergeMode.squash
                ? 'merge_squash_hint'
                : 'merge_merge_hint'),
            style: TextStyle(color: b.muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          for (final c in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Text(c.shortId, style: b.mono(fontSize: 11, color: b.muted)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      c.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: b.fg, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          if (preview.incomingCount > shown.length)
            Text(
              translate('merge_more_commits').replaceAll(
                '{count}',
                '${preview.incomingCount - shown.length}',
              ),
              style: TextStyle(color: b.muted, fontSize: 12),
            ),
          const SizedBox(height: 12),
          if (!(_mode == MergeMode.merge &&
              preview.canFastForward &&
              !_noFastForward))
            TextField(
              controller: _message,
              minLines: 1,
              maxLines: 6,
              style: TextStyle(color: b.fg, fontSize: 13),
              decoration: InputDecoration(
                labelText: translate('merge_message'),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _messageEdited = true),
            ),
          if (_mode == MergeMode.merge && preview.canFastForward)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: _noFastForward,
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _noFastForward = v ?? false),
              title: Text(translate('merge_no_ff')),
              subtitle: _noFastForward
                  ? null
                  : Text(translate('merge_ff_hint')),
            ),
          if (preview.dirty) ...[
            const SizedBox(height: 10),
            Text(translate('merge_dirty'), style: TextStyle(color: b.mod)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: b.del)),
          ],
        ],
      );
    }

    return AlertDialog(
      title: Text(t('merge_title')),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: body)),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(translate(
            preview?.upToDate ?? false ? 'close' : 'cancel',
          )),
        ),
        if (preview != null && !preview.upToDate)
          FilledButton(
            onPressed: canRun ? _run : null,
            child: Text(translate(_mode == MergeMode.squash
                ? 'merge_mode_squash'
                : 'merge_mode_merge')),
          ),
      ],
    );
  }
}

/// Splits [text] so each of [words] is shown in [bold].
List<TextSpan> _withBold(String text, List<String> words, TextStyle bold) {
  final spans = <TextSpan>[];
  var rest = text;
  while (rest.isNotEmpty) {
    var at = -1;
    var word = '';
    for (final w in words) {
      final i = rest.indexOf(w);
      if (i != -1 && (at == -1 || i < at)) {
        at = i;
        word = w;
      }
    }
    if (at == -1) {
      spans.add(TextSpan(text: rest));
      break;
    }
    if (at > 0) spans.add(TextSpan(text: rest.substring(0, at)));
    spans.add(TextSpan(text: word, style: bold));
    rest = rest.substring(at + word.length);
  }
  return spans;
}
