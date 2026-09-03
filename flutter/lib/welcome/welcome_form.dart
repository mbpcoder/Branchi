import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_locale.dart';
import '../repo/git_actions.dart';
import '../repo/recent_repositories_store.dart';
import '../widgets/form_row.dart';

/// The "start page" shown as the content of the default tab and every new
/// tab: pick a local repository, browse recent ones, or clone a remote one.
class WelcomeForm extends StatefulWidget {
  const WelcomeForm({super.key, required this.onRepositoryOpened});

  final ValueChanged<String> onRepositoryOpened;

  @override
  State<WelcomeForm> createState() => _WelcomeFormState();
}

class _WelcomeFormState extends State<WelcomeForm> {
  List<String> _recentRepositories = [];
  bool _isBusy = false;

  final TextEditingController _sourceUrlController = TextEditingController();
  final TextEditingController _repoNameController = TextEditingController();
  final TextEditingController _destinationPathController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRecentRepositories();
  }

  Future<void> _loadRecentRepositories() async {
    final recent = await RecentRepositoriesStore.load();
    if (!mounted) return;
    setState(() => _recentRepositories = recent);
  }

  @override
  void dispose() {
    _sourceUrlController.dispose();
    _repoNameController.dispose();
    _destinationPathController.dispose();
    super.dispose();
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

  Future<void> _pickDestinationPath() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null) return;
    _destinationPathController.text = path;
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
    final sourceUrl = _sourceUrlController.text.trim();
    final destinationPath = _destinationPathController.text.trim();

    if (sourceUrl.isEmpty) {
      _showMessage(translate('source_url_required'));
      return;
    }
    if (destinationPath.isEmpty) {
      _showMessage(translate('destination_path_required'));
      return;
    }

    final repoName = _repoNameController.text.trim().isNotEmpty
        ? _repoNameController.text.trim()
        : GitActions.repoNameFromUrl(sourceUrl);
    final targetDirectory = p.join(destinationPath, repoName);

    setState(() => _isBusy = true);
    final result = await GitActions.clone(
      sourceUrl: sourceUrl,
      destinationDirectory: targetDirectory,
    );
    if (!mounted) return;
    setState(() => _isBusy = false);

    if (!result.isSuccess) {
      _showMessage(result.error ?? translate('not_a_git_repository'));
      return;
    }

    await RecentRepositoriesStore.addOrPromote(targetDirectory);
    _showMessage(translate('repository_cloned'));
    widget.onRepositoryOpened(targetDirectory);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Image.asset(
                  'assets/icon/branchi_logo.png',
                  width: 40,
                  height: 40,
                ),
                const SizedBox(width: 12),
                Text('Branchi', style: Theme.of(context).textTheme.headlineSmall),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              translate('local_repositories'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: _isBusy ? null : _openRepository,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(translate('open_repository')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: _isBusy ? null : _newRepository,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(translate('new_repository')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Text(
              translate('recent_repositories'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (_recentRepositories.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  translate('no_recent_repositories'),
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              )
            else
              ...List.generate(_recentRepositories.length, (index) {
                final path = _recentRepositories[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: InkWell(
                    onTap: _isBusy ? null : () => _openRecentRepository(path),
                    child: Row(
                      children: [
                        Icon(
                          Icons.folder,
                          size: 20,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(path)),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 32),
            Text(
              translate('clone_repository'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            FormRow(
              label: translate('source_url'),
              child: TextField(
                controller: _sourceUrlController,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FormRow(
              label: translate('repository_name'),
              child: TextField(
                controller: _repoNameController,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FormRow(
              label: translate('destination_path'),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _destinationPathController,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _isBusy ? null : _pickDestinationPath,
                    child: const Text('...'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _isBusy ? null : _cloneRepository,
                child: _isBusy
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(translate('cloning')),
                        ],
                      )
                    : Text(translate('clone')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
