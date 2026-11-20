import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../logs/action_log.dart';
import '../repo/branch_watcher.dart';
import '../repo/repo_controller.dart';
import '../theme/app_theme.dart';
import 'settings_widgets.dart';
import 'watcher_preferences.dart';

/// The "Branch watcher" settings section: the auto-pull switch with a live
/// countdown, the interval picker and the branches to pull (all for the
/// open repository, [controller]), plus the global watcher toggles.
class BranchWatcherSection extends StatefulWidget {
  const BranchWatcherSection({super.key, required this.controller});

  /// The open repository, or `null` when the active tab is a start page.
  final RepoController? controller;

  @override
  State<BranchWatcherSection> createState() => _BranchWatcherSectionState();
}

class _BranchWatcherSectionState extends State<BranchWatcherSection> {
  /// The interval to restore when auto-pull is switched back on.
  int _lastInterval = 2;
  Set<String>? _branches;
  bool _branchesLoaded = false;

  @override
  void initState() {
    super.initState();
    WatcherPreferences.ensureLoaded();
    _loadBranches();
  }

  @override
  void didUpdateWidget(BranchWatcherSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller?.repoPath != widget.controller?.repoPath) {
      _branchesLoaded = false;
      _branches = null;
      _loadBranches();
    }
  }

  Future<void> _loadBranches() async {
    final controller = widget.controller;
    if (controller == null) return;
    final saved = await WatcherPreferences.loadBranches(controller.repoPath);
    if (!mounted) return;
    setState(() {
      _branches = saved;
      _branchesLoaded = true;
    });
  }

  void _toggleBranch(RepoController controller, String name, bool on) {
    final current = {
      ...(_branches ??
          {if (controller.currentBranch != null) controller.currentBranch!}),
    };
    if (on) {
      current.add(name);
    } else {
      current.remove(name);
    }
    setState(() => _branches = current);
    WatcherPreferences.saveBranches(controller.repoPath, current);
  }

  void _setEnabled(BranchWatcher watcher, bool on) {
    if (on) {
      watcher.setIntervalMinutes(_lastInterval);
    } else {
      final interval = watcher.intervalMinutes;
      if (interval != null) _lastInterval = interval;
      watcher.setIntervalMinutes(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final b = context.branchi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionTitle(
          title: translate('branch_watcher'),
          subtitle: translate('branch_watcher_description'),
        ),
        const SizedBox(height: 36),
        if (controller == null) ...[
          Text(
            translate('branch_watcher_no_repo'),
            style: TextStyle(color: b.muted),
          ),
          const SizedBox(height: 36),
        ] else
          ListenableBuilder(
            listenable: Listenable.merge([controller, controller.watcher]),
            builder: (context, _) => _repoSettings(controller),
          ),
        ListenableBuilder(
          listenable: Listenable.merge([
            WatcherPreferences.onlyWhenClean,
            WatcherPreferences.notifyOnNewCommits,
          ]),
          builder: (context, _) => HairlineList(
            children: [
              SettingsToggleRow(
                title: translate('watcher_only_when_clean'),
                hint: translate('watcher_only_when_clean_hint'),
                value: WatcherPreferences.onlyWhenClean.value,
                onChanged: WatcherPreferences.setOnlyWhenClean,
              ),
              SettingsToggleRow(
                title: translate('watcher_notify_new_commits'),
                hint: translate('watcher_notify_new_commits_hint'),
                value: WatcherPreferences.notifyOnNewCommits.value,
                onChanged: WatcherPreferences.setNotifyOnNewCommits,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _repoSettings(RepoController controller) {
    final watcher = controller.watcher;
    final interval = watcher.intervalMinutes;
    if (interval != null) _lastInterval = interval;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HairlineList(
          children: [
            SettingsToggleRow(
              title: translate('auto_pull'),
              emphasized: true,
              value: watcher.isEnabled,
              onChanged: watcher.isLoaded
                  ? (on) => _setEnabled(watcher, on)
                  : null,
              hintWidget: _AutoPullStatus(controller: controller),
            ),
          ],
        ),
        const SizedBox(height: 36),
        SettingsGroup(
          label: translate('watcher_interval'),
          child: SegmentedPicker<int>(
            values: kAutoPullIntervalsMinutes,
            selected: interval,
            labelOf: (m) =>
                translate('watcher_interval_short').replaceAll('{n}', '$m'),
            onSelected: watcher.setIntervalMinutes,
          ),
        ),
        const SizedBox(height: 36),
        SettingsGroup(
          label: translate('watcher_branches_to_pull'),
          child: _branchList(controller),
        ),
        const SizedBox(height: 36),
      ],
    );
  }

  Widget _branchList(RepoController controller) {
    final b = context.branchi;
    final locals = controller.branches.where((e) => !e.isRemote).toList();
    if (locals.isEmpty || !_branchesLoaded) {
      return Text(
        translate('watcher_no_local_branches'),
        style: TextStyle(color: b.muted),
      );
    }
    final current = controller.currentBranch;
    final selected = _branches ?? {if (current != null) current};
    return BorderedList(
      children: [
        for (final branch in locals)
          InkWell(
            onTap: () => _toggleBranch(
              controller,
              branch.name,
              !selected.contains(branch.name),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: Checkbox(
                      value: selected.contains(branch.name),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      onChanged: (on) =>
                          _toggleBranch(controller, branch.name, on ?? false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      branch.name,
                      style: b.mono(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (branch.name == current)
                    Text(
                      translate('watcher_branch_current'),
                      style: TextStyle(fontSize: 12, color: b.muted),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// "Next pull in m:ss · last pulled HH:mm" (or "Auto-pull is off").
class _AutoPullStatus extends StatelessWidget {
  const _AutoPullStatus({required this.controller});

  final RepoController controller;

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    final watcher = controller.watcher;
    return ListenableBuilder(
      listenable: Listenable.merge([watcher.countdown, ActionLog.instance]),
      builder: (context, _) {
        final last = WatcherPreferences.lastPulledAt(
          controller.repoPath,
          branch: controller.currentBranch,
        );
        final lastText = last == null
            ? null
            : translate('watcher_last_pulled').replaceAll('{time}', _hhmm(last));
        final interval = watcher.intervalMinutes;
        if (interval == null) {
          return Text(
            [translate('auto_pull_disabled'), if (lastText != null) lastText]
                .join(' · '),
          );
        }
        if (watcher.isPulling || controller.isPulling) {
          return Text(translate('watcher_pulling'));
        }
        final time = formatCountdown(
          watcher.countdown.value ?? Duration(minutes: interval),
        );
        final template = translate('watcher_next_pull');
        final parts = template.split('{time}');
        return Text.rich(
          TextSpan(
            children: [
              TextSpan(text: parts.first),
              TextSpan(text: time, style: b.mono(fontSize: 12, color: b.muted)),
              if (parts.length > 1) TextSpan(text: parts.sublist(1).join()),
              if (lastText != null) TextSpan(text: ' · $lastText'),
            ],
          ),
        );
      },
    );
  }
}
