import 'dart:convert';
import 'dart:io';

import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

import '../settings/shell_preferences.dart';

/// A running shell session backing one terminal tab.
class TerminalSession {
  TerminalSession({
    required this.id,
    required this.title,
    required this.pty,
    required this.terminal,
  });

  final int id;
  String title;
  final Pty pty;
  final Terminal terminal;

  void dispose() {
    pty.kill();
  }
}

/// The shell to launch inside the embedded terminal.
String defaultShell() {
  final preferred = ShellPreferences.resolvedDefault;
  if (preferred != null) return preferred.executable;
  if (Platform.isWindows) {
    return Platform.environment['COMSPEC'] ?? 'powershell.exe';
  }
  if (Platform.isMacOS) return Platform.environment['SHELL'] ?? '/bin/zsh';
  return Platform.environment['SHELL'] ?? '/bin/bash';
}

/// Apps started from Finder/the Dock get a minimal PATH (no Homebrew etc.),
/// so on macOS start a login shell, like Terminal.app does, to load the
/// user's profile.
List<String> _shellArguments() => Platform.isMacOS ? const ['-l'] : const [];

/// flutter_pty builds the Windows command line by joining the executable and
/// arguments with spaces, without quoting. A path like
/// `C:\Program Files\PowerShell\7\pwsh.exe` then reaches the shell split
/// at the space (pwsh tries to run `C:\Program` as a script), so quote any
/// part that contains whitespace.
String _quoteForWindows(String value) {
  if (!Platform.isWindows) return value;
  if (value.startsWith('"') && value.endsWith('"')) return value;
  if (!value.contains(RegExp(r'\s'))) return value;
  return '"$value"';
}

/// Spawns a real shell in a pseudo-terminal and wires it up to an in-app
/// [Terminal], so the terminal panel runs inside the app itself rather than
/// opening a separate OS terminal window (which isn't available in headless
/// / containerized environments).
TerminalSession spawnTerminalSession(
  int id,
  String title, {
  String? workingDirectory,
  String? shellExecutable,
}) {
  final pty = Pty.start(
    _quoteForWindows(shellExecutable ?? defaultShell()),
    arguments: [for (final arg in _shellArguments()) _quoteForWindows(arg)],
    columns: 80,
    rows: 24,
    workingDirectory: workingDirectory ?? Directory.current.path,
    // Pass the app's full environment explicitly so the shell gets the
    // user's PATH, %APPDATA%, %USERPROFILE% etc. — without these, tools
    // like Node version managers fail to find their config.
    environment: Platform.environment,
  );

  final terminal = Terminal(maxLines: 10000);
  terminal.onOutput = (data) => pty.write(const Utf8Encoder().convert(data));
  terminal.onResize = (width, height, pixelWidth, pixelHeight) {
    pty.resize(height, width);
  };

  pty.output
      .cast<List<int>>()
      .transform(const Utf8Decoder(allowMalformed: true))
      .listen(terminal.write);

  return TerminalSession(id: id, title: title, pty: pty, terminal: terminal);
}
