import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Building blocks for the minimal settings page: section title, labels,
/// toggle rows with hairline separators, a compact switch and a segmented
/// picker.

/// 18px/600 section title with a muted subtitle.
class SettingsSectionTitle extends StatelessWidget {
  const SettingsSectionTitle({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: b.fg,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(subtitle!, style: TextStyle(fontSize: 13, color: b.muted)),
        ],
      ],
    );
  }
}

/// A 500-weight group label ("Theme", "Accent", "Interval", ...) followed
/// by its content, 12px apart.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.label,
    required this.child,
    this.trailing,
  });

  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

/// A list of rows separated (and bounded top and bottom) by hairlines.
class HairlineList extends StatelessWidget {
  const HairlineList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(top: b.hairline)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final child in children)
            DecoratedBox(
              decoration: BoxDecoration(border: Border(bottom: b.hairline)),
              child: child,
            ),
        ],
      ),
    );
  }
}

/// Title + muted hint on the left, a [MiniSwitch] on the right; the whole
/// row toggles. Use inside a [HairlineList].
class SettingsToggleRow extends StatelessWidget {
  const SettingsToggleRow({
    super.key,
    required this.title,
    this.hint,
    this.hintWidget,
    required this.value,
    required this.onChanged,
    this.emphasized = false,
  });

  final String title;
  final String? hint;

  /// Replaces [hint], e.g. for a live countdown.
  final Widget? hintWidget;
  final bool value;
  final ValueChanged<bool>? onChanged;

  /// Uses a 500-weight title (e.g. the main "Auto-pull" switch).
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final enabled = onChanged != null;
    return MergeSemantics(
      child: InkWell(
        onTap: enabled ? () => onChanged!(!value) : null,
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: enabled ? b.fg : b.muted,
                        fontWeight: emphasized
                            ? FontWeight.w500
                            : FontWeight.w400,
                      ),
                    ),
                    if (hintWidget != null || hint != null) ...[
                      const SizedBox(height: 2),
                      DefaultTextStyle.merge(
                        style: TextStyle(fontSize: 12, color: b.muted),
                        child: hintWidget ?? Text(hint!),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              MiniSwitch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 34x20 pill switch: accent track when on, [BranchiColors.off] when off.
class MiniSwitch extends StatelessWidget {
  const MiniSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final enabled = onChanged != null;
    return Semantics(
      toggled: value,
      enabled: enabled,
      child: GestureDetector(
        onTap: enabled ? () => onChanged!(!value) : null,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 34,
            height: 20,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: (value ? b.accent : b.off).withValues(
                alpha: enabled ? 1 : 0.5,
              ),
              borderRadius: BorderRadius.circular(999),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 140),
              alignment: value
                  ? AlignmentDirectional.centerEnd
                  : AlignmentDirectional.centerStart,
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Equal-width segmented control on a [BranchiColors.hover] track; the
/// selected segment is raised onto [BranchiColors.bg].
class SegmentedPicker<T> extends StatelessWidget {
  const SegmentedPicker({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  final List<T> values;
  final T? selected;
  final String Function(T value) labelOf;
  final ValueChanged<T>? onSelected;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final enabled = onSelected != null;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: b.hover,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          for (var i = 0; i < values.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: _Segment(
                label: labelOf(values[i]),
                selected: values[i] == selected,
                onTap: enabled ? () => onSelected!(values[i]) : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
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
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? b.bg : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          hoverColor: selected
              ? Colors.transparent
              : b.bg.withValues(alpha: 0.4),
          splashColor: Colors.transparent,
          child: SizedBox(
            height: 32,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: onTap == null
                      ? b.off
                      : selected
                      ? b.fg
                      : b.muted,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A bordered, rounded box; rows inside are separated by hairlines.
class BorderedList extends StatelessWidget {
  const BorderedList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.fromBorderSide(b.hairline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++)
            DecoratedBox(
              decoration: BoxDecoration(
                border: i == 0 ? null : Border(top: b.hairline),
              ),
              child: children[i],
            ),
        ],
      ),
    );
  }
}
