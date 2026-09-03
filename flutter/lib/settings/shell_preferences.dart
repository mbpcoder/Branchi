import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shell_detection.dart';

const String _prefsKey = 'branchi_configured_shells';

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

/// Shells available in the terminal panel: a list auto-detected from the
/// OS, plus any the user defines by hand in the settings page.
///
/// When the combined list ([all]) is empty, the terminal falls back to the
/// platform default shell ([defaultShell] in `terminal_session.dart`). When
/// there's exactly one shell, new terminal tabs use it directly. Only when
/// there are two or more does the "new terminal tab" action offer a
/// picker.
class ShellPreferences {
  ShellPreferences._();

  /// Shells found on this machine by [detectInstalledShells]. Not
  /// persisted — recomputed on every launch so it stays in sync with what's
  /// actually installed.
  static final ValueNotifier<List<ShellDefinition>> detected =
      ValueNotifier<List<ShellDefinition>>(const []);

  /// Shells the user has added by hand. Persisted across launches.
  static final ValueNotifier<List<ShellDefinition>> custom =
      ValueNotifier<List<ShellDefinition>>(const []);

  /// The combined list terminal tabs pick from: auto-detected shells
  /// followed by user-defined ones.
  static List<ShellDefinition> get all => [...detected.value, ...custom.value];

  static Future<void> load() async {
    detected.value = await detectInstalledShells();

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_prefsKey);
    if (saved == null) return;
    custom.value = [
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
      [for (final shell in custom.value) jsonEncode(shell.toJson())],
    );
  }

  static Future<void> add(ShellDefinition shell) async {
    custom.value = [...custom.value, shell];
    await _persist();
  }

  static Future<void> removeAt(int index) async {
    final updated = [...custom.value]..removeAt(index);
    custom.value = updated;
    await _persist();
  }
}
