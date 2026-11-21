import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_locale.dart';

const String _prefsKey = 'branchi_calendar';

/// Which calendar dates are shown in: [auto] follows the language (Jalali
/// for Persian, Gregorian otherwise).
enum CalendarPreference { auto, gregorian, jalali }

enum CalendarKind { gregorian, jalali }

/// A date in some calendar system: year, month (1-12) and day.
@immutable
class CalendarDate {
  const CalendarDate(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  @override
  bool operator ==(Object other) =>
      other is CalendarDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => '$year-$month-$day';
}

/// Global calendar setting, stored like the language.
class AppCalendarSettings {
  AppCalendarSettings._();

  static final ValueNotifier<CalendarPreference> preference = ValueNotifier(
    CalendarPreference.auto,
  );

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    preference.value = CalendarPreference.values.firstWhere(
      (p) => p.name == saved,
      orElse: () => CalendarPreference.auto,
    );
  }

  static Future<void> set(CalendarPreference value) async {
    preference.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, value.name);
  }

  /// The calendar in effect for the current setting and language.
  static CalendarKind get kind {
    switch (preference.value) {
      case CalendarPreference.gregorian:
        return CalendarKind.gregorian;
      case CalendarPreference.jalali:
        return CalendarKind.jalali;
      case CalendarPreference.auto:
        return AppLocale.languageCode.value == 'fa'
            ? CalendarKind.jalali
            : CalendarKind.gregorian;
    }
  }

  /// The calendar in effect, formatting for the current language.
  static AppCalendar get current =>
      AppCalendar(kind, AppLocale.languageCode.value);
}

/// Date maths and formatting for one calendar system in one language.
/// [DateTime]s in and out are local dates (time of day ignored).
class AppCalendar {
  const AppCalendar(this.kind, this.languageCode);

  final CalendarKind kind;
  final String languageCode;

  bool get isJalali => kind == CalendarKind.jalali;

  CalendarDate fromDateTime(DateTime date) => isJalali
      ? Jalali.fromGregorian(date.year, date.month, date.day)
      : CalendarDate(date.year, date.month, date.day);

  /// Normalizes an out-of-range [month] (e.g. 0 or 13) into the year.
  DateTime toDateTime(int year, int month, int day) {
    final y = year + ((month - 1) / 12).floor();
    final m = (month - 1) % 12 + 1;
    if (!isJalali) return DateTime(y, m, day);
    final g = Jalali.toGregorian(y, m, 1);
    return DateTime(g.year, g.month, g.day + day - 1);
  }

  int daysInMonth(int year, int month) => isJalali
      ? Jalali.monthLength(year, month)
      : DateTime(year, month + 1, 0).day;

  /// First day of the month [date] is in.
  DateTime startOfMonth(DateTime date) {
    final c = fromDateTime(date);
    return toDateTime(c.year, c.month, 1);
  }

  DateTime startOfYear(DateTime date) =>
      toDateTime(fromDateTime(date).year, 1, 1);

  /// Weekday a week starts on ([DateTime.monday] or [DateTime.saturday]).
  int get firstWeekday => isJalali ? DateTime.saturday : DateTime.monday;

  /// Short weekday names, Monday first (index 0 = [DateTime.monday]).
  List<String> get weekdayShortNames {
    switch (languageCode) {
      case 'fa':
        return const ['د', 'س', 'چ', 'پ', 'ج', 'ش', 'ی'];
      case 'ar':
        return const ['ن', 'ث', 'ر', 'خ', 'ج', 'س', 'ح'];
      default:
        return const ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
    }
  }

  /// Weekday names for row labels, Monday first.
  List<String> get weekdayNames {
    switch (languageCode) {
      case 'fa':
        return const [
          'دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه', 'شنبه', //
          'یکشنبه',
        ];
      case 'ar':
        return const [
          'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', //
          'الأحد',
        ];
      default:
        return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    }
  }

  String monthName(int month, {bool short = false}) {
    final names = _monthNames();
    final name = names[month - 1];
    if (short && languageCode == 'en' && !isJalali) {
      return name.substring(0, 3);
    }
    return name;
  }

  List<String> _monthNames() {
    if (isJalali) {
      return languageCode == 'fa' || languageCode == 'ar'
          ? const [
              'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور', //
              'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند',
            ]
          : const [
              'Farvardin', 'Ordibehesht', 'Khordad', 'Tir', 'Mordad', //
              'Shahrivar', 'Mehr', 'Aban', 'Azar', 'Dey', 'Bahman', 'Esfand',
            ];
    }
    switch (languageCode) {
      case 'fa':
        return const [
          'ژانویه', 'فوریه', 'مارس', 'آوریل', 'مه', 'ژوئن', 'ژوئیه', //
          'اوت', 'سپتامبر', 'اکتبر', 'نوامبر', 'دسامبر',
        ];
      case 'ar':
        return const [
          'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', //
          'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
        ];
      default:
        return const [
          'January', 'February', 'March', 'April', 'May', 'June', 'July', //
          'August', 'September', 'October', 'November', 'December',
        ];
    }
  }

  /// Persian digits in Persian, Western digits otherwise.
  String digits(Object value) {
    final text = '$value';
    if (languageCode != 'fa') return text;
    const persian = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
    return text.replaceAllMapped(
      RegExp(r'[0-9]'),
      (m) => persian[int.parse(m[0]!)],
    );
  }

  /// "Sep 8" / "17 Shahrivar" / "۱۷ شهریور".
  String formatDay(DateTime date) {
    final c = fromDateTime(date);
    if (languageCode == 'en' && !isJalali) {
      return '${monthName(c.month, short: true)} ${c.day}';
    }
    return '${digits(c.day)} ${monthName(c.month)}';
  }

  /// "Sep 8, 2026" / "۱۷ شهریور ۱۴۰۵".
  String formatDate(DateTime date) {
    final c = fromDateTime(date);
    if (languageCode == 'en' && !isJalali) {
      return '${monthName(c.month, short: true)} ${c.day}, ${c.year}';
    }
    return '${digits(c.day)} ${monthName(c.month)} ${digits(c.year)}';
  }

  /// "September 2026" / "شهریور ۱۴۰۵".
  String formatMonthYear(int year, int month) =>
      '${monthName(month)} ${digits(year)}';

  /// "Sep" / "شهریور", with the year when [withYear].
  String formatMonth(DateTime date, {bool withYear = false}) {
    final c = fromDateTime(date);
    final name = monthName(c.month, short: true);
    return withYear ? '$name ${digits(c.year)}' : name;
  }

  /// "2026-09-08" / "1405-06-17", always Western digits so it can be typed.
  String formatIso(DateTime date) {
    final c = fromDateTime(date);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${c.year}-${two(c.month)}-${two(c.day)}';
  }

  /// Parses [formatIso]'s format (Persian digits accepted too); `null` if
  /// it isn't a valid date in this calendar.
  DateTime? parseIso(String text) {
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    final normalized = text.trim().split('').map((ch) {
      final pi = persian.indexOf(ch);
      if (pi >= 0) return '$pi';
      final ai = arabic.indexOf(ch);
      if (ai >= 0) return '$ai';
      return ch;
    }).join();
    final match = RegExp(
      r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})$',
    ).firstMatch(normalized);
    if (match == null) return null;
    final y = int.parse(match[1]!);
    final m = int.parse(match[2]!);
    final d = int.parse(match[3]!);
    if (m < 1 || m > 12 || d < 1 || d > daysInMonth(y, m)) return null;
    return toDateTime(y, m, d);
  }
}

/// Jalali (Solar Hijri) <-> Gregorian conversion, after the jalaali-js
/// algorithm (valid for Jalali years -61 to 3177).
class Jalali {
  Jalali._();

  static const List<int> _breaks = [
    -61, 9, 38, 199, 426, 686, 756, 818, 1111, 1181, 1210, 1635, 2060, //
    2097, 2192, 2262, 2324, 2394, 2456, 3178,
  ];

  static int _div(int a, int b) => a ~/ b;
  static int _mod(int a, int b) => a.remainder(b);

  static CalendarDate fromGregorian(int gy, int gm, int gd) =>
      _d2j(_g2d(gy, gm, gd));

  static CalendarDate toGregorian(int jy, int jm, int jd) =>
      _d2g(_j2d(jy, jm, jd));

  static bool isLeapYear(int jy) => _jalCal(jy).leap == 0;

  static int monthLength(int jy, int jm) {
    if (jm <= 6) return 31;
    if (jm <= 11) return 30;
    return isLeapYear(jy) ? 30 : 29;
  }

  static ({int leap, int gy, int march}) _jalCal(int jy) {
    final gy = jy + 621;
    var leapJ = -14;
    var jp = _breaks[0];
    var jump = 0;
    for (var i = 1; i < _breaks.length; i++) {
      final jm = _breaks[i];
      jump = jm - jp;
      if (jy < jm) break;
      leapJ += _div(jump, 33) * 8 + _div(_mod(jump, 33), 4);
      jp = jm;
    }
    var n = jy - jp;
    leapJ += _div(n, 33) * 8 + _div(_mod(n, 33) + 3, 4);
    if (_mod(jump, 33) == 4 && jump - n == 4) leapJ += 1;
    final leapG = _div(gy, 4) - _div((_div(gy, 100) + 1) * 3, 4) - 150;
    final march = 20 + leapJ - leapG;
    if (jump - n < 6) n = n - jump + _div(jump + 4, 33) * 33;
    var leap = _mod(_mod(n + 1, 33) - 1, 4);
    if (leap == -1) leap = 4;
    return (leap: leap, gy: gy, march: march);
  }

  static int _j2d(int jy, int jm, int jd) {
    final r = _jalCal(jy);
    return _g2d(r.gy, 3, r.march) +
        (jm - 1) * 31 -
        _div(jm, 7) * (jm - 7) +
        jd -
        1;
  }

  static CalendarDate _d2j(int jdn) {
    final gy = _d2g(jdn).year;
    var jy = gy - 621;
    final r = _jalCal(jy);
    final jdn1f = _g2d(gy, 3, r.march);
    var k = jdn - jdn1f;
    if (k >= 0) {
      if (k <= 185) {
        return CalendarDate(jy, 1 + _div(k, 31), _mod(k, 31) + 1);
      }
      k -= 186;
    } else {
      jy -= 1;
      k += 179;
      if (r.leap == 1) k += 1;
    }
    return CalendarDate(jy, 7 + _div(k, 30), _mod(k, 30) + 1);
  }

  static int _g2d(int gy, int gm, int gd) {
    var d =
        _div((gy + _div(gm - 8, 6) + 100100) * 1461, 4) +
        _div(153 * _mod(gm + 9, 12) + 2, 5) +
        gd -
        34840408;
    d = d - _div(_div(gy + 100100 + _div(gm - 8, 6), 100) * 3, 4) + 752;
    return d;
  }

  static CalendarDate _d2g(int jdn) {
    var j = 4 * jdn + 139361631;
    j = j + _div(_div(4 * jdn + 183187720, 146097) * 3, 4) * 4 - 3908;
    final i = _div(_mod(j, 1461), 4) * 5 + 308;
    final gd = _div(_mod(i, 153), 5) + 1;
    final gm = _mod(_div(i, 153), 12) + 1;
    final gy = _div(j, 1461) - 100100 + _div(8 - gm, 6);
    return CalendarDate(gy, gm, gd);
  }
}
