// lib/config/app_config.dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

enum BackendMode {
  activeDirectory,
  genericRest, // e.g. spring, node, laravel
}

class AppConfig {
  // 👇 change this to switch backend
  static const backendMode = BackendMode.activeDirectory;

  /// Single source of truth for the API base URL. Every service should
  /// read this instead of hardcoding a host — otherwise changing
  /// API_BASE_URL in .env silently only affects some requests while
  /// others keep hitting a stale hardcoded URL.
  ///
  /// Falls back to the deployed API if .env doesn't define it (e.g. it
  /// failed to load, or the key is missing).
  static const String _fallbackBaseUrl = "https://immigration-api-chi.vercel.app/api";

  static String get apiBaseUrl {
    final fromEnv = dotenv.env['API_BASE_URL']?.trim();
    if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
    return _fallbackBaseUrl;
  }
}
