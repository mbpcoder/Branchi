import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../settings/settings_widgets.dart';
import '../theme/app_theme.dart';
import 'update_banner.dart';
import 'update_service.dart';

/// Settings → Updates: current version, auto-check toggle, "Check now" and
/// the action for an available update.
class UpdateSettingsSection extends StatelessWidget {
  const UpdateSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return AnimatedBuilder(
      animation: Listenable.merge([
        UpdateService.status,
        UpdateService.latest,
        UpdateService.progress,
        UpdateService.autoCheck,
      ]),
      builder: (context, _) {
        final status = UpdateService.status.value;
        final release = UpdateService.latest.value;
        final supported = UpdateService.channel != InstallChannel.unsupported;
        final busy = status == UpdateStatus.checking ||
            status == UpdateStatus.downloading ||
            status == UpdateStatus.installing;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsSectionTitle(
              title: translate('updates'),
              subtitle: translate('updates_description'),
            ),
            const SizedBox(height: 40),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(translate('current_version')),
                      const SizedBox(height: 2),
                      Text(
                        'v$kAppVersion',
                        style: b.mono(fontSize: 12, color: b.muted),
                      ),
                    ],
                  ),
                ),
                OutlinedButton(
                  onPressed: supported && !busy ? UpdateService.check : null,
                  child: Text(translate('check_for_updates')),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!supported)
              Text(
                translate('updates_unsupported'),
                style: TextStyle(color: b.muted),
              )
            else
              _statusRow(b, status, release),
            const SizedBox(height: 24),
            HairlineList(
              children: [
                SettingsToggleRow(
                  title: translate('update_auto_check'),
                  hint: translate('update_auto_check_hint'),
                  value: UpdateService.autoCheck.value,
                  onChanged: supported ? UpdateService.setAutoCheck : null,
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _statusRow(
    BranchiColors b,
    UpdateStatus status,
    ReleaseInfo? release,
  ) {
    final muted = TextStyle(color: b.muted);
    switch (status) {
      case UpdateStatus.checking:
        return Text(translate('update_checking'), style: muted);
      case UpdateStatus.upToDate:
        return Text(translate('update_up_to_date'), style: muted);
      case UpdateStatus.error:
        return Text(
          '${translate('update_failed')}: ${UpdateService.lastError ?? ''}',
          style: TextStyle(color: b.del),
        );
      case UpdateStatus.downloading:
      case UpdateStatus.installing:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              status == UpdateStatus.installing
                  ? translate('update_installing')
                  : translate('update_downloading'),
              style: muted,
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: status == UpdateStatus.downloading
                  ? UpdateService.progress.value
                  : null,
            ),
          ],
        );
      case UpdateStatus.available when release != null:
        return Row(
          children: [
            Expanded(
              child: Text(
                translate('update_available')
                    .replaceAll('{version}', release.version),
              ),
            ),
            UpdateActionButton(release: release),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
