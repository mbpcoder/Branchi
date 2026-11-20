import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../repo/branch_watcher.dart';
import '../settings/settings_route.dart';
import '../theme/app_theme.dart';

/// Compact auto-pull control for the top bar: an accent dot, "Auto" and a
/// monospace countdown to the next pull (or "Off"). Clicking opens a menu
/// to pick the interval (Off / 1-4 minutes) and a "Watcher settings…"
/// entry.
///
/// Bound to a [BranchWatcher] (e.g. `repoController.watcher`). By default
/// "Watcher settings…" opens the settings page on the
/// [kSettingsSectionBranchWatcher] section; pass [onOpenSettings] to
/// override.
class AutoPullButton extends StatefulWidget {
  const AutoPullButton({
    super.key,
    required this.watcher,
    this.onOpenSettings,
    this.isBusy = false,
  });

  final BranchWatcher watcher;

  /// Replaces the default "open settings on the branch watcher section".
  final VoidCallback? onOpenSettings;

  /// Shows a spinner in place of the countdown, e.g. while a manual pull
  /// runs. Automatic pulls ([BranchWatcher.isPulling]) always show it.
  final bool isBusy;

  @override
  State<AutoPullButton> createState() => _AutoPullButtonState();
}

class _AutoPullButtonState extends State<AutoPullButton> {
  final MenuController _menuController = MenuController();
  bool _hovered = false;

  void _select(int? minutes) {
    widget.watcher.setIntervalMinutes(minutes);
  }

  void _openSettings() {
    final callback = widget.onOpenSettings;
    if (callback != null) {
      callback();
    } else {
      openSettings(context, section: kSettingsSectionBranchWatcher);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return ListenableBuilder(
      listenable: widget.watcher,
      builder: (context, _) {
        final interval = widget.watcher.intervalMinutes;
        final options = <int?>[
          null,
          ...kAutoPullIntervalsMinutes,
          if (interval != null && !kAutoPullIntervalsMinutes.contains(interval))
            interval,
        ];
        return MenuAnchor(
          controller: _menuController,
          alignmentOffset: const Offset(0, 6),
          style: MenuStyle(
            minimumSize: const WidgetStatePropertyAll(Size(220, 0)),
            padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
          ),
          menuChildren: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: Text(
                translate('auto_pull_every'),
                style: TextStyle(
                  fontSize: 11,
                  color: b.muted,
                  letterSpacing: 0.44,
                ),
              ),
            ),
            for (final option in options)
              _IntervalItem(
                label: option == null
                    ? translate('auto_pull_off')
                    : autoPullIntervalLabel(option),
                selected: option == interval,
                onPressed: () => _select(option),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Container(height: 1, width: 204, color: b.line),
            ),
            MenuItemButton(
              onPressed: _openSettings,
              style: _itemStyle(b, selected: false, color: b.muted),
              child: Text(translate('watcher_settings')),
            ),
          ],
          builder: (context, controller, child) {
            final busy = widget.isBusy || widget.watcher.isPulling;
            final tooltip = interval == null
                ? translate('auto_pull_disabled')
                : translate('auto_pull_tooltip')
                    .replaceAll('{interval}', autoPullIntervalLabel(interval));
            return Tooltip(
              message: tooltip,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() => _hovered = false),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
                  child: Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: _hovered || controller.isOpen
                          ? b.hover
                          : Colors.transparent,
                      border: Border.all(color: b.line),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: interval == null ? b.off : b.accent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          translate('auto_pull_label'),
                          style: TextStyle(fontSize: 12, color: b.fg),
                        ),
                        const SizedBox(width: 8),
                        if (busy)
                          SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: b.muted,
                            ),
                          )
                        else if (interval == null)
                          Text(
                            translate('auto_pull_off'),
                            style: TextStyle(fontSize: 12, color: b.muted),
                          )
                        else
                          ValueListenableBuilder<Duration?>(
                            valueListenable: widget.watcher.countdown,
                            builder: (context, remaining, _) {
                              final text = formatCountdown(
                                remaining ?? Duration(minutes: interval),
                              );
                              return Semantics(
                                label: translate('auto_pull_next')
                                    .replaceAll('{time}', text),
                                child: ExcludeSemantics(
                                  child: Text(
                                    text,
                                    style: b.mono(
                                      fontSize: 12,
                                      color: b.muted,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.keyboard_arrow_down,
                          size: 14,
                          color: b.muted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

ButtonStyle _itemStyle(
  BranchiColors b, {
  required bool selected,
  Color? color,
}) {
  return ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(208, 32)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 10),
    ),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) => selected || states.contains(WidgetState.hovered)
          ? b.hover
          : Colors.transparent,
    ),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    foregroundColor: WidgetStatePropertyAll(color ?? b.fg),
    textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 13)),
  );
}

class _IntervalItem extends StatelessWidget {
  const _IntervalItem({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return MenuItemButton(
      onPressed: onPressed,
      style: _itemStyle(b, selected: selected),
      trailingIcon: selected
          ? Icon(Icons.check, size: 14, color: b.accent)
          : const SizedBox(width: 14),
      child: Text(label),
    );
  }
}
