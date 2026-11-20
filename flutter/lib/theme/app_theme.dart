import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _prefsKey = 'branchi_theme_mode';
const String _accentPrefsKey = 'branchi_accent_color';
const String _defaultThemeMode = 'system';

/// UI font: Inter, falling back to each platform's system sans-serif.
/// No font assets are bundled, so Inter is used only when it's installed.
const String kUiFontFamily = 'Inter';
const List<String> kUiFontFallback = [
  'Segoe UI',
  'SF Pro Text',
  '.AppleSystemUIFont',
  'Roboto',
  'Ubuntu',
  'Cantarell',
  'Noto Sans',
  'Helvetica Neue',
  'Arial',
];

/// Monospace font for hashes, branch names, paths and code: JetBrains Mono,
/// falling back to common platform monospace fonts.
const String kMonoFontFamily = 'JetBrains Mono';
const List<String> kMonoFontFallback = [
  'Cascadia Code',
  'Cascadia Mono',
  'Consolas',
  'SF Mono',
  'Menlo',
  'Ubuntu Mono',
  'DejaVu Sans Mono',
  'Liberation Mono',
  'Courier New',
  'monospace',
];

/// Base UI font size, in logical pixels.
const double kBaseFontSize = 13;

/// Accent colors the user can pick from (first is the default).
const List<Color> kAccentOptions = [
  Color(0xFF3B82F6), // blue
  Color(0xFF10B981), // green
  Color(0xFFF97316), // orange
  Color(0xFFA855F7), // purple
  Color(0xFF71717A), // graphite
];

const Color kDefaultAccent = Color(0xFF3B82F6);

/// Branchi's design tokens, available from any widget as
/// `context.branchi` (see [BranchiThemeContext]):
///
/// * [bg] - window background (panels are not filled; use this or nothing)
/// * [fg] - primary text
/// * [muted] - secondary text, icons, inactive tabs
/// * [line] - 1px hairline borders and dividers
/// * [hover] - hover/selected row background, segmented-control track
/// * [add] / [del] / [mod] - added / deleted / modified (diffs, status)
/// * [off] - disabled/off indicators
/// * [accent] - user-selectable accent (selection edge, dots, counts)
@immutable
class BranchiColors extends ThemeExtension<BranchiColors> {
  const BranchiColors({
    required this.bg,
    required this.fg,
    required this.muted,
    required this.line,
    required this.hover,
    required this.add,
    required this.del,
    required this.mod,
    required this.off,
    required this.accent,
  });

  factory BranchiColors.dark({Color accent = kDefaultAccent}) => BranchiColors(
        bg: const Color(0xFF0E0E10),
        fg: const Color(0xFFEDEDEF),
        muted: const Color(0xFF8B8B93),
        line: const Color(0xFF1F1F23),
        hover: const Color(0xFF18181B),
        add: const Color(0xFF4ADE80),
        del: const Color(0xFFF87171),
        mod: const Color(0xFFFBBF24),
        off: const Color(0xFF3F3F46),
        accent: accent,
      );

  factory BranchiColors.light({Color accent = kDefaultAccent}) =>
      BranchiColors(
        bg: const Color(0xFFFFFFFF),
        fg: const Color(0xFF18181B),
        muted: const Color(0xFF6B6B73),
        line: const Color(0xFFECECEE),
        hover: const Color(0xFFF4F4F5),
        add: const Color(0xFF15803D),
        del: const Color(0xFFB91C1C),
        mod: const Color(0xFFA16207),
        off: const Color(0xFFD4D4D8),
        accent: accent,
      );

  final Color bg;
  final Color fg;
  final Color muted;
  final Color line;
  final Color hover;
  final Color add;
  final Color del;
  final Color mod;
  final Color off;
  final Color accent;

  /// Subtle diff-line backgrounds (≈8% tint of [add]/[del]).
  Color get addBg => add.withValues(alpha: 0.08);
  Color get delBg => del.withValues(alpha: 0.08);

  /// A 1px hairline border in [line].
  BorderSide get hairline => BorderSide(color: line);

  /// Monospace text style for hashes, branch names, paths and code.
  TextStyle mono({
    double fontSize = 12,
    Color? color,
    FontWeight? fontWeight,
    double? height,
  }) =>
      TextStyle(
        fontFamily: kMonoFontFamily,
        fontFamilyFallback: kMonoFontFallback,
        fontSize: fontSize,
        color: color ?? fg,
        fontWeight: fontWeight,
        height: height,
      );

  @override
  BranchiColors copyWith({
    Color? bg,
    Color? fg,
    Color? muted,
    Color? line,
    Color? hover,
    Color? add,
    Color? del,
    Color? mod,
    Color? off,
    Color? accent,
  }) {
    return BranchiColors(
      bg: bg ?? this.bg,
      fg: fg ?? this.fg,
      muted: muted ?? this.muted,
      line: line ?? this.line,
      hover: hover ?? this.hover,
      add: add ?? this.add,
      del: del ?? this.del,
      mod: mod ?? this.mod,
      off: off ?? this.off,
      accent: accent ?? this.accent,
    );
  }

  @override
  BranchiColors lerp(ThemeExtension<BranchiColors>? other, double t) {
    if (other is! BranchiColors) return this;
    return BranchiColors(
      bg: Color.lerp(bg, other.bg, t)!,
      fg: Color.lerp(fg, other.fg, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      line: Color.lerp(line, other.line, t)!,
      hover: Color.lerp(hover, other.hover, t)!,
      add: Color.lerp(add, other.add, t)!,
      del: Color.lerp(del, other.del, t)!,
      mod: Color.lerp(mod, other.mod, t)!,
      off: Color.lerp(off, other.off, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
    );
  }
}

/// `context.branchi.muted` etc.
extension BranchiThemeContext on BuildContext {
  BranchiColors get branchi {
    final theme = Theme.of(this);
    return theme.extension<BranchiColors>() ??
        (theme.brightness == Brightness.dark
            ? BranchiColors.dark(accent: AppTheme.accent.value)
            : BranchiColors.light(accent: AppTheme.accent.value));
  }
}

/// Global, app-wide selected theme mode (light/dark/system) and accent.
///
/// Mirrors [AppLocale]: simple [ValueNotifier]s persisted via
/// [SharedPreferences] so the rest of the app can rebuild via
/// [ValueListenableBuilder] when the user changes them.
class AppTheme {
  AppTheme._();

  static final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  /// The user-selected accent color; one of [kAccentOptions] by default,
  /// but any color is accepted by [setAccent].
  static final ValueNotifier<Color> accent =
      ValueNotifier<Color>(kDefaultAccent);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey) ?? _defaultThemeMode;
    themeMode.value = _decode(saved);
    final savedAccent = prefs.getInt(_accentPrefsKey);
    if (savedAccent != null) accent.value = Color(savedAccent);
  }

  static Future<void> toggle() async {
    final isDark = themeMode.value == ThemeMode.dark ||
        (themeMode.value == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    await set(isDark ? ThemeMode.light : ThemeMode.dark);
  }

  static Future<void> set(ThemeMode mode) async {
    themeMode.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, _encode(mode));
  }

  static Future<void> setAccent(Color color) async {
    accent.value = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_accentPrefsKey, color.toARGB32());
  }

  static ThemeData light(Color accent) =>
      _build(BranchiColors.light(accent: accent), Brightness.light);

  static ThemeData dark(Color accent) =>
      _build(BranchiColors.dark(accent: accent), Brightness.dark);

  static ThemeData _build(BranchiColors c, Brightness brightness) {
    final onAccent = ThemeData.estimateBrightnessForColor(c.accent) ==
            Brightness.dark
        ? Colors.white
        : Colors.black;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: onAccent,
      primaryContainer: c.accent.withValues(alpha: 0.15),
      onPrimaryContainer: c.fg,
      secondary: c.accent,
      onSecondary: onAccent,
      secondaryContainer: c.hover,
      onSecondaryContainer: c.fg,
      tertiary: c.mod,
      onTertiary: c.bg,
      error: c.del,
      onError: c.bg,
      errorContainer: c.del.withValues(alpha: 0.12),
      onErrorContainer: c.del,
      surface: c.bg,
      onSurface: c.fg,
      onSurfaceVariant: c.muted,
      surfaceDim: c.bg,
      surfaceBright: c.bg,
      surfaceContainerLowest: c.bg,
      surfaceContainerLow: c.bg,
      surfaceContainer: c.bg,
      surfaceContainerHigh: c.hover,
      surfaceContainerHighest: c.hover,
      outline: c.line,
      outlineVariant: c.line,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: c.fg,
      onInverseSurface: c.bg,
      inversePrimary: c.accent,
      surfaceTint: Colors.transparent,
    );

    final radius6 = BorderRadius.circular(6);
    final radius8 = BorderRadius.circular(8);
    final menuShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: c.hairline,
    );
    const menuShadow = Color(0x40000000);

    TextStyle ts(double size, [FontWeight weight = FontWeight.w400]) =>
        TextStyle(fontSize: size, fontWeight: weight, color: c.fg);

    final textTheme = TextTheme(
      displayLarge: ts(32, FontWeight.w600),
      displayMedium: ts(28, FontWeight.w600),
      displaySmall: ts(24, FontWeight.w600),
      headlineLarge: ts(22, FontWeight.w600),
      headlineMedium: ts(20, FontWeight.w600),
      headlineSmall: ts(18, FontWeight.w600),
      titleLarge: ts(18, FontWeight.w600),
      titleMedium: ts(14, FontWeight.w600),
      titleSmall: ts(13, FontWeight.w600),
      bodyLarge: ts(14),
      bodyMedium: ts(kBaseFontSize),
      bodySmall: ts(12).copyWith(color: c.muted),
      labelLarge: ts(13, FontWeight.w500),
      labelMedium: ts(12, FontWeight.w500),
      labelSmall: ts(11, FontWeight.w500).copyWith(color: c.muted),
    );

    final buttonPadding =
        const EdgeInsets.symmetric(horizontal: 12, vertical: 6);
    const buttonMinSize = Size(0, 32);
    final buttonText = ts(kBaseFontSize, FontWeight.w500);
    final buttonShape = RoundedRectangleBorder(borderRadius: radius6);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      fontFamily: kUiFontFamily,
      fontFamilyFallback: kUiFontFallback,
      textTheme: textTheme,
      visualDensity: VisualDensity.compact,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.bg,
      cardColor: c.bg,
      dividerColor: c.line,
      hoverColor: c.hover,
      focusColor: c.hover,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      disabledColor: c.off,
      extensions: [c],
      dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: c.muted, size: 16),
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        foregroundColor: c.fg,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 52,
        centerTitle: false,
        titleTextStyle: ts(14, FontWeight.w600),
        iconTheme: IconThemeData(color: c.muted, size: 18),
        actionsIconTheme: IconThemeData(color: c.muted, size: 18),
        shape: Border(bottom: c.hairline),
      ),
      cardTheme: CardThemeData(
        color: c.bg,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: radius8, side: c.hairline),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shadowColor: menuShadow,
        shape: menuShape,
        titleTextStyle: ts(15, FontWeight.w600),
        contentTextStyle: ts(kBaseFontSize),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shadowColor: menuShadow,
        shape: menuShape,
        textStyle: ts(kBaseFontSize),
        labelTextStyle: WidgetStatePropertyAll(ts(kBaseFontSize)),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(c.bg),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(12),
          shadowColor: const WidgetStatePropertyAll(menuShadow),
          shape: WidgetStatePropertyAll(menuShape),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
        ),
      ),
      menuButtonTheme: MenuButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 32)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 10),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: radius6),
          ),
          textStyle: WidgetStatePropertyAll(ts(kBaseFontSize)),
          foregroundColor: WidgetStatePropertyAll(c.fg),
          overlayColor: WidgetStatePropertyAll(c.hover),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: c.fg, borderRadius: radius6),
        textStyle: ts(12).copyWith(color: c.bg),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        waitDuration: const Duration(milliseconds: 500),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: c.hover,
        hoverColor: Colors.transparent,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        hintStyle: ts(kBaseFontSize).copyWith(color: c.muted),
        labelStyle: ts(kBaseFontSize).copyWith(color: c.muted),
        floatingLabelStyle: ts(12).copyWith(color: c.muted),
        border: OutlineInputBorder(borderRadius: radius8, borderSide: c.hairline),
        enabledBorder:
            OutlineInputBorder(borderRadius: radius8, borderSide: c.hairline),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius8,
          borderSide: BorderSide(color: c.accent),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius8,
          borderSide: BorderSide(color: c.del),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radius8,
          borderSide: BorderSide(color: c.del),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.accent,
        selectionColor: c.accent.withValues(alpha: 0.3),
        selectionHandleColor: c.accent,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.fg,
          disabledForegroundColor: c.off,
          overlayColor: c.fg,
          padding: buttonPadding,
          minimumSize: buttonMinSize,
          textStyle: buttonText,
          shape: buttonShape,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.fg,
          foregroundColor: c.bg,
          disabledBackgroundColor: c.hover,
          disabledForegroundColor: c.off,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          minimumSize: buttonMinSize,
          textStyle: buttonText,
          shape: buttonShape,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.fg,
          disabledForegroundColor: c.off,
          side: c.hairline,
          padding: buttonPadding,
          minimumSize: buttonMinSize,
          textStyle: buttonText,
          shape: buttonShape,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.hover,
          foregroundColor: c.fg,
          disabledForegroundColor: c.off,
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          padding: buttonPadding,
          minimumSize: buttonMinSize,
          textStyle: buttonText,
          shape: buttonShape,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: c.muted,
          hoverColor: c.hover,
          highlightColor: Colors.transparent,
          disabledForegroundColor: c.off,
          iconSize: 16,
          minimumSize: const Size(32, 32),
          padding: EdgeInsets.zero,
          shape: buttonShape,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? c.accent
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(onAccent),
        side: BorderSide(color: c.muted),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? c.accent : c.muted,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? onAccent : c.muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? c.accent : c.hover,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : c.line,
        ),
      ),
      listTileTheme: ListTileThemeData(
        dense: true,
        iconColor: c.muted,
        textColor: c.fg,
        selectedColor: c.fg,
        selectedTileColor: c.hover,
        shape: RoundedRectangleBorder(borderRadius: radius6),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        minVerticalPadding: 6,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        selectedColor: c.hover,
        side: c.hairline,
        labelStyle: ts(12),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 6),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.fg,
        contentTextStyle: ts(kBaseFontSize).copyWith(color: c.bg),
        actionTextColor: c.accent,
        behavior: SnackBarBehavior.floating,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: radius8),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.line,
        circularTrackColor: Colors.transparent,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(3),
        thumbColor: WidgetStatePropertyAll(c.muted.withValues(alpha: 0.35)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: c.fg,
        unselectedLabelColor: c.muted,
        indicatorColor: c.accent,
        dividerColor: c.line,
        labelStyle: ts(kBaseFontSize, FontWeight.w500),
        unselectedLabelStyle: ts(kBaseFontSize),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
    );
  }

  static String _encode(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  static ThemeMode _decode(String value) => switch (value) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}
