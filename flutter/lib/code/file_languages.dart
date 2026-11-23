import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:re_highlight/languages/all.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A detected or chosen language for a file: the `re_highlight` grammar key
/// used for highlighting, and the label shown in the editor footer.
typedef FileLanguage = ({String grammar, String label});

/// Grammar key meaning "no highlighting".
const String kPlainTextGrammar = 'plaintext';

const FileLanguage kPlainText = (grammar: kPlainTextGrammar, label: 'Plain Text');

/// Exact file names (lowercase) whose type the extension alone doesn't
/// tell, e.g. `composer.lock` is JSON but `yarn.lock` isn't. Checked before
/// [_byExtension].
const Map<String, FileLanguage> _byFileName = {
  'composer.lock': (grammar: 'json', label: 'JSON'),
  'pipfile.lock': (grammar: 'json', label: 'JSON'),
  'flake.lock': (grammar: 'json', label: 'JSON'),
  '.babelrc': (grammar: 'json', label: 'JSON'),
  '.prettierrc': (grammar: 'json', label: 'JSON'),
  '.eslintrc': (grammar: 'json', label: 'JSON'),
  '.jshintrc': (grammar: 'json', label: 'JSON'),
  '.swcrc': (grammar: 'json', label: 'JSON'),
  'artisan': (grammar: 'php', label: 'PHP'),
  'cargo.lock': (grammar: 'ini', label: 'TOML'),
  'pipfile': (grammar: 'ini', label: 'TOML'),
  '.editorconfig': (grammar: 'ini', label: 'INI'),
  '.gitconfig': (grammar: 'ini', label: 'INI'),
  '.npmrc': (grammar: 'ini', label: 'INI'),
  '.gitmodules': (grammar: 'ini', label: 'INI'),
  'dockerfile': (grammar: 'dockerfile', label: 'Dockerfile'),
  'containerfile': (grammar: 'dockerfile', label: 'Dockerfile'),
  'makefile': (grammar: 'makefile', label: 'Makefile'),
  'gnumakefile': (grammar: 'makefile', label: 'Makefile'),
  'cmakelists.txt': (grammar: 'cmake', label: 'CMake'),
  'gemfile': (grammar: 'ruby', label: 'Ruby'),
  'rakefile': (grammar: 'ruby', label: 'Ruby'),
  'podfile': (grammar: 'ruby', label: 'Ruby'),
  'vagrantfile': (grammar: 'ruby', label: 'Ruby'),
  '.bashrc': (grammar: 'bash', label: 'Shell'),
  '.zshrc': (grammar: 'bash', label: 'Shell'),
  '.profile': (grammar: 'bash', label: 'Shell'),
  '.bash_profile': (grammar: 'bash', label: 'Shell'),
};

/// Extension (lowercase, no dot) -> language.
const Map<String, FileLanguage> _byExtension = {
  'dart': (grammar: 'dart', label: 'Dart'),
  'rs': (grammar: 'rust', label: 'Rust'),
  'js': (grammar: 'javascript', label: 'JavaScript'),
  'jsx': (grammar: 'javascript', label: 'JSX'),
  'mjs': (grammar: 'javascript', label: 'JavaScript'),
  'cjs': (grammar: 'javascript', label: 'JavaScript'),
  'ts': (grammar: 'typescript', label: 'TypeScript'),
  'tsx': (grammar: 'typescript', label: 'TSX'),
  'json': (grammar: 'json', label: 'JSON'),
  'jsonc': (grammar: 'json', label: 'JSON'),
  'json5': (grammar: 'json', label: 'JSON'),
  'yaml': (grammar: 'yaml', label: 'YAML'),
  'yml': (grammar: 'yaml', label: 'YAML'),
  'toml': (grammar: 'ini', label: 'TOML'),
  'md': (grammar: 'markdown', label: 'Markdown'),
  'markdown': (grammar: 'markdown', label: 'Markdown'),
  'sh': (grammar: 'bash', label: 'Shell'),
  'bash': (grammar: 'bash', label: 'Shell'),
  'zsh': (grammar: 'bash', label: 'Shell'),
  'ps1': (grammar: 'powershell', label: 'PowerShell'),
  'bat': (grammar: 'dos', label: 'Batch'),
  'cmd': (grammar: 'dos', label: 'Batch'),
  'py': (grammar: 'python', label: 'Python'),
  'rb': (grammar: 'ruby', label: 'Ruby'),
  'go': (grammar: 'go', label: 'Go'),
  'kt': (grammar: 'kotlin', label: 'Kotlin'),
  'kts': (grammar: 'kotlin', label: 'Kotlin'),
  'swift': (grammar: 'swift', label: 'Swift'),
  'c': (grammar: 'c', label: 'C'),
  'h': (grammar: 'c', label: 'C'),
  'cpp': (grammar: 'cpp', label: 'C++'),
  'cc': (grammar: 'cpp', label: 'C++'),
  'hpp': (grammar: 'cpp', label: 'C++'),
  'xml': (grammar: 'xml', label: 'XML'),
  'svg': (grammar: 'xml', label: 'SVG'),
  'html': (grammar: 'xml', label: 'HTML'),
  'htm': (grammar: 'xml', label: 'HTML'),
  'php': (grammar: 'php', label: 'PHP'),
  'css': (grammar: 'css', label: 'CSS'),
  'scss': (grammar: 'scss', label: 'SCSS'),
  'less': (grammar: 'less', label: 'Less'),
  'sql': (grammar: 'sql', label: 'SQL'),
  'cs': (grammar: 'csharp', label: 'C#'),
  'java': (grammar: 'java', label: 'Java'),
  'gradle': (grammar: 'gradle', label: 'Gradle'),
  'ini': (grammar: 'ini', label: 'INI'),
  'cfg': (grammar: 'ini', label: 'INI'),
  'conf': (grammar: 'ini', label: 'INI'),
  'properties': (grammar: 'properties', label: 'Properties'),
  'blade': (grammar: 'php', label: 'Blade'),
  'twig': (grammar: 'twig', label: 'Twig'),
  'vue': (grammar: 'vue', label: 'Vue'),
  'graphql': (grammar: 'graphql', label: 'GraphQL'),
  'gql': (grammar: 'graphql', label: 'GraphQL'),
  'proto': (grammar: 'protobuf', label: 'Protobuf'),
  'diff': (grammar: 'diff', label: 'Diff'),
  'patch': (grammar: 'diff', label: 'Diff'),
  'env': (grammar: 'properties', label: 'Env'),
  'txt': kPlainText,
  'log': kPlainText,
};

/// The language detected from [path]'s file name alone, or null when it
/// isn't recognised.
FileLanguage? detectFileLanguage(String path) {
  final basename = p.basename(path).toLowerCase();
  final byName = _byFileName[basename];
  if (byName != null) return byName;
  if (basename.endsWith('.blade.php')) return _byExtension['blade'];
  if (basename == '.env' || basename.startsWith('.env.')) {
    return _byExtension['env'];
  }
  if (basename.startsWith('dockerfile.')) return _byFileName['dockerfile'];
  final ext = p.extension(basename).replaceFirst('.', '');
  return _byExtension[ext];
}

/// The label shown for grammar key [grammar] when the user picked it by
/// hand, e.g. "JSON" for `json`.
String grammarLabel(String grammar) {
  if (grammar == kPlainTextGrammar) return kPlainText.label;
  final own = _grammarLabels[grammar];
  if (own != null) return own;
  final name = builtinAllLanguages[grammar]?.name;
  if (name != null && name.isNotEmpty && !name.startsWith('.')) return name;
  final key = grammar.replaceAll('-', ' ');
  return key.isEmpty ? grammar : key[0].toUpperCase() + key.substring(1);
}

/// Labels for grammars whose `re_highlight` name is missing or unclear.
const Map<String, String> _grammarLabels = {
  'php': 'PHP',
  'php-template': 'PHP Template',
  'vue': 'Vue',
  'xml': 'HTML / XML',
  'ini': 'INI / TOML',
  'properties': 'Properties',
  'bash': 'Shell (Bash)',
  'dsconfig': 'dsconfig',
  'python-repl': 'Python REPL',
  'gn': 'GN',
};

/// Every grammar the editor can highlight, sorted by label, for the
/// language picker. Plain Text comes first.
List<FileLanguage> allPickableLanguages() {
  final languages = [
    for (final key in builtinAllLanguages.keys)
      if (key != kPlainTextGrammar) (grammar: key, label: grammarLabel(key)),
  ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  return [kPlainText, ...languages];
}

/// Languages the user picked by hand for specific files, keyed by absolute
/// path and persisted, so e.g. a file opens with the same highlighting next
/// time.
class FileLanguageOverrides {
  FileLanguageOverrides._();

  static const _prefsKey = 'editor_language_overrides';

  /// Absolute path -> grammar key.
  static final ValueNotifier<Map<String, String>> overrides =
      ValueNotifier(const {});

  static Future<void>? _loading;

  /// Loads the saved overrides once; later calls return the same future.
  static Future<void> ensureLoaded() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        overrides.value = {
          for (final entry in decoded.entries)
            if (entry.key is String && entry.value is String)
              entry.key as String: entry.value as String,
        };
      }
    } catch (_) {
      // Corrupt or unavailable prefs: fall back to auto-detection.
    }
  }

  /// The language for [path]: the user's choice if any, else the detected
  /// one, else null.
  static FileLanguage? languageFor(String path) {
    final grammar = overrides.value[p.normalize(path)];
    if (grammar != null) return (grammar: grammar, label: grammarLabel(grammar));
    return detectFileLanguage(path);
  }

  /// Whether [path]'s language was picked by hand.
  static bool hasOverride(String path) =>
      overrides.value.containsKey(p.normalize(path));

  /// Remembers [grammar] for [path], or forgets the choice when null.
  static Future<void> set(String path, String? grammar) async {
    final next = Map<String, String>.of(overrides.value);
    final key = p.normalize(path);
    if (grammar == null) {
      next.remove(key);
    } else {
      next[key] = grammar;
    }
    overrides.value = next;
    await _save();
  }

  /// Keeps choices attached to files after [from] (a file or folder) was
  /// moved or renamed to [to].
  static Future<void> movePath(String from, String to) async {
    final src = p.normalize(from);
    final dst = p.normalize(to);
    var changed = false;
    final next = <String, String>{};
    for (final entry in overrides.value.entries) {
      if (entry.key == src || p.isWithin(src, entry.key)) {
        next[p.join(dst, p.relative(entry.key, from: src))] = entry.value;
        changed = true;
      } else {
        next[entry.key] = entry.value;
      }
    }
    if (!changed) return;
    overrides.value = next;
    await _save();
  }

  /// Drops choices for [path] (a file or folder) and everything under it.
  static Future<void> removePath(String path) async {
    final target = p.normalize(path);
    final next = Map<String, String>.of(overrides.value)
      ..removeWhere((key, _) => key == target || p.isWithin(target, key));
    if (next.length == overrides.value.length) return;
    overrides.value = next;
    await _save();
  }

  static Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(overrides.value));
    } catch (_) {
      // Not persisted this time; the in-memory choice still applies.
    }
  }
}
