import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_locale.dart';
import '../repo/git_ffi.dart';
import '../theme/app_theme.dart';

/// One search result: a path relative to the root, and which of its
/// characters matched the query.
class _Match {
  _Match(this.path, this.positions);

  factory _Match.fromJson(Map<String, dynamic> json) => _Match(
        json['path'] as String,
        (json['positions'] as List).cast<int>().toSet(),
      );

  final String path;
  final Set<int> positions;
}

/// Runs the search off the UI thread. Top-level, so the isolate closure
/// captures only these arguments and not a widget's state.
Future<List<dynamic>> _findFilesInIsolate(
  GitFfi ffi,
  String root,
  String query,
  bool refresh,
) =>
    Isolate.run(
      () => ffi.findFiles(
        root,
        query,
        limit: _FileSearchDialogState._limit,
        refresh: refresh,
      ),
    );

/// Shows the "go to file" search for files under [rootPath]. Returns the
/// chosen file's absolute path, or null if dismissed.
Future<String?> showFileSearch(BuildContext context, String rootPath) {
  return showDialog<String>(
    context: context,
    builder: (_) => _FileSearchDialog(rootPath: rootPath),
  );
}

class _FileSearchDialog extends StatefulWidget {
  const _FileSearchDialog({required this.rootPath});

  final String rootPath;

  @override
  State<_FileSearchDialog> createState() => _FileSearchDialogState();
}

class _FileSearchDialogState extends State<_FileSearchDialog> {
  static const _limit = 60;

  final _query = TextEditingController();
  final _scroll = ScrollController();
  List<_Match> _results = const [];
  int _highlighted = 0;
  String? _error;

  /// Only the newest search's results are shown, even if an older one
  /// finishes later.
  int _generation = 0;

  /// The first search rebuilds the file list, so new files show up;
  /// keystrokes after it reuse the cached list.
  bool _indexed = false;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final ffi = GitFfi.instanceOrNull;
    if (ffi == null) {
      setState(() => _error = translate('file_search_unavailable'));
      return;
    }
    final generation = ++_generation;
    final root = widget.rootPath;
    final refresh = !_indexed;
    _indexed = true;
    try {
      final raw = await _findFilesInIsolate(ffi, root, query, refresh);
      if (!mounted || generation != _generation) return;
      setState(() {
        _results = raw
            .cast<Map<String, dynamic>>()
            .map(_Match.fromJson)
            .toList();
        _highlighted = 0;
        _error = null;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = error.toString());
    }
  }

  void _move(int delta) {
    if (_results.isEmpty) return;
    setState(() {
      _highlighted = (_highlighted + delta).clamp(0, _results.length - 1);
    });
    // Keep the highlighted row in view.
    const rowHeight = _ResultRow.height;
    if (!_scroll.hasClients) return;
    final top = _highlighted * rowHeight;
    final viewport = _scroll.position.viewportDimension;
    if (top < _scroll.offset) {
      _scroll.jumpTo(top);
    } else if (top + rowHeight > _scroll.offset + viewport) {
      _scroll.jumpTo(top + rowHeight - viewport);
    }
  }

  void _choose(int index) {
    if (index < 0 || index >= _results.length) return;
    Navigator.pop(context, p.joinAll([
      widget.rootPath,
      ..._results[index].path.split('/'),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.branchi;
    return Dialog(
      alignment: const Alignment(0, -0.7),
      child: SizedBox(
        width: 560,
        height: 460,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
            const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
            const SingleActivator(LogicalKeyboardKey.pageDown): () => _move(10),
            const SingleActivator(LogicalKeyboardKey.pageUp): () => _move(-10),
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _query,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: translate('file_search_hint'),
                    prefixIcon: Icon(Icons.search, size: 18, color: c.muted),
                    isDense: true,
                  ),
                  onChanged: _search,
                  onSubmitted: (_) => _choose(_highlighted),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _error!,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.del),
                  ),
                )
              else if (_results.isEmpty && _query.text.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    translate('file_search_no_results'),
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  itemCount: _results.length,
                  itemExtent: _ResultRow.height,
                  itemBuilder: (context, index) => _ResultRow(
                    match: _results[index],
                    highlighted: index == _highlighted,
                    onTap: () => _choose(index),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.match,
    required this.highlighted,
    required this.onTap,
  });

  static const double height = 40;

  final _Match match;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.branchi;
    final path = match.path;
    final slash = path.lastIndexOf('/');
    final nameStart = slash + 1;
    final dir = slash > 0 ? path.substring(0, slash) : '';

    // Positions are character (code point) indices into the whole path.
    final chars = path.runes.toList();
    final nameCharStart = path.substring(0, nameStart).runes.length;

    List<TextSpan> spans(int from, int to, TextStyle base) => [
          for (var i = from; i < to; i++)
            TextSpan(
              text: String.fromCharCode(chars[i]),
              style: match.positions.contains(i)
                  ? base.copyWith(color: c.accent, fontWeight: FontWeight.w600)
                  : base,
            ),
        ];

    final nameStyle = TextStyle(fontSize: 13, color: c.fg);
    final dirStyle = TextStyle(fontSize: 12, color: c.muted);

    return InkWell(
      onTap: onTap,
      child: Container(
        color: highlighted ? c.hover : null,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: AlignmentDirectional.centerStart,
        child: Text.rich(
          TextSpan(children: [
            ...spans(nameCharStart, chars.length, nameStyle),
            if (dir.isNotEmpty) TextSpan(text: '   ', style: dirStyle),
            if (dir.isNotEmpty)
              ...spans(0, nameCharStart - 1, dirStyle),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
