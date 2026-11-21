import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logs/file_logger.dart';

/// Version baked in at build time:
/// `flutter build windows --dart-define=BRANCHI_VERSION=1.2.3`.
const String kAppVersion =
    String.fromEnvironment('BRANCHI_VERSION', defaultValue: '0.0.0');

const String _repo = 'mbpcoder/Branchi';
const String _installerAsset = 'branchi-setup.exe';
const String _autoCheckKey = 'branchi_update_auto_check';
const String _lastCheckKey = 'branchi_update_last_check';
const Duration _checkInterval = Duration(hours: 24);

/// How this copy of Branchi was installed, which decides how it updates.
enum InstallChannel {
  /// Inno Setup installer: download and run the new installer.
  installer,

  /// Scoop: the user runs `scoop update branchi`.
  scoop,

  /// Portable zip (or a dev build): link to the release page.
  portable,

  /// Not Windows: updates aren't handled in-app yet.
  unsupported,
}

enum UpdateStatus {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  installing,
  error,
}

@immutable
class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.pageUrl,
    this.installerUrl,
    this.checksumUrl,
  });

  final String version;
  final String pageUrl;
  final String? installerUrl;
  final String? checksumUrl;
}

/// Checks GitHub Releases for a newer stable version and, for installer
/// builds on Windows, downloads the new installer, verifies its SHA-256
/// and runs it silently (it closes and relaunches the app).
class UpdateService {
  UpdateService._();

  static final ValueNotifier<UpdateStatus> status =
      ValueNotifier(UpdateStatus.idle);
  static final ValueNotifier<ReleaseInfo?> latest = ValueNotifier(null);
  static final ValueNotifier<double?> progress = ValueNotifier(null);
  static final ValueNotifier<bool> autoCheck = ValueNotifier(true);
  static String? lastError;

  static final InstallChannel _detected = _detectChannel();

  /// Forces [channel] in tests.
  @visibleForTesting
  static InstallChannel? debugChannelOverride;

  static InstallChannel get channel => debugChannelOverride ?? _detected;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    autoCheck.value = prefs.getBool(_autoCheckKey) ?? true;
  }

  static Future<void> setAutoCheck(bool value) async {
    autoCheck.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoCheckKey, value);
  }

  /// Called once at startup: checks at most once per [_checkInterval].
  static Future<void> checkOnStartup() async {
    if (channel == InstallChannel.unsupported || !autoCheck.value) return;
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_lastCheckKey);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (last != null && now - last < _checkInterval.inMilliseconds) return;
    await check(silent: true);
  }

  /// Queries the latest release. [silent] keeps errors out of the UI
  /// status (used for background checks).
  static Future<void> check({bool silent = false}) async {
    if (status.value == UpdateStatus.checking ||
        status.value == UpdateStatus.downloading ||
        status.value == UpdateStatus.installing) {
      return;
    }
    status.value = UpdateStatus.checking;
    try {
      final release = await _fetchLatest();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _lastCheckKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      if (isNewer(release.version, kAppVersion)) {
        latest.value = release;
        status.value = UpdateStatus.available;
      } else {
        latest.value = null;
        status.value = UpdateStatus.upToDate;
      }
    } catch (e, st) {
      FileLogger.log('Update check failed: $e', stackTrace: st);
      lastError = '$e';
      status.value = silent ? UpdateStatus.idle : UpdateStatus.error;
    }
  }

  /// Downloads, verifies and launches the installer, then exits the app.
  static Future<void> install() async {
    final release = latest.value;
    if (channel != InstallChannel.installer ||
        release?.installerUrl == null) {
      return;
    }
    status.value = UpdateStatus.downloading;
    progress.value = 0;
    try {
      final dir = await Directory.systemTemp.createTemp('branchi-update-');
      final file = File('${dir.path}\\$_installerAsset');
      await _download(release!.installerUrl!, file);

      if (release.checksumUrl != null) {
        final expected = (await _getString(release.checksumUrl!))
            .trim()
            .split(RegExp(r'\s+'))
            .first
            .toLowerCase();
        final actual = await _sha256(file);
        if (expected != actual) {
          throw StateError('Checksum mismatch for the downloaded installer');
        }
      }

      status.value = UpdateStatus.installing;
      await Process.start(
        file.path,
        const [
          '/VERYSILENT',
          '/SUPPRESSMSGBOXES',
          '/NORESTART',
          '/CLOSEAPPLICATIONS',
          '/RELAUNCH=1',
        ],
        mode: ProcessStartMode.detached,
      );
      exit(0);
    } catch (e, st) {
      FileLogger.log('Update install failed: $e', stackTrace: st);
      lastError = '$e';
      progress.value = null;
      status.value = UpdateStatus.error;
    }
  }

  /// True when [candidate] is a higher `major.minor.patch` than [current].
  /// A leading `v` and any `-suffix`/`+build` are ignored.
  static bool isNewer(String candidate, String current) {
    List<int> parse(String v) {
      final core = v.trim().replaceFirst(RegExp(r'^v'), '').split(
            RegExp(r'[-+]'),
          )[0];
      final parts = core.split('.').map((p) => int.tryParse(p) ?? 0).toList();
      while (parts.length < 3) {
        parts.add(0);
      }
      return parts;
    }

    final a = parse(candidate), b = parse(current);
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  static InstallChannel _detectChannel() {
    if (!Platform.isWindows) return InstallChannel.unsupported;
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    if (exeDir.toLowerCase().contains(r'\scoop\apps\')) {
      return InstallChannel.scoop;
    }
    // Inno Setup leaves its uninstaller next to the app.
    if (File('$exeDir\\unins000.exe').existsSync()) {
      return InstallChannel.installer;
    }
    return InstallChannel.portable;
  }

  static Future<ReleaseInfo> _fetchLatest() async {
    final body = await _getString(
      'https://api.github.com/repos/$_repo/releases/latest',
      accept: 'application/vnd.github+json',
    );
    final json = jsonDecode(body) as Map<String, dynamic>;
    String? assetUrl(String name) {
      for (final a in (json['assets'] as List? ?? const [])) {
        final asset = a as Map<String, dynamic>;
        if (asset['name'] == name) {
          return asset['browser_download_url'] as String?;
        }
      }
      return null;
    }

    return ReleaseInfo(
      version: (json['tag_name'] as String).replaceFirst(RegExp(r'^v'), ''),
      pageUrl: json['html_url'] as String,
      installerUrl: assetUrl(_installerAsset),
      checksumUrl: assetUrl('$_installerAsset.sha256'),
    );
  }

  static HttpClient _client() =>
      HttpClient()..userAgent = 'Branchi/$kAppVersion';

  static Future<String> _getString(String url, {String? accept}) async {
    final client = _client();
    try {
      final req = await client.getUrl(Uri.parse(url));
      if (accept != null) req.headers.set(HttpHeaders.acceptHeader, accept);
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('HTTP ${res.statusCode}', uri: Uri.parse(url));
      }
      return await res.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  }

  static Future<void> _download(String url, File target) async {
    final client = _client();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('HTTP ${res.statusCode}', uri: Uri.parse(url));
      }
      final total = res.contentLength;
      var received = 0;
      final sink = target.openWrite();
      await for (final chunk in res) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) progress.value = received / total;
      }
      await sink.close();
    } finally {
      client.close();
    }
  }

  /// SHA-256 via the built-in `certutil`, avoiding a crypto dependency.
  static Future<String> _sha256(File file) async {
    final result =
        await Process.run('certutil', ['-hashfile', file.path, 'SHA256']);
    if (result.exitCode != 0) {
      throw StateError('certutil failed: ${result.stderr}');
    }
    final hash = (result.stdout as String)
        .split(RegExp(r'\r?\n'))
        .map((l) => l.replaceAll(' ', '').trim().toLowerCase())
        .firstWhere(
          (l) => RegExp(r'^[0-9a-f]{64}$').hasMatch(l),
          orElse: () => throw StateError('Could not read certutil output'),
        );
    return hash;
  }

  /// Opens [url] in the default browser.
  static Future<void> openInBrowser(String url) async {
    if (Platform.isWindows) {
      await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [url]);
    } else {
      await Process.run('xdg-open', [url]);
    }
  }
}
