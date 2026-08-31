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
