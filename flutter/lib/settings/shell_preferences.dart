import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shell_detection.dart';

const String _prefsKey = 'branchi_configured_shells';
const String _defaultKey = 'branchi_default_shell';

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
/// New terminal tabs use [resolvedDefault]. When the combined list ([all])
/// is empty, the terminal falls back to the platform default shell
/// ([defaultShell] in `terminal_session.dart`). When there are two or more
/// shells, the "new terminal tab" action also offers a picker.
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

  /// Executable of the shell the user picked as default in settings, or
  /// null for automatic. Persisted across launches.
  static final ValueNotifier<String?> defaultExecutable =
      ValueNotifier<String?>(null);

  /// The shell new terminal tabs use: the user's pick if it's still
  /// available, otherwise auto-detected — PowerShell 7 (`pwsh`), then
  /// Windows PowerShell, then the first known shell. Null when no shells
  /// are known (the terminal then falls back to the platform default).
  static ShellDefinition? get resolvedDefault {
    final shells = all;
    final picked = defaultExecutable.value;
    if (picked != null) {
      for (final shell in shells) {
        if (shell.executable == picked) return shell;
      }
    }
    return autoDefault;
  }

  /// The automatic choice, ignoring the user's pick.
  static ShellDefinition? get autoDefault {
    final shells = all;
    for (final exe in const ['pwsh.exe', 'powershell.exe']) {
      for (final shell in shells) {
        if (shell.executable.toLowerCase().endsWith(exe)) return shell;
      }
    }
    return shells.isEmpty ? null : shells.first;
  }

  static Future<void> setDefault(String? executable) async {
    defaultExecutable.value = executable;
    final prefs = await SharedPreferences.getInstance();
    if (executable == null) {
      await prefs.remove(_defaultKey);
    } else {
      await prefs.setString(_defaultKey, executable);
    }
  }

  static Future<void> load() async {
    detected.value = await detectInstalledShells();

    final prefs = await SharedPreferences.getInstance();
    defaultExecutable.value = prefs.getString(_defaultKey);
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
