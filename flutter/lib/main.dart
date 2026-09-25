import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'l10n/app_locale.dart';
import 'logs/file_logger.dart';
import 'settings/shell_preferences.dart';
import 'theme/app_theme.dart';

export 'app.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await FileLogger.init();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      FileLogger.log(
        'FlutterError: ${details.exceptionAsString()}',
        stackTrace: details.stack,
      );
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      FileLogger.log('Uncaught error: $error', stackTrace: stack);
      return true;
    };

    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      await windowManager.ensureInitialized();
    }
    await AppLocale.load();
    await AppTheme.load();
    await ShellPreferences.load();
    runApp(const BranchiApp());
  }, (error, stack) {
    FileLogger.log('Uncaught zone error: $error', stackTrace: stack);
  });
}
