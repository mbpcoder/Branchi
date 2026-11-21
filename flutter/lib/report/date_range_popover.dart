import 'package:flutter/material.dart';

import '../l10n/app_calendar.dart';
import '../l10n/app_locale.dart';
import '../theme/app_theme.dart';
import 'report_data.dart';

/// The presets listed on the popover's left, in order.
const List<PeriodPreset> popoverPresets = [
  PeriodPreset.last7Days,
  PeriodPreset.last30Days,
  PeriodPreset.last90Days,
  PeriodPreset.thisMonth,
  PeriodPreset.lastMonth,
  PeriodPreset.thisYear,
  PeriodPreset.all,
  PeriodPreset.custom,
];

String presetLabel(PeriodPreset preset) =>
    translate('report_preset_${preset.name}');

/// Opens the period popover under [anchor] (the widget's global rect).
/// Returns the chosen period (a preset, or a custom range), or `null` if
/// cancelled.
Future<ReportPeriod?> showDateRangePopover(
  BuildContext context, {
  required Rect anchor,
  required ReportPeriod current,
}) {
  return showDialog<ReportPeriod>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (context) {
      final size = MediaQuery.of(context).size;
      const width = 760.0;
      final left = (anchor.right - width).clamp(
        16.0,
        size.width - width - 16.0,
      );
      return Stack(
        children: [
          Positioned(
            top: anchor.bottom + 6,
            left: left < 16 ? 16 : left,
            child: SizedBox(
              width: width,
              child: _DateRangePopover(current: current),
            ),
          ),
        ],
      );
    },
  );
}

class _DateRangePopover extends StatefulWidget {
  const _DateRangePopover({required this.current});

  final ReportPeriod current;

  @override
  State<_DateRangePopover> createState() => _DateRangePopoverState();
}

class _DateRangePopoverState extends State<_DateRangePopover> {
  late final AppCalendar _calendar = AppCalendarSettings.current;
  late DateTime? _from;
  late DateTime? _to;

  /// First of the two months shown.
  late CalendarDate _month;
  final _fromField = TextEditingController();
  final _toField = TextEditingController();

  @override
  void initState() {
    super.initState();
    final period = widget.current;
    _from = period.from ?? DateTime(period.to.year, period.to.month - 1);
    _to = period.to;
    final shown = _calendar.fromDateTime(_from!);
    final end = _calendar.fromDateTime(_to!);
    _month = shown.year == end.year && shown.month == end.month
        ? _shiftMonth(end, -1)
        : CalendarDate(shown.year, shown.month, 1);
    _syncFields();
  }

  @override
  void dispose() {
    _fromField.dispose();
    _toField.dispose();
    super.dispose();
  }

  CalendarDate _shiftMonth(CalendarDate c, int by) {
    final d = _calendar.toDateTime(c.year, c.month + by, 1);
    final r = _calendar.fromDateTime(d);
    return CalendarDate(r.year, r.month, 1);
  }

  void _syncFields() {
    _fromField.text = _from == null ? '' : _calendar.formatIso(_from!);
    _toField.text = _to == null ? '' : _calendar.formatIso(_to!);
  }

  void _pickDay(DateTime day) {
    setState(() {
      if (_from == null || _to != null) {
        _from = day;
        _to = null;
      } else if (day.isBefore(_from!)) {
        _to = _from;
        _from = day;
      } else {
        _to = day;
      }
      _syncFields();
    });
  }

  void _typed() {
    final from = _calendar.parseIso(_fromField.text);
    final to = _calendar.parseIso(_toField.text);
    setState(() {
      if (from != null) _from = from;
      if (to != null) _to = to;
      if (from != null) {
        final c = _calendar.fromDateTime(from);
        _month = CalendarDate(c.year, c.month, 1);
      }
    });
  }

  bool get _canApply => _from != null && _to != null;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final days = _canApply ? ReportPeriod.custom(_from!, _to!).days : null;
    return Material(
      color: b.bg,
      elevation: 8,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: b.line),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 160,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final preset in popoverPresets)
                    _PresetItem(
                      label: presetLabel(preset),
                      selected: widget.current.preset == preset,
                      onTap: preset == PeriodPreset.custom
                          ? null
                          : () => Navigator.of(
                              context,
                            ).pop(ReportPeriod.fromPreset(preset, _calendar)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsetsDirectional.only(start: 12),
                decoration: BoxDecoration(
                  border: BorderDirectional(start: b.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconButton(
                          tooltip: translate('report_previous_month'),
                          icon: Icon(
                            isRtl ? Icons.chevron_right : Icons.chevron_left,
                            size: 18,
                          ),
                          onPressed: () =>
                              setState(() => _month = _shiftMonth(_month, -1)),
                        ),
                        Expanded(child: _month0()),
                        const SizedBox(width: 16),
                        Expanded(child: _month1()),
                        IconButton(
                          tooltip: translate('report_next_month'),
                          icon: Icon(
                            isRtl ? Icons.chevron_left : Icons.chevron_right,
                            size: 18,
                          ),
                          onPressed: () =>
                              setState(() => _month = _shiftMonth(_month, 1)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _DateField(
                            label: translate('report_from'),
                            controller: _fromField,
                            hint: _calendar.isJalali
                                ? '1405-01-01'
                                : '2026-01-01',
                            onChanged: (_) => _typed(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DateField(
                            label: translate('report_to'),
                            controller: _toField,
                            hint: _calendar.isJalali
                                ? '1405-01-31'
                                : '2026-01-31',
                            onChanged: (_) => _typed(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (days != null)
                          Text(
                            translate(
                              'report_days_count',
                            ).replaceAll('{n}', _calendar.digits(days)),
                            style: TextStyle(fontSize: 12, color: b.muted),
                          ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(translate('cancel')),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _canApply
                              ? () => Navigator.of(
                                  context,
                                ).pop(ReportPeriod.custom(_from!, _to!))
                              : null,
                          child: Text(translate('report_apply')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _month0() => _MonthGrid(
    calendar: _calendar,
    year: _month.year,
    month: _month.month,
    from: _from,
    to: _to,
    onPick: _pickDay,
  );

  Widget _month1() {
    final next = _shiftMonth(_month, 1);
    return _MonthGrid(
      calendar: _calendar,
      year: next.year,
      month: next.month,
      from: _from,
      to: _to,
      onPick: _pickDay,
    );
  }
}

class _PresetItem extends StatelessWidget {
  const _PresetItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? b.hover : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: b.fg,
            fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: b.muted)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          onChanged: onChanged,
          style: b.mono(fontSize: 12),
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 10,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
          ),
        ),
      ],
    );
  }
}

/// One month of day cells, weeks starting on the calendar's first weekday.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.calendar,
    required this.year,
    required this.month,
    required this.from,
    required this.to,
    required this.onPick,
  });

  final AppCalendar calendar;
  final int year;
  final int month;
  final DateTime? from;
  final DateTime? to;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final first = calendar.toDateTime(year, month, 1);
    final lead = (first.weekday - calendar.firstWeekday + 7) % 7;
    final days = calendar.daysInMonth(year, month);
    final names = calendar.weekdayShortNames;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final cells = <Widget>[
      for (var i = 0; i < lead; i++) const SizedBox(),
      for (var d = 1; d <= days; d++)
        Builder(
          builder: (context) {
            final date = calendar.toDateTime(year, month, d);
            final isEdge = date == from || date == to;
            final inRange =
                from != null &&
                to != null &&
                date.isAfter(from!) &&
                date.isBefore(to!);
            return InkWell(
              onTap: () => onPick(date),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 1),
                decoration: BoxDecoration(
                  color: isEdge
                      ? b.fg
                      : inRange
                      ? b.accent.withValues(alpha: 0.12)
                      : null,
                  borderRadius: BorderRadius.circular(isEdge ? 6 : 0),
                  border: date == today && !isEdge
                      ? Border.all(color: b.line)
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  calendar.digits(d),
                  style: TextStyle(
                    fontSize: 12,
                    color: isEdge ? b.bg : b.fg,
                    fontWeight: isEdge ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            );
          },
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 10),
          child: Text(
            calendar.formatMonthYear(year, month),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: b.fg,
            ),
          ),
        ),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Text(
                  names[(calendar.firstWeekday - 1 + i) % 7],
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: b.muted),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          childAspectRatio: 1.15,
          physics: const NeverScrollableScrollPhysics(),
          children: cells,
        ),
      ],
    );
  }
}
