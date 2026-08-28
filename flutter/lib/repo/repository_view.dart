import 'package:flutter/material.dart';

import 'branch_sidebar.dart';
import 'column_resize_handle.dart';
import 'commit_detail.dart';
import 'commit_list.dart';
import 'git_actions.dart';
import 'models.dart';
import 'panel_layout_store.dart';

const double _defaultSidebarWidth = 220;
const double _defaultCommitListWidth = 360;
const double _minColumnWidth = 160;
const double _maxColumnWidth = 640;

/// The main view for an opened repository: a branch sidebar, the commit
/// log, and a detail/diff pane for the selected commit.
class RepositoryView extends StatefulWidget {
  const RepositoryView({super.key, required this.path});

  final String path;

  @override
  State<RepositoryView> createState() => _RepositoryViewState();
}

class _RepositoryViewState extends State<RepositoryView> {
  List<CommitEntry> _commits = [];
  List<BranchEntry> _branches = [];
  bool _isLoading = true;
  String? _loadError;

  CommitEntry? _selectedCommit;
  List<DiffFileEntry> _diffFiles = [];
  bool _isDiffLoading = false;
  String? _diffError;
  String? _selectedFilePath;

  double _sidebarWidth = _defaultSidebarWidth;
  double _commitListWidth = _defaultCommitListWidth;

  @override
  void initState() {
    super.initState();
    _loadRepository();
    _loadPanelLayout();
  }

  Future<void> _loadPanelLayout() async {
    final results = await Future.wait([
      PanelLayoutStore.loadSidebarWidth(),
      PanelLayoutStore.loadCommitListWidth(),
    ]);
    if (!mounted) return;
    setState(() {
      _sidebarWidth = results[0] ?? _defaultSidebarWidth;
      _commitListWidth = results[1] ?? _defaultCommitListWidth;
    });
  }

  void _resizeSidebar(double delta) {
    setState(() {
      _sidebarWidth = (_sidebarWidth + delta)
          .clamp(_minColumnWidth, _maxColumnWidth);
    });
  }

  void _resizeCommitList(double delta) {
    setState(() {
      _commitListWidth = (_commitListWidth + delta)
          .clamp(_minColumnWidth, _maxColumnWidth);
    });
  }

  @override
  void didUpdateWidget(covariant RepositoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _selectedCommit = null;
      _diffFiles = [];
      _selectedFilePath = null;
      _loadRepository();
    }
  }

  Future<void> _loadRepository() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final results = await Future.wait([
        GitActions.log(widget.path),
        GitActions.branches(widget.path),
      ]);
      if (!mounted) return;
      setState(() {
        _commits = results[0] as List<CommitEntry>;
        _branches = results[1] as List<BranchEntry>;
        _isLoading = false;
      });
      if (_commits.isNotEmpty) {
        _selectCommit(_commits.first);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = error.toString();
      });
    }
  }

  Future<void> _selectCommit(CommitEntry commit) async {
    setState(() {
      _selectedCommit = commit;
      _diffFiles = [];
      _selectedFilePath = null;
      _isDiffLoading = true;
      _diffError = null;
    });

    try {
      final diff = await GitActions.commitDiff(widget.path, commit.id);
      if (!mounted || _selectedCommit?.id != commit.id) return;
      setState(() {
        _diffFiles = diff;
        _selectedFilePath = diff.isEmpty ? null : diff.first.path;
        _isDiffLoading = false;
      });
    } catch (error) {
      if (!mounted || _selectedCommit?.id != commit.id) return;
      setState(() {
        _isDiffLoading = false;
        _diffError = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(child: Text('Failed to load repository: $_loadError'));
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BranchSidebar(branches: _branches, width: _sidebarWidth),
        ColumnResizeHandle(
          onDrag: _resizeSidebar,
          onDragEnd: () => PanelLayoutStore.saveSidebarWidth(_sidebarWidth),
        ),
        SizedBox(
          width: _commitListWidth,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: CommitList(
              commits: _commits,
              selectedId: _selectedCommit?.id,
              onSelect: _selectCommit,
            ),
          ),
        ),
        ColumnResizeHandle(
          onDrag: _resizeCommitList,
          onDragEnd: () =>
              PanelLayoutStore.saveCommitListWidth(_commitListWidth),
        ),
        Expanded(
          child: CommitDetail(
            commit: _selectedCommit,
            diffFiles: _diffFiles,
            isLoading: _isDiffLoading,
            error: _diffError,
            selectedFilePath: _selectedFilePath,
            onSelectFile: (path) => setState(() => _selectedFilePath = path),
          ),
        ),
      ],
    );
  }
}
