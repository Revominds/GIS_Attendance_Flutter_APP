// In-app self-update for sideloaded builds (no Play Store).
//
// How it works:
//   1. The app fetches a small JSON file from [AppConfig.updateUrl], e.g.
//        {"version":"1.0.2","apk_url":"https://.../app-release.apk",
//         "mandatory":false,"notes":"Face scan fix"}
//   2. If the remote version is newer than the installed one, the user is
//      offered Download & Install. The APK is downloaded to the temp dir
//      and opened with the system installer (open_filex) — Android installs
//      it OVER the current app, keeping all data. No uninstall needed.
//
// Server setup: upload each release APK somewhere with a direct-download
// URL (e.g. Supabase Storage public bucket) and update version.json.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gis_attendance/config/app_config.dart';

class UpdateInfo {
  final String version;
  final String apkUrl;
  final bool mandatory;
  final String notes;

  const UpdateInfo({
    required this.version,
    required this.apkUrl,
    this.mandatory = false,
    this.notes = '',
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) => UpdateInfo(
        version: (json['version'] ?? '').toString(),
        apkUrl: (json['apk_url'] ?? json['apkUrl'] ?? '').toString(),
        mandatory: json['mandatory'] == true,
        notes: (json['notes'] ?? '').toString(),
      );
}

class UpdateCheckResult {
  final UpdateInfo? update; // non-null when a newer build exists
  final String currentVersion;
  final String message; // human-readable status when no update

  const UpdateCheckResult({
    required this.update,
    required this.currentVersion,
    required this.message,
  });
}

class UpdateService {
  static const _apkFileName = 'GIS_Attendance-update.apk';

  /// Returns update info when a newer version exists, else a status message.
  /// Never throws — all failures are returned as [UpdateCheckResult.message].
  static Future<UpdateCheckResult> check() async {
    final pkg = await PackageInfo.fromPlatform();
    final current = pkg.version;

    final url = AppConfig.updateUrl;
    if (url.isEmpty) {
      return UpdateCheckResult(
        update: null,
        currentVersion: current,
        message: 'Update server is not configured on this build.',
      );
    }

    try {
      // Cache-buster so phones never get a stale cached version.json.
      final uri = Uri.parse(url).replace(queryParameters: {
        ...Uri.parse(url).queryParameters,
        't': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      final resp = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) {
        return UpdateCheckResult(
          update: null,
          currentVersion: current,
          message: 'Update check failed (server ${resp.statusCode}).',
        );
      }
      final info = UpdateInfo.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>);
      if (info.version.isEmpty || info.apkUrl.isEmpty) {
        return UpdateCheckResult(
          update: null,
          currentVersion: current,
          message: 'Update server returned an invalid response.',
        );
      }
      if (_isNewer(current, info.version)) {
        return UpdateCheckResult(
            update: info, currentVersion: current, message: '');
      }
      return UpdateCheckResult(
        update: null,
        currentVersion: current,
        message: 'You are on the latest version ($current).',
      );
    } on TimeoutException {
      return UpdateCheckResult(
        update: null,
        currentVersion: current,
        message: 'Update check timed out. Check your connection.',
      );
    } catch (e) {
      return UpdateCheckResult(
        update: null,
        currentVersion: current,
        message: 'Update check failed: $e',
      );
    }
  }

  /// Downloads the APK (progress 0..1) then launches the system installer.
  /// Returns the installer result message; throws on download failure.
  static Future<String> downloadAndInstall(
    String apkUrl, {
    void Function(double progress)? onProgress,
  }) async {
    final req = http.Request('GET', Uri.parse(apkUrl));
    final streamed =
        await http.Client().send(req).timeout(const Duration(seconds: 30));
    if (streamed.statusCode != 200) {
      throw HttpException(
          'Download failed (server ${streamed.statusCode}).');
    }
    final total = streamed.contentLength ?? 0;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$_apkFileName');
    final sink = file.openWrite();
    var received = 0;
    await for (final chunk in streamed.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress?.call(received / total);
    }
    await sink.close();
    final result = await OpenFilex.open(file.path);
    return result.message;
  }

  /// Compares dotted versions ("1.0.2" > "1.0.1"). Non-numeric parts are
  /// compared lexically; missing parts count as 0.
  static bool _isNewer(String current, String remote) {
    int cmp = _compareVersions(remote, current);
    return cmp > 0;
  }

  static int _compareVersions(String a, String b) {
    // Strip build metadata (+...) — version core decides update order.
    final ac = a.split('+').first.split('.');
    final bc = b.split('+').first.split('.');
    final len = ac.length > bc.length ? ac.length : bc.length;
    for (var i = 0; i < len; i++) {
      final x = i < ac.length ? ac[i] : '0';
      final y = i < bc.length ? bc[i] : '0';
      final xn = int.tryParse(x);
      final yn = int.tryParse(y);
      if (xn != null && yn != null) {
        if (xn != yn) return xn.compareTo(yn);
      } else if (x != y) {
        return x.compareTo(y);
      }
    }
    return 0;
  }
}
