import 'package:flutter/material.dart';

import 'settings_page.dart';

/// Route name used for the settings page.
const String kSettingsRouteName = '/settings';

/// Section ids accepted by [openSettings] / [SettingsPage.initialSection].
const String kSettingsSectionBranchWatcher = 'branch_watcher';

/// Opens the settings page, optionally scrolled to [section] (one of the
/// `kSettingsSection*` ids). The section id is passed both as
/// [SettingsPage.initialSection] and as the route's
/// [RouteSettings.arguments].
Future<void> openSettings(BuildContext context, {String? section}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: RouteSettings(name: kSettingsRouteName, arguments: section),
      builder: (context) => SettingsPage(initialSection: section),
    ),
  );
}
