import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// App-wide logger.
///
/// - In debug builds every entry is also printed to the console.
/// - Every entry (all builds) is appended to a rotating log file at
///   `<app documents>/logs/app.log`, kept to [_maxBytes] with one `.1`
///   backup, so a user hitting a bug in the field can export the file.
///
/// Writes are queued and flushed sequentially off a single future chain,
/// so logging never blocks the caller and lines never interleave.
enum LogLevel { debug, info, warn, error }

class AppLog {
  AppLog._();

  static const String _dirName = 'logs';
  static const String _fileName = 'app.log';
  static const int _maxBytes = 1024 * 1024; // 1 MB before rotation

  static File? _file;
  static Future<void> _chain = Future.value();
  static bool _initStarted = false;

  /// Resolve the log file path. Safe to call more than once; the first
  /// call wins. Call from `main()` before `runApp` so early logs land in
  /// the file too, but logging works without it (falls back to console).
  static Future<void> init() async {
    if (_initStarted) return;
    _initStarted = true;
    try {
      final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/$_dirName');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _file = File('${dir.path}/$_fileName');
    } catch (e) {
      // No file logging available (e.g. restricted platform) — console only.
      debugPrint('AppLog: file logging unavailable: $e');
    }
  }

  static void d(String tag, Object? message) => _log(LogLevel.debug, tag, message);
  static void i(String tag, Object? message) => _log(LogLevel.info, tag, message);
  static void w(String tag, Object? message, [Object? error, StackTrace? st]) =>
      _log(LogLevel.warn, tag, message, error, st);
  static void e(String tag, Object? message, [Object? error, StackTrace? st]) =>
      _log(LogLevel.error, tag, message, error, st);

  static void _log(LogLevel level, String tag, Object? message,
      [Object? error, StackTrace? st]) {
    final ts = DateTime.now().toIso8601String();
    final lvl = level.name.toUpperCase().padRight(5);
    var line = '$ts $lvl [$tag] $message';
    if (error != null) line += '\n    error: $error';
    if (st != null && (level == LogLevel.warn || level == LogLevel.error)) {
      line += '\n${st.toString().trimRight()}';
    }

    if (kDebugMode) debugPrint(line);
    _append('$line\n');
  }

  static void _append(String text) {
    _chain = _chain.then((_) async {
      final file = _file;
      if (file == null) return;
      try {
        if (await file.exists() && await file.length() > _maxBytes) {
          final backup = File('${file.path}.1');
          if (await backup.exists()) await backup.delete();
          await file.rename(backup.path);
        }
        await file.writeAsString(text, mode: FileMode.append, flush: false);
      } catch (_) {
        // Never let logging throw into the app.
      }
    });
  }

  /// Absolute path of the current log file, or null if file logging is off.
  static String? get filePath => _file?.path;

  /// Current + rotated log contents, newest file last. For a "share logs"
  /// action or an in-app debug viewer.
  static Future<String> dump() async {
    final file = _file;
    if (file == null) return '';
    final buf = StringBuffer();
    final backup = File('${file.path}.1');
    if (await backup.exists()) buf.write(await backup.readAsString());
    if (await file.exists()) buf.write(await file.readAsString());
    return buf.toString();
  }

  /// Wait for pending writes to hit disk. Call before exporting the file.
  static Future<void> flush() => _chain;
}
