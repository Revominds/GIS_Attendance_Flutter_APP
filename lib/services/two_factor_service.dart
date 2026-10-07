// Two-factor authentication (email OTP) service.
//
// Backend has no dedicated 2FA endpoints (see doc/API.md), so this is a
// client-side implementation built on the existing
// POST /api/notification/send-email route:
//   1. Generate a random 6-digit OTP.
//   2. Email it via AttendanceService.SendEmail.
//   3. Hold the OTP + expiry locally (SharedPreferences) and verify
//      the user-typed code against it.
//
// The per-officer toggle defaults to OFF — `isEnabled()` returns false
// unless the officer explicitly opted in on the Settings screen.
// When a real server-side 2FA lands, keep this class's public API and
// swap the internals to call it.

import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gis_attendance/services/attendance_service.dart';
import 'package:gis_attendance/services/config_service.dart';
import 'package:gis_attendance/utils/app_log.dart';

class TwoFactorResult {
  final bool ok;
  final String message;
  const TwoFactorResult(this.ok, this.message);
}

class TwoFactorService {
  static const String _enabledPrefix = 'two_factor_enabled_';
  static const String _otpPrefix = 'two_factor_otp_';
  static const String _expirySuffix = '_exp';
  static const String _attemptsSuffix = '_attempts';

  /// OTP validity window and resend / attempt limits.
  static const Duration otpValidity = Duration(minutes: 5);
  static const int maxAttempts = 5;

  final AttendanceService _attendanceService = AttendanceService();

  String _enabledKey(String officerKey) => '$_enabledPrefix$officerKey';
  String _otpKey(String officerKey) => '$_otpPrefix$officerKey';
  String _expiryKey(String officerKey) => '$_otpPrefix$officerKey$_expirySuffix';
  String _attemptsKey(String officerKey) =>
      '$_otpPrefix$officerKey$_attemptsSuffix';

  /// Normalise the per-officer storage key (usernames are officer IDs like
  /// "P/012/2025" — fine as a prefs key, just trimmed/lowercased).
  String keyFor(String? officerIdOrUsername) =>
      (officerIdOrUsername ?? 'unknown').trim().toLowerCase();

  /// Default OFF: returns false when nothing was ever stored.
  Future<bool> isEnabled(String officerIdOrUsername) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_enabledKey(keyFor(officerIdOrUsername))) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Global kill-switch from System Config (also defaults to OFF).
  /// Flip it on once the server mailer is configured.
  Future<bool> isAllowedByConfig() => ConfigService.twoFactorAllowed();

  /// Effective gate used at sign-in: global switch AND per-officer opt-in.
  Future<bool> isRequiredFor(String officerIdOrUsername) async {
    if (!await isAllowedByConfig()) return false;
    return isEnabled(officerIdOrUsername);
  }

  Future<void> setEnabled(String officerIdOrUsername, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey(keyFor(officerIdOrUsername)), enabled);
    if (!enabled) {
      await clearOtp(officerIdOrUsername);
    }
  }

  /// Generates an OTP, emails it, and stores it with an expiry.
  /// Returns a user-safe message either way.
  Future<TwoFactorResult> sendOtp({
    required String officerIdOrUsername,
    required String email,
  }) async {
    final key = keyFor(officerIdOrUsername);
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty || !RegExp(r'\S+@\S+\.\S+').hasMatch(trimmedEmail)) {
      return const TwoFactorResult(
          false, 'No valid email on your profile — update it first.');
    }

    final otp = (100000 + Random.secure().nextInt(900000)).toString();
    final expiry = DateTime.now().add(otpValidity);

    final sent = await _attendanceService.SendEmail(
      trimmedEmail,
      'Your GIS verification code',
      'Your Ghana Immigration Service verification code is: $otp\n\n'
          'It expires in ${otpValidity.inMinutes} minutes. '
          'If you did not request this, please ignore this email.',
    );

    if (!sent) {
      AppLog.w('TwoFactorService', 'send-email failed for $trimmedEmail');
      return const TwoFactorResult(
        false,
        'Could not send the code. Check your connection and that the '
        'server email service is configured, then try again.',
      );
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_otpKey(key), otp);
      await prefs.setString(_expiryKey(key), expiry.toIso8601String());
      await prefs.setInt(_attemptsKey(key), 0);
    } catch (e) {
      AppLog.e('TwoFactorService', 'failed to persist OTP: $e');
      return const TwoFactorResult(
          false, 'Could not prepare verification. Please try again.');
    }

    AppLog.i('TwoFactorService', 'OTP sent to $trimmedEmail (exp $expiry)');
    return TwoFactorResult(
        true, 'A 6-digit code was sent to ${_maskEmail(trimmedEmail)}.');
  }

  /// Verifies a user-typed code. Enforces expiry + max attempts.
  Future<TwoFactorResult> verifyOtp({
    required String officerIdOrUsername,
    required String code,
  }) async {
    final key = keyFor(officerIdOrUsername);
    final input = code.trim();
    if (input.length != 6 || int.tryParse(input) == null) {
      return const TwoFactorResult(false, 'Enter the 6-digit code.');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_otpKey(key));
      final expRaw = prefs.getString(_expiryKey(key));
      var attempts = prefs.getInt(_attemptsKey(key)) ?? 0;

      if (stored == null || expRaw == null) {
        return const TwoFactorResult(
            false, 'No active code. Tap Resend to get a new one.');
      }

      final expiry = DateTime.tryParse(expRaw);
      if (expiry == null || DateTime.now().isAfter(expiry)) {
        await clearOtp(officerIdOrUsername);
        return const TwoFactorResult(
            false, 'Code expired. Tap Resend to get a new one.');
      }

      attempts += 1;
      await prefs.setInt(_attemptsKey(key), attempts);
      if (attempts > maxAttempts) {
        await clearOtp(officerIdOrUsername);
        return const TwoFactorResult(
            false, 'Too many attempts. Tap Resend to get a new code.');
      }

      if (stored != input) {
        final left = maxAttempts - attempts;
        return TwoFactorResult(false,
            'Incorrect code.${left >= 0 ? ' $left attempt${left == 1 ? '' : 's'} left.' : ''}');
      }

      await clearOtp(officerIdOrUsername);
      return const TwoFactorResult(true, 'Verified.');
    } catch (e) {
      AppLog.e('TwoFactorService', 'verifyOtp error: $e');
      return const TwoFactorResult(
          false, 'Verification failed. Please try again.');
    }
  }

  Future<void> clearOtp(String officerIdOrUsername) async {
    try {
      final key = keyFor(officerIdOrUsername);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_otpKey(key));
      await prefs.remove(_expiryKey(key));
      await prefs.remove(_attemptsKey(key));
    } catch (_) {
      // best-effort only
    }
  }

  /// Remaining validity of the currently pending OTP, or null if none.
  Future<Duration?> otpTimeLeft(String officerIdOrUsername) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final expRaw =
          prefs.getString(_expiryKey(keyFor(officerIdOrUsername)));
      if (expRaw == null) return null;
      final expiry = DateTime.tryParse(expRaw);
      if (expiry == null) return null;
      final left = expiry.difference(DateTime.now());
      return left.isNegative ? null : left;
    } catch (_) {
      return null;
    }
  }

  String maskEmail(String email) => _maskEmail(email);

  String _maskEmail(String email) {
    try {
      final parts = email.split('@');
      if (parts.length != 2) return email;
      final name = parts[0];
      final shown = name.length <= 2 ? '${name[0]}***' : '${name.substring(0, 2)}***';
      return '$shown@${parts[1]}';
    } catch (_) {
      return email;
    }
  }

  /// Debug helper (never log the real OTP in release).
  String debugSnapshot(Map<String, dynamic> m) => jsonEncode(m);
}
