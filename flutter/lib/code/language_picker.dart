import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_locale.dart';
import '../theme/app_theme.dart';
import 'file_languages.dart';

/// Returned by [showLanguagePicker] when the user wants auto-detection
/// back instead of a hand-picked language.
const String kAutoDetectLanguage = '__auto__';

/// Shows a searchable list of languages. Returns the chosen grammar key,
/// [kAutoDetectLanguage], or null if dismissed.
Future<String?> showLanguagePicker(
  BuildContext context, {
  required FileLanguage? current,
  required FileLanguage? detected,
  required bool hasOverride,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _LanguagePickerDialog(
      current: current,
      detected: detected,
      hasOverride: hasOverride,
    ),
  );
}

class _LanguagePickerDialog extends StatefulWidget {
  const _LanguagePickerDialog({
    required this.current,
    required this.detected,
    required this.hasOverride,
  });

  final FileLanguage? current;
  final FileLanguage? detected;
  final bool hasOverride;

  @override
  State<_LanguagePickerDialog> createState() => _LanguagePickerDialogState();
}

class _LanguagePickerDialogState extends State<_LanguagePickerDialog> {
  static final List<FileLanguage> _all = allPickableLanguages();

  final _query = TextEditingController();
  int _highlighted = 0;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Entries to show: "Auto detect" (when a language was picked by hand),
  /// then languages whose label or key contains the query.
  List<({String value, String label})> get _entries {
    final q = _query.text.trim().toLowerCase();
    final detectedLabel = widget.detected?.label ?? kPlainText.label;
    return [
      if (widget.hasOverride && q.isEmpty)
        (
          value: kAutoDetectLanguage,
          label: translate('editor_auto_detect')
              .replaceAll('{language}', detectedLabel),
        ),
      for (final lang in _all)
        if (q.isEmpty ||
            lang.label.toLowerCase().contains(q) ||
            lang.grammar.contains(q))
          (value: lang.grammar, label: lang.label),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.branchi;
    final entries = _entries;
    if (_highlighted >= entries.length) _highlighted = 0;

    void choose(int index) {
      if (index < entries.length) Navigator.pop(context, entries[index].value);
    }

    return Dialog(
      alignment: const Alignment(0, -0.6),
      child: SizedBox(
        width: 420,
        height: 420,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowDown): () => setState(
                  () => _highlighted =
                      (_highlighted + 1).clamp(0, entries.length - 1),
                ),
            const SingleActivator(LogicalKeyboardKey.arrowUp): () => setState(
                  () => _highlighted =
                      (_highlighted - 1).clamp(0, entries.length - 1),
                ),
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _query,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: translate('editor_select_language'),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() => _highlighted = 0),
                  onSubmitted: (_) => choose(_highlighted),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: entries.length,
                  itemExtent: 32,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final isCurrent = entry.value ==
                        (widget.current ?? kPlainText).grammar;
                    return InkWell(
                      onTap: () => choose(index),
                      child: Container(
                        color: index == _highlighted ? c.hover : null,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        alignment: AlignmentDirectional.centerStart,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                entry.label,
                                style: TextStyle(fontSize: 13, color: c.fg),
                              ),
                            ),
                            if (isCurrent)
                              Icon(Icons.check, size: 14, color: c.accent),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
