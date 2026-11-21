import 'package:branchi/l10n/app_calendar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Jalali conversion matches known dates', () {
    expect(Jalali.fromGregorian(2024, 3, 20), const CalendarDate(1403, 1, 1));
    expect(Jalali.fromGregorian(2025, 3, 21), const CalendarDate(1404, 1, 1));
    expect(Jalali.fromGregorian(2026, 3, 21), const CalendarDate(1405, 1, 1));
    expect(Jalali.fromGregorian(2026, 11, 21), const CalendarDate(1405, 8, 30));
    expect(Jalali.fromGregorian(1979, 2, 11), const CalendarDate(1357, 11, 22));
    expect(Jalali.toGregorian(1403, 12, 30), const CalendarDate(2025, 3, 20));
    expect(Jalali.isLeapYear(1403), isTrue);
    expect(Jalali.isLeapYear(1404), isFalse);
  });

  test('round trip over several years', () {
    var d = DateTime.utc(2020, 1, 1);
    while (d.year < 2030) {
      final j = Jalali.fromGregorian(d.year, d.month, d.day);
      final g = Jalali.toGregorian(j.year, j.month, j.day);
      expect(g, CalendarDate(d.year, d.month, d.day));
      expect(j.day <= Jalali.monthLength(j.year, j.month), isTrue);
      d = d.add(const Duration(days: 1));
    }
  });

  test('formatting and parsing', () {
    const fa = AppCalendar(CalendarKind.jalali, 'fa');
    final date = DateTime(2026, 9, 8);
    expect(fa.formatIso(date), '1405-06-17');
    expect(fa.formatDate(date), '۱۷ شهریور ۱۴۰۵');
    expect(fa.parseIso('۱۴۰۵-۰۶-۱۷'), date);
    expect(fa.parseIso('1405-12-31'), isNull);
    expect(fa.startOfMonth(date), DateTime(2026, 8, 23));
    expect(fa.toDateTime(1405, 13, 1), DateTime(2027, 3, 21));

    const en = AppCalendar(CalendarKind.gregorian, 'en');
    expect(en.formatDate(date), 'Sep 8, 2026');
    expect(en.formatDay(date), 'Sep 8');
    expect(en.parseIso('2026-02-30'), isNull);
    expect(en.startOfYear(date), DateTime(2026, 1, 1));
  });
}
