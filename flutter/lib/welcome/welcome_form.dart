import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_locale.dart';
import '../repo/git_actions.dart';
import '../repo/recent_repositories_store.dart';
import '../theme/app_theme.dart';
import '../widgets/form_row.dart';

/// The "start page" shown as the content of the default tab and every new
/// tab: a centered 560px column with "Open folder" / "Clone" / "New repo"
/// and the recent repositories. Cloning happens in a dialog.
class WelcomeForm extends StatefulWidget {
  const WelcomeForm({super.key, required this.onRepositoryOpened});

  final ValueChanged<String> onRepositoryOpened;

  @override
  State<WelcomeForm> createState() => _WelcomeFormState();
}

class _WelcomeFormState extends State<WelcomeForm> {
  List<String> _recentRepositories = [];

  /// Current branch of each recent repository, filled in lazily.
  final Map<String, String> _recentBranches = {};
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _loadRecentRepositories();
  }

  Future<void> _loadRecentRepositories() async {
    final recent = await RecentRepositoriesStore.load();
    if (!mounted) return;
    setState(() => _recentRepositories = recent);
    _loadRecentBranches(recent);
  }

  Future<void> _loadRecentBranches(List<String> paths) async {
    for (final path in paths) {
      if (!GitActions.isGitRepository(path)) continue;
      try {
        final branches = await GitActions.branches(path);
        final head = branches.where((b) => b.isHead && !b.isRemote);
        if (head.isEmpty || !mounted) continue;
        setState(() => _recentBranches[path] = head.first.name);
      } catch (_) {
        // Branch is optional decoration; ignore failures.
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openRepository() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null) return;

    if (!GitActions.isGitRepository(path)) {
      _showMessage(translate('not_a_git_repository'));
      return;
    }

    await RecentRepositoriesStore.addOrPromote(path);
    widget.onRepositoryOpened(path);
  }

  Future<void> _newRepository() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null) return;

    setState(() => _isBusy = true);
    final result = await GitActions.init(path);
    if (!mounted) return;
    setState(() => _isBusy = false);

    if (!result.isSuccess) {
      _showMessage(result.error ?? translate('not_a_git_repository'));
      return;
    }

    await RecentRepositoriesStore.addOrPromote(path);
    _showMessage(translate('repository_created'));
    widget.onRepositoryOpened(path);
  }

  Future<void> _openRecentRepository(String path) async {
    if (!GitActions.isGitRepository(path)) {
      _showMessage(translate('repository_no_longer_exists'));
      final updated = await RecentRepositoriesStore.remove(path);
      if (!mounted) return;
      setState(() => _recentRepositories = updated);
      return;
    }
    await RecentRepositoriesStore.addOrPromote(path);
    widget.onRepositoryOpened(path);
  }

  Future<void> _cloneRepository() async {
    final targetDirectory = await showDialog<String>(
      context: context,
      builder: (context) => const _CloneDialog(),
    );
    if (targetDirectory == null || !mounted) return;
    await RecentRepositoriesStore.addOrPromote(targetDirectory);
    _showMessage(translate('repository_cloned'));
    widget.onRepositoryOpened(targetDirectory);
  }

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (constraints.maxHeight - 96).clamp(0, double.infinity),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Branchi',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.56,
                      color: b.fg,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    translate('welcome_subtitle'),
                    style: TextStyle(color: b.muted),
                  ),
                  const SizedBox(height: 36),
                  Row(
                    children: [
                      Expanded(
                        child: _StartButton(
                          label: translate('open_folder'),
                          solid: true,
                          onPressed: _isBusy ? null : _openRepository,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StartButton(
                          label: translate('clone'),
                          onPressed: _isBusy ? null : _cloneRepository,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StartButton(
                          label: translate('new_repo'),
                          onPressed: _isBusy ? null : _newRepository,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 36),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      translate('recent'),
                      style: TextStyle(
                        fontSize: 11,
                        color: b.muted,
                        letterSpacing: 0.44,
                      ),
                    ),
                  ),
                  if (_recentRepositories.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(top: b.hairline),
                      ),
                      child: Text(
                        translate('no_recent_repositories'),
                        style: TextStyle(color: b.muted),
                      ),
                    )
                  else
                    for (final path in _recentRepositories)
                      _RecentRow(
                        path: path,
                        branch: _recentBranches[path],
                        onTap: _isBusy
                            ? null
                            : () => _openRecentRepository(path),
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 40px start-page button: solid ([BranchiColors.fg] fill) or outlined.
class _StartButton extends StatelessWidget {
  const _StartButton({
    required this.label,
    required this.onPressed,
    this.solid = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    );
    const size = Size.fromHeight(40);
    final child = Text(label, overflow: TextOverflow.ellipsis);
    if (solid) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(minimumSize: size, shape: shape),
        child: child,
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(minimumSize: size, shape: shape),
      child: child,
    );
  }
}

class _RecentRow extends StatefulWidget {
  const _RecentRow({
    required this.path,
    required this.branch,
    required this.onTap,
  });

  final String path;
  final String? branch;
  final VoidCallback? onTap;

  @override
  State<_RecentRow> createState() => _RecentRowState();
}

class _RecentRowState extends State<_RecentRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final name = p.basename(widget.path);
    return Semantics(
      button: true,
      child: MouseRegion(
        cursor: widget.onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(border: Border(top: b.hairline)),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? widget.path : name,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: _hovered ? b.accent : b.fg,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.path,
                        style: b.mono(fontSize: 12, color: b.muted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (widget.branch != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    widget.branch!,
                    style: b.mono(fontSize: 12, color: b.muted),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Clone repository" dialog: repository URL and the folder to clone into
/// (Browse picks a parent folder and appends the repository's name, which
/// can then be edited). Pops with the cloned directory on success.
class _CloneDialog extends StatefulWidget {
  const _CloneDialog();

  @override
  State<_CloneDialog> createState() => _CloneDialogState();
}

class _CloneDialogState extends State<_CloneDialog> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();

  /// The folder picked with Browse; while the destination still reads
  /// `<picked>/<name from URL>` it follows URL edits.
  String? _pickedParent;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _urlController.addListener(_syncDestinationWithUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  String _nameFromUrl(String url) =>
      url.trim().isEmpty ? '' : GitActions.repoNameFromUrl(url.trim());

  String? _lastAutoDestination;

  void _syncDestinationWithUrl() {
    final parent = _pickedParent;
    if (parent == null) return;
    final current = _destinationController.text;
    if (current != _lastAutoDestination && current != parent) return;
    final name = _nameFromUrl(_urlController.text);
    final next = name.isEmpty ? parent : p.join(parent, name);
    _lastAutoDestination = next;
    _destinationController.text = next;
  }

  Future<void> _browse() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null) return;
    _pickedParent = path;
    _lastAutoDestination = null;
    _destinationController.text = path;
    _syncDestinationWithUrl();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _clone() async {
    final sourceUrl = _urlController.text.trim();
    var destination = _destinationController.text.trim();
    if (sourceUrl.isEmpty) {
      _showMessage(translate('source_url_required'));
      return;
    }
    if (destination.isEmpty) {
      _showMessage(translate('destination_path_required'));
      return;
    }
    // A bare picked folder means "clone inside it".
    if (destination == _pickedParent) {
      destination = p.join(destination, GitActions.repoNameFromUrl(sourceUrl));
    }

    setState(() => _isBusy = true);
    final result = await GitActions.clone(
      sourceUrl: sourceUrl,
      destinationDirectory: destination,
    );
    if (!mounted) return;
    setState(() => _isBusy = false);

    if (!result.isSuccess) {
      _showMessage(result.error ?? translate('not_a_git_repository'));
      return;
    }
    Navigator.of(context).pop(destination);
  }

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return PopScope(
      canPop: !_isBusy,
      child: Dialog(
        backgroundColor: b.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: b.hairline,
        ),
        child: SizedBox(
          width: 480,
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  translate('clone_repository'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: b.fg,
                  ),
                ),
                const SizedBox(height: 18),
                FormRow(
                  label: translate('repository_url'),
                  child: TextField(
                    controller: _urlController,
                    autofocus: true,
                    enabled: !_isBusy,
                    decoration: const InputDecoration(
                      filled: false,
                      hintText: 'https://github.com/owner/repo.git',
                    ),
                    onSubmitted: (_) => _isBusy ? null : _clone(),
                  ),
                ),
                const SizedBox(height: 18),
                FormRow(
                  label: translate('clone_into'),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _destinationController,
                          enabled: !_isBusy,
                          decoration: const InputDecoration(filled: false),
                          onSubmitted: (_) => _isBusy ? null : _clone(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _isBusy ? null : _browse,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 38),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(translate('browse')),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isBusy
                          ? null
                          : () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: b.muted,
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      child: Text(translate('cancel')),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _isBusy ? null : _clone,
                      style: FilledButton.styleFrom(
                        backgroundColor: b.accent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isBusy
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: b.muted,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(translate('cloning')),
                              ],
                            )
                          : Text(translate('clone')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
