import 'dart:io';

import 'shell_preferences.dart';

/// Probes the current OS for shells that are installed but not explicitly
/// configured by the user, so the terminal panel has sensible choices out
/// of the box (matching what the platform's own terminal apps offer).
///
/// Each platform gets its own list of candidates below. To support another
/// OS later, add a case to [detectInstalledShells] with its own candidate
/// list — the rest of the app (settings page, terminal panel) only ever
/// deals with the resulting [ShellDefinition]s and doesn't need to change.
Future<List<ShellDefinition>> detectInstalledShells() async {
  if (Platform.isWindows) return _detectWindowsShells();
  if (Platform.isLinux || Platform.isMacOS) return _detectPosixShells();
  return const [];
}

/// One shell worth probing for: a display name plus a way to find its
/// executable on this machine. [resolve] returns null when the shell isn't
/// installed.
class _ShellCandidate {
  const _ShellCandidate(this.name, this.resolve);

  final String name;
  final Future<String?> Function() resolve;
}

Future<List<ShellDefinition>> _runCandidates(
  List<_ShellCandidate> candidates,
) async {
  final found = <ShellDefinition>[];
  for (final candidate in candidates) {
    final executable = await candidate.resolve();
    if (executable != null) {
      found.add(ShellDefinition(name: candidate.name, executable: executable));
    }
  }
  return found;
}

/// Looks up [executable] on the system `PATH`, returning the first match or
/// null if it isn't found. Works with `where` (Windows) or `which`
/// (POSIX).
Future<String?> _findOnPath(String executable) async {
  try {
    final result = await Process.run(
      Platform.isWindows ? 'where' : 'which',
      [executable],
    );
    if (result.exitCode != 0) return null;
    final lines = (result.stdout as String)
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
    return lines.isEmpty ? null : lines.first;
  } catch (_) {
    // `where`/`which` themselves missing, or the process couldn't start.
    return null;
  }
}

Future<String?> _firstExistingPath(List<String> paths) async {
  for (final path in paths) {
    if (await File(path).exists()) return path;
  }
  return null;
}

Future<List<ShellDefinition>> _detectWindowsShells() async {
  final programFiles = Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
  final programFilesX86 =
      Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';
  final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';

  final candidates = [
    _ShellCandidate('Command Prompt', () async {
      final comspec = Platform.environment['COMSPEC'];
      if (comspec != null && await File(comspec).exists()) return comspec;
      return _firstExistingPath(['$systemRoot\\System32\\cmd.exe']);
    }),
    _ShellCandidate(
      'Windows PowerShell',
      () async =>
          await _findOnPath('powershell.exe') ??
          _firstExistingPath([
            '$systemRoot\\System32\\WindowsPowerShell\\v1.0\\powershell.exe',
          ]),
    ),
    // "posh": PowerShell (Core), the cross-platform successor to Windows
    // PowerShell, installed as `pwsh`.
    _ShellCandidate(
      'PowerShell',
      () async =>
          await _findOnPath('pwsh.exe') ??
          _firstExistingPath([
            '$programFiles\\PowerShell\\7\\pwsh.exe',
          ]),
    ),
    _ShellCandidate(
      'Git Bash',
      () async => _firstExistingPath([
        '$programFiles\\Git\\bin\\bash.exe',
        '$programFiles\\Git\\git-bash.exe',
        '$programFilesX86\\Git\\bin\\bash.exe',
        '$programFilesX86\\Git\\git-bash.exe',
      ]),
    ),
    _ShellCandidate(
      'WSL',
      () async =>
          _firstExistingPath(['$systemRoot\\System32\\wsl.exe']),
    ),
  ];

  return _runCandidates(candidates);
}

/// Placeholder for future macOS/Linux support: probes the common POSIX
/// shells so `ShellPreferences` already works there once the rest of the
/// app (e.g. [defaultShell] in `terminal_session.dart`) is extended.
Future<List<ShellDefinition>> _detectPosixShells() async {
  final candidates = [
    _ShellCandidate('Bash', () => _findOnPath('bash')),
    _ShellCandidate('Zsh', () => _findOnPath('zsh')),
    _ShellCandidate('Fish', () => _findOnPath('fish')),
    _ShellCandidate('sh', () => _findOnPath('sh')),
  ];

  return _runCandidates(candidates);
}
