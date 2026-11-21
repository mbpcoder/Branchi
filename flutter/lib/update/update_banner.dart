import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../theme/app_theme.dart';
import 'update_service.dart';

/// Thin strip under the tab bar shown while a newer version is available
/// (or downloading/installing). Dismissible for the current session.
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key});

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return AnimatedBuilder(
      animation: Listenable.merge([
        UpdateService.status,
        UpdateService.latest,
        UpdateService.progress,
      ]),
      builder: (context, _) {
        final status = UpdateService.status.value;
        final release = UpdateService.latest.value;
        final busy = status == UpdateStatus.downloading ||
            status == UpdateStatus.installing;
        if (release == null ||
            (_dismissed && !busy) ||
            !(status == UpdateStatus.available || busy)) {
          return const SizedBox.shrink();
        }
        return Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: b.accent.withValues(alpha: 0.10),
            border: Border(bottom: b.hairline),
          ),
          child: Row(
            children: [
              Icon(Icons.system_update_alt, size: 16, color: b.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  busy
                      ? _busyText(status)
                      : translate('update_available')
                          .replaceAll('{version}', release.version),
                  style: TextStyle(fontSize: 13, color: b.fg),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (busy)
                SizedBox(
                  width: 120,
                  child: LinearProgressIndicator(
                    value: status == UpdateStatus.downloading
                        ? UpdateService.progress.value
                        : null,
                  ),
                )
              else ...[
                UpdateActionButton(release: release),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: translate('dismiss'),
                  iconSize: 16,
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _dismissed = true),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _busyText(UpdateStatus status) {
    if (status == UpdateStatus.installing) return translate('update_installing');
    final p = UpdateService.progress.value;
    final pct = p == null ? '' : ' ${(p * 100).round()}%';
    return '${translate('update_downloading')}$pct';
  }
}

/// The primary action for an available update, by install channel:
/// install (installer), show the command (Scoop) or open the release page.
class UpdateActionButton extends StatelessWidget {
  const UpdateActionButton({super.key, required this.release});

  final ReleaseInfo release;

  @override
  Widget build(BuildContext context) {
    switch (UpdateService.channel) {
      case InstallChannel.installer when release.installerUrl != null:
        return FilledButton(
          onPressed: UpdateService.install,
          child: Text(translate('update_install_restart')),
        );
      case InstallChannel.scoop:
        return Tooltip(
          message: 'scoop update branchi',
          child: OutlinedButton(
            onPressed: null,
            child: Text(translate('update_via_scoop')),
          ),
        );
      default:
        return OutlinedButton(
          onPressed: () => UpdateService.openInBrowser(release.pageUrl),
          child: Text(translate('update_download')),
        );
    }
  }
}
