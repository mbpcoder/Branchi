import 'dart:convert';
import 'dart:io';

import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

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
  if (Platform.isWindows) {
    return Platform.environment['COMSPEC'] ?? 'powershell.exe';
  }
  return Platform.environment['SHELL'] ?? '/bin/bash';
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
    shellExecutable ?? defaultShell(),
    columns: 80,
    rows: 24,
    workingDirectory: workingDirectory ?? Directory.current.path,
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
