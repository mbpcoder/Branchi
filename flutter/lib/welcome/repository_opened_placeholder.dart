import 'package:flutter/material.dart';

/// A minimal placeholder shown once a tab has a repository attached, until
/// an actual repository view (log, diff, branches, ...) is built.
class RepositoryOpenedPlaceholder extends StatelessWidget {
  const RepositoryOpenedPlaceholder({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open,
              size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(path, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
