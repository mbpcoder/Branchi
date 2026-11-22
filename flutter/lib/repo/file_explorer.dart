import 'dart:io';

/// Opens the OS's file explorer (Explorer/Finder/the default file manager)
/// at [path]. Returns null on success, or an error message on failure.
Future<String?> openInFileExplorer(String path) async {
  try {
    final ProcessResult result;
    if (Platform.isWindows) {
      result = await Process.run('explorer.exe', [path]);
      // explorer.exe returns a non-zero exit code even on success, so its
      // exit code can't be used to detect failure here.
      return null;
    } else if (Platform.isMacOS) {
      result = await Process.run('open', [path]);
    } else {
      result = await Process.run('xdg-open', [path]);
    }
    if (result.exitCode != 0) {
      final stderr = result.stderr.toString().trim();
      return stderr.isEmpty ? 'Failed to open file explorer.' : stderr;
    }
    return null;
  } catch (e) {
    return e.toString();
  }
}

/// Opens the OS's file manager with [path] (a file or folder) selected.
/// Returns null on success, or an error message on failure.
Future<String?> revealInFileExplorer(String path) async {
  try {
    if (Platform.isWindows) {
      // explorer.exe exits non-zero even on success; see above.
      await Process.run('explorer.exe', ['/select,', path]);
      return null;
    }
    if (Platform.isMacOS) {
      final result = await Process.run('open', ['-R', path]);
      if (result.exitCode == 0) return null;
      final stderr = result.stderr.toString().trim();
      return stderr.isEmpty ? 'Failed to open Finder.' : stderr;
    }
    // Linux: file managers implementing the freedesktop FileManager1
    // interface (Nautilus, Dolphin, Nemo, ...) can select the item;
    // otherwise just open its folder.
    final result = await Process.run('dbus-send', [
      '--session',
      '--print-reply',
      '--dest=org.freedesktop.FileManager1',
      '--type=method_call',
      '/org/freedesktop/FileManager1',
      'org.freedesktop.FileManager1.ShowItems',
      'array:string:${Uri.file(path)}',
      'string:',
    ]);
    if (result.exitCode == 0) return null;
  } catch (_) {
    // Fall through to opening the parent folder.
  }
  final parent = FileSystemEntity.isDirectorySync(path)
      ? path
      : File(path).parent.path;
  return openInFileExplorer(parent);
}
