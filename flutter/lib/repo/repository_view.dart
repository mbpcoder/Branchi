import 'package:flutter/material.dart';

import 'branch_sidebar.dart';
import 'commit_detail.dart';
import 'commit_list.dart';
import 'git_actions.dart';
import 'models.dart';

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

  @override
  void initState() {
    super.initState();
    _loadRepository();
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
        BranchSidebar(branches: _branches),
        SizedBox(
          width: 360,
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
