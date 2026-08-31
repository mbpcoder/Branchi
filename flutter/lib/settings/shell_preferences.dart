import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _prefsKey = 'rustgit_configured_shells';

/// A shell the user can launch in the terminal panel: a display name plus
/// the executable (and optional args) to spawn, e.g. `powershell.exe` or
/// `/bin/zsh`.
@immutable
class ShellDefinition {
  const ShellDefinition({required this.name, required this.executable});

  final String name;
  final String executable;

  Map<String, String> toJson() => {'name': name, 'executable': executable};

  factory ShellDefinition.fromJson(Map<String, dynamic> json) =>
      ShellDefinition(
        name: json['name'] as String,
        executable: json['executable'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is ShellDefinition &&
      other.name == name &&
      other.executable == executable;

  @override
  int get hashCode => Object.hash(name, executable);
}

/// User-configured list of shells that can be launched in the terminal
/// panel, managed from the settings page.
///
/// When empty, the terminal falls back to the platform default shell
/// ([defaultShell] in `terminal_session.dart`). When there's exactly one
/// configured shell, new terminal tabs use it directly. Only when there are
/// two or more does the "new terminal tab" action offer a picker.
class ShellPreferences {
  ShellPreferences._();

  static final ValueNotifier<List<ShellDefinition>> shells =
      ValueNotifier<List<ShellDefinition>>(const []);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_prefsKey);
    if (saved == null) return;
    shells.value = [
      for (final entry in saved)
        ShellDefinition.fromJson(
          jsonDecode(entry) as Map<String, dynamic>,
        ),
    ];
  }

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefsKey,
      [for (final shell in shells.value) jsonEncode(shell.toJson())],
    );
  }

  static Future<void> add(ShellDefinition shell) async {
    shells.value = [...shells.value, shell];
    await _persist();
  }

  static Future<void> removeAt(int index) async {
    final updated = [...shells.value]..removeAt(index);
    shells.value = updated;
    await _persist();
  }
}
