import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The app-wide keyboard shortcuts. They're matched in a
/// [HardwareKeyboard] handler (see [AppShortcuts.match]), ahead of the
/// focus system, so they also work while the terminal or the code editor
/// has focus.
enum AppShortcut {
  terminal,
  activity,
  history,
  changes,
  files,
  report,
  nextTab,
  previousTab,
  goToTab,
}

/// A matched shortcut; [tabIndex] is set for [AppShortcut.goToTab].
typedef ShortcutMatch = ({AppShortcut shortcut, int? tabIndex});

class AppShortcuts {
  AppShortcuts._();

  static bool get _isMac => defaultTargetPlatform == TargetPlatform.macOS;

  static String get _primary => _isMac ? '⌘' : 'Ctrl';
  static String get _ctrl => _isMac ? '⌃' : 'Ctrl';
  static String get _alt => _isMac ? '⌥' : 'Alt';
  static String get _shift => _isMac ? '⇧' : 'Shift';

  /// The keys to press, as shown to the user: `['Alt', 'F12']`.
  static List<String> keys(AppShortcut shortcut) => switch (shortcut) {
        AppShortcut.terminal => [_alt, 'F12'],
        AppShortcut.activity => [_alt, 'F9'],
        AppShortcut.history => [_primary, '1'],
        AppShortcut.changes => [_primary, '2'],
        AppShortcut.files => [_primary, '3'],
        AppShortcut.report => [_primary, '4'],
        AppShortcut.nextTab => [_ctrl, 'Tab'],
        AppShortcut.previousTab => [_ctrl, _shift, 'Tab'],
        AppShortcut.goToTab => [_alt, '1–9'],
      };

  /// "Alt+F12" (or "⌥F12" on macOS), for tooltips.
  static String label(AppShortcut shortcut) => _join(keys(shortcut));

  /// "Alt+3" for the third repo tab; null past the ninth.
  static String? tabLabel(int index) =>
      index < 9 ? _join([_alt, '${index + 1}']) : null;

  static String _join(List<String> keys) => keys.join(_isMac ? '' : '+');

  static final _sectionDigits = {
    PhysicalKeyboardKey.digit1: AppShortcut.history,
    PhysicalKeyboardKey.digit2: AppShortcut.changes,
    PhysicalKeyboardKey.digit3: AppShortcut.files,
    PhysicalKeyboardKey.digit4: AppShortcut.report,
  };

  static const _tabDigits = [
    PhysicalKeyboardKey.digit1,
    PhysicalKeyboardKey.digit2,
    PhysicalKeyboardKey.digit3,
    PhysicalKeyboardKey.digit4,
    PhysicalKeyboardKey.digit5,
    PhysicalKeyboardKey.digit6,
    PhysicalKeyboardKey.digit7,
    PhysicalKeyboardKey.digit8,
    PhysicalKeyboardKey.digit9,
  ];

  /// The shortcut [event] presses, if any. Digits are matched by physical
  /// key, so they work on any keyboard layout (Persian, Arabic, ...).
  static ShortcutMatch? match(KeyEvent event) {
    if (event is! KeyDownEvent) return null;
    final keyboard = HardwareKeyboard.instance;
    final ctrl = keyboard.isControlPressed;
    final alt = keyboard.isAltPressed;
    final shift = keyboard.isShiftPressed;
    final meta = keyboard.isMetaPressed;
    final primary = _isMac ? meta && !ctrl : ctrl && !meta;
    final altOnly = alt && !ctrl && !shift && !meta;

    if (altOnly && event.logicalKey == LogicalKeyboardKey.f12) {
      return (shortcut: AppShortcut.terminal, tabIndex: null);
    }
    if (altOnly && event.logicalKey == LogicalKeyboardKey.f9) {
      return (shortcut: AppShortcut.activity, tabIndex: null);
    }
    if (primary && !alt && !shift) {
      final section = _sectionDigits[event.physicalKey];
      if (section != null) return (shortcut: section, tabIndex: null);
    }
    if (ctrl && !alt && !meta && event.logicalKey == LogicalKeyboardKey.tab) {
      return (
        shortcut: shift ? AppShortcut.previousTab : AppShortcut.nextTab,
        tabIndex: null,
      );
    }
    if (altOnly) {
      final index = _tabDigits.indexOf(event.physicalKey);
      if (index != -1) return (shortcut: AppShortcut.goToTab, tabIndex: index);
    }
    return null;
  }
}
