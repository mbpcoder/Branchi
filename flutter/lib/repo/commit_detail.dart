import 'package:flutter/material.dart';

import 'models.dart';

/// Right-hand pane: metadata for the selected commit plus a per-file diff
/// viewer, or a loading/empty/error state.
class CommitDetail extends StatelessWidget {
  const CommitDetail({
    super.key,
    required this.commit,
    required this.diffFiles,
    required this.isLoading,
    required this.error,
    required this.selectedFilePath,
    required this.onSelectFile,
  });

  final CommitEntry? commit;
  final List<DiffFileEntry> diffFiles;
  final bool isLoading;
  final String? error;
  final String? selectedFilePath;
  final ValueChanged<String> onSelectFile;

  @override
  Widget build(BuildContext context) {
    final commit = this.commit;
    if (commit == null) {
      return const Center(child: Text('Select a commit to see its changes'));
    }
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(child: Text('Failed to load diff: $error'));
    }

    final selectedFile = diffFiles.isEmpty
        ? null
        : diffFiles.firstWhere(
            (f) => f.path == selectedFilePath,
            orElse: () => diffFiles.first,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(commit.summary, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                '${commit.author} <${commit.email}> · ${commit.id}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 240,
                child: ListView(
                  children: [
                    for (final file in diffFiles)
                      _FileTile(
                        file: file,
                        selected: file.path == selectedFile?.path,
                        onTap: () => onSelectFile(file.path),
                      ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: selectedFile == null
                    ? const Center(child: Text('No file changes'))
                    : _PatchView(file: selectedFile),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.file,
    required this.selected,
    required this.onTap,
  });

  final DiffFileEntry file;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.secondaryContainer : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _StatusBadge(status: file.status),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  file.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              Text(
                '+${file.additions}',
                style: const TextStyle(color: Colors.green, fontSize: 12),
              ),
              const SizedBox(width: 4),
              Text(
                '-${file.deletions}',
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final FileChangeStatus status;

  @override
  Widget build(BuildContext context) {
    final (letter, color) = switch (status) {
      FileChangeStatus.new_ => ('A', Colors.green),
      FileChangeStatus.modified => ('M', Colors.orange),
      FileChangeStatus.deleted => ('D', Colors.red),
      FileChangeStatus.renamed => ('R', Colors.blue),
      FileChangeStatus.typechange => ('T', Colors.purple),
      FileChangeStatus.conflicted => ('!', Colors.red),
    };
    return SizedBox(
      width: 16,
      child: Text(
        letter,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _PatchView extends StatelessWidget {
  const _PatchView({required this.file});

  final DiffFileEntry file;

  @override
  Widget build(BuildContext context) {
    final lines = file.patch.split('\n');
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: SelectableText.rich(
          TextSpan(
            children: [
              for (final line in lines) _spanFor(line),
            ],
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        ),
      ),
    );
  }

  TextSpan _spanFor(String line) {
    Color? color;
    if (line.startsWith('+')) {
      color = Colors.green.shade700;
    } else if (line.startsWith('-')) {
      color = Colors.red.shade700;
    }
    return TextSpan(text: '$line\n', style: TextStyle(color: color));
  }
}
