import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_locale.dart';
import '../repo/git_ffi.dart';
import '../theme/app_theme.dart';

/// One matching line.
class ContentSearchMatch {
  ContentSearchMatch({
    required this.path,
    required this.line,
    required this.column,
    required this.text,
    required this.ranges,
  });

  factory ContentSearchMatch.fromJson(Map<String, dynamic> json) =>
      ContentSearchMatch(
        path: json['path'] as String,
        line: json['line'] as int,
        column: json['column'] as int,
        text: json['text'] as String,
        ranges: [
          for (final r in json['ranges'] as List)
            ((r as List)[0] as int, r[1] as int),
        ],
      );

  /// Relative to the searched root, `/`-separated.
  final String path;

  /// 1-based.
  final int line;

  /// 0-based character column of the first match.
  final int column;
  final String text;
  final List<(int, int)> ranges;

  /// Length of the first match, for selecting it in the editor.
  int get firstMatchLength => ranges.isEmpty ? 0 : ranges[0].$2 - ranges[0].$1;
}

/// Called to open a result: absolute path, 1-based line, 0-based column and
/// the match's length.
typedef OpenMatchCallback = void Function(
  String path,
  int line,
  int column,
  int length,
);

/// Off the UI thread; top-level so the isolate captures only its arguments.
Future<Map<String, dynamic>> _searchInIsolate(
  GitFfi ffi,
  String root,
  String query,
  bool regex,
  bool caseSensitive,
  bool wholeWord,
) =>
    Isolate.run(
      () => ffi.searchContent(
        root,
        query,
        regex: regex,
        caseSensitive: caseSensitive,
        wholeWord: wholeWord,
      ),
    );

/// The "Search in files" sidebar: a query box with case / whole word /
/// regex toggles, and matching lines grouped by file.
class ContentSearchPanel extends StatefulWidget {
  const ContentSearchPanel({
    super.key,
    required this.rootPath,
    required this.onOpenMatch,
    required this.onClose,
    this.width = 260,
  });

  final String rootPath;
  final OpenMatchCallback onOpenMatch;

  /// Switches the sidebar back to the file tree.
  final VoidCallback onClose;
  final double width;

  @override
  State<ContentSearchPanel> createState() => ContentSearchPanelState();
}

class ContentSearchPanelState extends State<ContentSearchPanel> {
  final _query = TextEditingController();
  final _queryFocus = FocusNode();
  Timer? _debounce;
  int _generation = 0;

  bool _caseSensitive = false;
  bool _wholeWord = false;
  bool _regex = false;

  bool _searching = false;
  String? _error;
  bool _truncated = false;

  /// Results grouped by file, in path order.
  List<(String, List<ContentSearchMatch>)> _groups = const [];
  int _matchCount = 0;
  final Set<String> _collapsed = {};

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  /// Focuses the query box (e.g. on Ctrl+Shift+F), optionally filling it.
  void focusQuery({String? text}) {
    if (text != null && text.isNotEmpty) {
      _query.text = text;
      _scheduleSearch(immediate: true);
    }
    _queryFocus.requestFocus();
    _query.selection =
        TextSelection(baseOffset: 0, extentOffset: _query.text.length);
  }

  void _scheduleSearch({bool immediate = false}) {
    _debounce?.cancel();
    _debounce = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 250),
      () => unawaited(_search()),
    );
  }

  Future<void> _search() async {
    final query = _query.text;
    final generation = ++_generation;
    if (query.isEmpty) {
      setState(() {
        _groups = const [];
        _matchCount = 0;
        _truncated = false;
        _error = null;
        _searching = false;
      });
      return;
    }
    final ffi = GitFfi.instanceOrNull;
    if (ffi == null) {
      setState(() => _error = translate('file_search_unavailable'));
      return;
    }
    setState(() => _searching = true);
    try {
      final result = await _searchInIsolate(
        ffi,
        widget.rootPath,
        query,
        _regex,
        _caseSensitive,
        _wholeWord,
      );
      if (!mounted || generation != _generation) return;
      final matches = (result['matches'] as List)
          .cast<Map<String, dynamic>>()
          .map(ContentSearchMatch.fromJson)
          .toList();
      final groups = <(String, List<ContentSearchMatch>)>[];
      for (final m in matches) {
        if (groups.isEmpty || groups.last.$1 != m.path) {
          groups.add((m.path, [m]));
        } else {
          groups.last.$2.add(m);
        }
      }
      setState(() {
        _groups = groups;
        _matchCount = matches.length;
        _truncated = result['truncated'] as bool? ?? false;
        _error = null;
        _searching = false;
        _collapsed.clear();
      });
    } on GitFfiException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error.message;
        _groups = const [];
        _matchCount = 0;
        _searching = false;
      });
    }
  }

  void _open(ContentSearchMatch m) {
    widget.onOpenMatch(
      p.joinAll([widget.rootPath, ...m.path.split('/')]),
      m.line,
      m.column,
      m.firstMatchLength,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.branchi;
    final summaryStyle = TextStyle(fontSize: 11, color: c.muted);

    String summary() {
      if (_error != null) return _error!;
      if (_query.text.isEmpty) return '';
      if (_matchCount == 0) {
        return _searching ? '' : translate('content_search_no_results');
      }
      final text = translate('content_search_summary')
          .replaceAll('{matches}', '$_matchCount')
          .replaceAll('{files}', '${_groups.length}');
      return _truncated
          ? '$text ${translate('content_search_truncated')}'
          : text;
    }

    final rows = <Widget>[];
    for (final (path, matches) in _groups) {
      final collapsed = _collapsed.contains(path);
      rows.add(_FileHeader(
        path: path,
        count: matches.length,
        collapsed: collapsed,
        onTap: () => setState(() {
          if (!_collapsed.remove(path)) _collapsed.add(path);
        }),
      ));
      if (!collapsed) {
        for (final m in matches) {
          rows.add(_MatchRow(match: m, onTap: () => _open(m)));
        }
      }
    }

    return SizedBox(
      width: widget.width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.bg,
          border: Border(right: c.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      translate('content_search'),
                      style: TextStyle(
                        fontSize: 11,
                        color: c.muted,
                        letterSpacing: 0.44,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.folder_outlined, size: 16),
                    color: c.muted,
                    visualDensity: VisualDensity.compact,
                    tooltip: translate('editor_explorer'),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape):
                      widget.onClose,
                },
                child: TextField(
                  controller: _query,
                  focusNode: _queryFocus,
                  style: TextStyle(fontSize: 13, color: c.fg),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: translate('content_search_hint'),
                    suffixIconConstraints:
                        const BoxConstraints(minHeight: 24, minWidth: 0),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Toggle(
                          label: 'Aa',
                          tooltip: translate('content_search_case'),
                          value: _caseSensitive,
                          onChanged: (v) {
                            setState(() => _caseSensitive = v);
                            _scheduleSearch(immediate: true);
                          },
                        ),
                        _Toggle(
                          label: 'ab',
                          underline: true,
                          tooltip: translate('content_search_word'),
                          value: _wholeWord,
                          onChanged: (v) {
                            setState(() => _wholeWord = v);
                            _scheduleSearch(immediate: true);
                          },
                        ),
                        _Toggle(
                          label: '.*',
                          tooltip: translate('content_search_regex'),
                          value: _regex,
                          onChanged: (v) {
                            setState(() => _regex = v);
                            _scheduleSearch(immediate: true);
                          },
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                  onChanged: (_) => _scheduleSearch(),
                  onSubmitted: (_) => _scheduleSearch(immediate: true),
                ),
              ),
            ),
            SizedBox(
              height: 2,
              child: _searching
                  ? LinearProgressIndicator(
                      minHeight: 2,
                      color: c.accent,
                      backgroundColor: Colors.transparent,
                    )
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 6),
              child: Text(
                summary(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: _error != null
                    ? summaryStyle.copyWith(color: c.del)
                    : summaryStyle,
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                children: rows,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.tooltip,
    required this.value,
    required this.onChanged,
    this.underline = false,
  });

  final String label;
  final String tooltip;
  final bool value;
  final bool underline;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.branchi;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => onChanged(!value),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: value ? c.accent.withValues(alpha: 0.18) : null,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: value ? c.accent : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            style: c.mono(fontSize: 11, color: value ? c.fg : c.muted).copyWith(
                  decoration: underline ? TextDecoration.underline : null,
                ),
          ),
        ),
      ),
    );
  }
}

class _FileHeader extends StatelessWidget {
  const _FileHeader({
    required this.path,
    required this.count,
    required this.collapsed,
    required this.onTap,
  });

  final String path;
  final int count;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.branchi;
    final slash = path.lastIndexOf('/');
    final name = path.substring(slash + 1);
    final dir = slash > 0 ? path.substring(0, slash) : '';
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
        child: Row(
          children: [
            SizedBox(
              width: 12,
              child: Text(
                collapsed ? '▸' : '▾',
                style: TextStyle(fontSize: 10, color: c.muted),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: name,
                    style: TextStyle(fontSize: 13, color: c.fg),
                  ),
                  if (dir.isNotEmpty)
                    TextSpan(
                      text: '  $dir',
                      style: TextStyle(fontSize: 11, color: c.muted),
                    ),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: c.hover,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(fontSize: 10, color: c.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.match, required this.onTap});

  final ContentSearchMatch match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.branchi;
    final base = TextStyle(fontSize: 12, color: c.muted);
    final hit = TextStyle(
      fontSize: 12,
      color: c.fg,
      backgroundColor: c.mod.withValues(alpha: 0.3),
    );
    final runes = match.text.runes.toList();
    final spans = <TextSpan>[];
    var pos = 0;
    for (final (start, end) in match.ranges) {
      if (start < pos || end > runes.length) continue;
      if (start > pos) {
        spans.add(TextSpan(text: String.fromCharCodes(runes, pos, start)));
      }
      spans.add(
        TextSpan(text: String.fromCharCodes(runes, start, end), style: hit),
      );
      pos = end;
    }
    if (pos < runes.length) {
      spans.add(TextSpan(text: String.fromCharCodes(runes, pos)));
    }

    return Tooltip(
      message: '${match.path}:${match.line}',
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(28, 3, 8, 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 34,
                child: Text(
                  '${match.line}',
                  style: c.mono(fontSize: 10, color: c.muted),
                ),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(style: base, children: spans),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
