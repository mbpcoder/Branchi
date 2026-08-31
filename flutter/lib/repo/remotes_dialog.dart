import 'package:flutter/material.dart';

import '../l10n/translations.dart';
import 'git_actions.dart';
import 'models.dart';

/// Dialog listing the repository's configured remotes, with actions to add,
/// edit (change URL), and remove them. Opened from the gear icon in the
/// branches sidebar.
Future<void> showRemotesDialog(BuildContext context, String repoPath) {
  return showDialog<void>(
    context: context,
    builder: (context) => _RemotesDialog(repoPath: repoPath),
  );
}

class _RemotesDialog extends StatefulWidget {
  const _RemotesDialog({required this.repoPath});

  final String repoPath;

  @override
  State<_RemotesDialog> createState() => _RemotesDialogState();
}

class _RemotesDialogState extends State<_RemotesDialog> {
  List<RemoteEntry>? _remotes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final remotes = await GitActions.remotes(widget.repoPath);
      if (!mounted) return;
      setState(() {
        _remotes = remotes;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _remotes = const [];
        _error = e.toString();
      });
    }
  }

  Future<void> _addOrEditRemote({RemoteEntry? existing}) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final urlController = TextEditingController(text: existing?.url ?? '');
    final formKey = GlobalKey<FormState>();
    final isEdit = existing != null;

    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          isEdit ? translate('edit_remote') : translate('add_remote'),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                enabled: !isEdit,
                decoration: InputDecoration(labelText: translate('remote_name')),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? translate('remote_name_required')
                    : null,
              ),
              TextFormField(
                controller: urlController,
                decoration: InputDecoration(labelText: translate('remote_url')),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? translate('remote_url_required')
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(translate('cancel')),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.of(context).pop((
                nameController.text.trim(),
                urlController.text.trim(),
              ));
            },
            child: Text(isEdit ? translate('save') : translate('add')),
          ),
        ],
      ),
    );

    if (result == null) return;
    final (name, url) = result;

    final action = isEdit
        ? GitActions.setRemoteUrl(widget.repoPath, name, url)
        : GitActions.addRemote(widget.repoPath, name, url);
    final actionResult = await action;
    if (!mounted) return;
    if (!actionResult.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(actionResult.error!)),
      );
      return;
    }
    await _load();
  }

  Future<void> _removeRemote(RemoteEntry remote) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(translate('remove_remote')),
        content: Text(translate('remove_remote_confirm').replaceAll(
          '{name}',
          remote.name,
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(translate('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(translate('remove')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await GitActions.removeRemote(widget.repoPath, remote.name);
    if (!mounted) return;
    if (!result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error!)),
      );
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final remotes = _remotes;
    return AlertDialog(
      title: Text(translate('git_remotes')),
      content: SizedBox(
        width: 420,
        child: remotes == null
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (remotes.isEmpty && _error == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(translate('no_remotes_configured')),
                    ),
                  for (final remote in remotes)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.cloud_outlined),
                      title: Text(remote.name),
                      subtitle: Text(remote.url),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: translate('edit_remote'),
                            onPressed: () =>
                                _addOrEditRemote(existing: remote),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: translate('remove_remote'),
                            onPressed: () => _removeRemote(remote),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => _addOrEditRemote(),
          icon: const Icon(Icons.add),
          label: Text(translate('add_remote')),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(translate('close')),
        ),
      ],
    );
  }
}
