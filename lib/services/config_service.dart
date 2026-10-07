import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-level system configuration (SMTP, SMS gateway, attendance
/// windows, notification preferences).
///
/// Stored in SharedPreferences on this device. There are currently no
/// backend config endpoints, so these values drive client behaviour
/// (cutoff prompts, notification capture, SMTP test mail) and are clearly
/// labelled as device configuration in the UI.
class ConfigService {
  // -- SMTP --
  static const _smtpHost = 'cfg_smtp_host';
  static const _smtpPort = 'cfg_smtp_port';
  static const _smtpUser = 'cfg_smtp_user';
  static const _smtpPass = 'cfg_smtp_pass';
  static const _smtpTls = 'cfg_smtp_tls';
  static const _smtpFrom = 'cfg_smtp_from';

  // -- SMS gateway --
  static const _smsProvider = 'cfg_sms_provider';
  static const _smsKey = 'cfg_sms_key';
  static const _smsSender = 'cfg_sms_sender';
  static const _smsEnabled = 'cfg_sms_enabled';

  // -- attendance windows (defaults match the historical hardcoded values)
  static const _lateH = 'cfg_late_h';
  static const _lateM = 'cfg_late_m';
  static const _earlyH = 'cfg_early_h';
  static const _earlyM = 'cfg_early_m';

  // -- notification capture flags (also read by NotificationService)
  static const activityKey = 'activity_logging_enabled';
  static const loginAlertsKey = 'login_alerts_enabled';

  // -- two-factor authentication (email OTP) global kill-switch.
  // Defaults to OFF so the feature ships dormant until the server mailer
  // (MAIL_USER/MAIL_PASS) is configured — an admin flips it on here in
  // System Config, officers then opt in per-account in Profile Settings.
  static const _twoFactorAllowed = 'cfg_two_factor_allowed';

  static Future<bool> twoFactorAllowed() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_twoFactorAllowed) ?? false;
  }

  static Future<void> setTwoFactorAllowed(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_twoFactorAllowed, v);
  }

  // ---------------------------------------------------------------- SMTP

  static Future<SmtpConfig> loadSmtp() async {
    final p = await SharedPreferences.getInstance();
    return SmtpConfig(
      host: p.getString(_smtpHost) ?? '',
      port: p.getInt(_smtpPort) ?? 587,
      username: p.getString(_smtpUser) ?? '',
      password: p.getString(_smtpPass) ?? '',
      tls: p.getBool(_smtpTls) ?? true,
      from: p.getString(_smtpFrom) ?? '',
    );
  }

  static Future<void> saveSmtp(SmtpConfig c) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_smtpHost, c.host);
    await p.setInt(_smtpPort, c.port);
    await p.setString(_smtpUser, c.username);
    await p.setString(_smtpPass, c.password);
    await p.setBool(_smtpTls, c.tls);
    await p.setString(_smtpFrom, c.from);
  }

  // ---------------------------------------------------------------- SMS

  static Future<SmsConfig> loadSms() async {
    final p = await SharedPreferences.getInstance();
    return SmsConfig(
      provider: p.getString(_smsProvider) ?? '',
      apiKey: p.getString(_smsKey) ?? '',
      senderId: p.getString(_smsSender) ?? '',
      enabled: p.getBool(_smsEnabled) ?? false,
    );
  }

  static Future<void> saveSms(SmsConfig c) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_smsProvider, c.provider);
    await p.setString(_smsKey, c.apiKey);
    await p.setString(_smsSender, c.senderId);
    await p.setBool(_smsEnabled, c.enabled);
  }

  // ---------------------------------------------------------------- windows

  static Future<TimeOfDay> lateCutoff() async {
    final p = await SharedPreferences.getInstance();
    return TimeOfDay(
        hour: p.getInt(_lateH) ?? 8, minute: p.getInt(_lateM) ?? 30);
  }

  static Future<void> setLateCutoff(TimeOfDay t) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_lateH, t.hour);
    await p.setInt(_lateM, t.minute);
  }

  static Future<TimeOfDay> earlyCutoff() async {
    final p = await SharedPreferences.getInstance();
    return TimeOfDay(
        hour: p.getInt(_earlyH) ?? 17, minute: p.getInt(_earlyM) ?? 0);
  }

  static Future<void> setEarlyCutoff(TimeOfDay t) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_earlyH, t.hour);
    await p.setInt(_earlyM, t.minute);
  }

  // ---------------------------------------------------------------- flags

  static Future<bool> activityLogging() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(activityKey) ?? true;
  }

  static Future<void> setActivityLogging(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(activityKey, v);
  }

  static Future<bool> loginAlerts() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(loginAlertsKey) ?? true;
  }

  static Future<void> setLoginAlerts(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(loginAlertsKey, v);
  }

  // ---------------------------------------------------------------- session

  static const _sessionHours = 'cfg_session_hours';
  static const _inactivityMinutes = 'cfg_inactivity_minutes';

  /// How long a sign-in session lasts before automatic logout.
  /// Enforced when the token is minted at sign-in (default 24h).
  static Future<int> sessionHours() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_sessionHours) ?? 24;
  }

  static Future<void> setSessionHours(int v) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_sessionHours, v.clamp(1, 720));
  }

  /// Minutes of inactivity before automatic logout (default 5).
  static Future<int> inactivityMinutes() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_inactivityMinutes) ?? 5;
  }

  static Future<void> setInactivityMinutes(int v) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_inactivityMinutes, v.clamp(1, 480));
  }
}

class SmtpConfig {
  String host;
  int port;
  String username;
  String password;
  bool tls;
  String from;
  SmtpConfig({
    this.host = '',
    this.port = 587,
    this.username = '',
    this.password = '',
    this.tls = true,
    this.from = '',
  });
}

class SmsConfig {
  String provider;
  String apiKey;
  String senderId;
  bool enabled;
  SmsConfig({
    this.provider = '',
    this.apiKey = '',
    this.senderId = '',
    this.enabled = false,
  });
}
