// SYSTEM CONFIG — device-level configuration for admins: SMTP mail,
// SMS gateway, attendance windows, notification capture and server info.
// Stored on this device via ConfigService (there are no backend config
// endpoints). The SMTP test button sends a real test email through
// POST /notification/send-email; SMS shows backend status honestly
// because POST /notification/send-sms is a documented stub.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gis_attendance/config/app_config.dart';
import 'package:gis_attendance/services/attendance_service.dart';
import 'package:gis_attendance/services/auth_service.dart';
import 'package:gis_attendance/services/config_service.dart';
import 'package:gis_attendance/services/notification_service.dart';

class SystemConfigScreen extends StatefulWidget {
  const SystemConfigScreen({super.key});
  @override
  State<SystemConfigScreen> createState() => _SystemConfigScreenState();
}

class _SystemConfigScreenState extends State<SystemConfigScreen> {
  static const olive = Color(0xFF2E4D2A);
  static const dark = Color(0xFF142412);
  static const bg = Color(0xFFF5F6F5);
  static const muted = Color(0xFF6E7A6C);
  static const hairline = Color(0xFFE7E9E4);
  static const goldTint = Color(0xFFFBF1D8);
  static const darkAmber = Color(0xFF7A5F00);
  static const danger = Color(0xFFD63031);

  final _auth = AuthService();
  final _attendance = AttendanceService();

  bool _checkingAccess = true;
  bool _allowed = false;
  bool _loading = true;
  bool _savingSmtp = false;
  bool _savingSms = false;
  bool _testingMail = false;
  bool _obscureSmtpPass = true;
  bool _obscureSmsKey = true;

  // session
  final _sessionCtrl = TextEditingController();
  final _inactivityCtrl = TextEditingController();
  bool _savingSession = false;

  // SMTP
  final _smtpHost = TextEditingController();
  final _smtpPort = TextEditingController();
  final _smtpUser = TextEditingController();
  final _smtpPass = TextEditingController();
  final _smtpFrom = TextEditingController();
  bool _smtpTls = true;

  // SMS
  final _smsProvider = TextEditingController();
  final _smsKey = TextEditingController();
  final _smsSender = TextEditingController();
  bool _smsEnabled = false;

  // windows + flags
  TimeOfDay _late = const TimeOfDay(hour: 8, minute: 30);
  TimeOfDay _early = const TimeOfDay(hour: 17, minute: 0);
  bool _activityLogging = true;
  bool _loginAlerts = true;

  // Two-factor authentication (email OTP) — global kill-switch.
  // OFF by default; turn on once the server mailer works so officers
  // can opt in from Profile Settings.
  bool _twoFactorAllowed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    for (final c in [
      _smtpHost,
      _smtpPort,
      _smtpUser,
      _smtpPass,
      _smtpFrom,
      _smsProvider,
      _smsKey,
      _smsSender,
      _sessionCtrl,
      _inactivityCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _init() async {
    final allowed = await _auth.isAdminOrSuper();
    SmtpConfig smtp = SmtpConfig();
    SmsConfig sms = SmsConfig();
    if (allowed) {
      smtp = await ConfigService.loadSmtp();
      sms = await ConfigService.loadSms();
      _late = await ConfigService.lateCutoff();
      _early = await ConfigService.earlyCutoff();
      _activityLogging = await ConfigService.activityLogging();
      _loginAlerts = await ConfigService.loginAlerts();
      _twoFactorAllowed = await ConfigService.twoFactorAllowed();
      _sessionCtrl.text =
          (await ConfigService.sessionHours()).toString();
      _inactivityCtrl.text =
          (await ConfigService.inactivityMinutes()).toString();
    }
    if (!mounted) return;
    setState(() {
      _allowed = allowed;
      _checkingAccess = false;
      _smtpHost.text = smtp.host;
      _smtpPort.text = smtp.port.toString();
      _smtpUser.text = smtp.username;
      _smtpPass.text = smtp.password;
      _smtpFrom.text = smtp.from;
      _smtpTls = smtp.tls;
      _smsProvider.text = sms.provider;
      _smsKey.text = sms.apiKey;
      _smsSender.text = sms.senderId;
      _smsEnabled = sms.enabled;
      _loading = false;
    });
  }

  void _snack(String msg, {bool ok = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: ok ? olive : danger,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  SmtpConfig _readSmtp() => SmtpConfig(
        host: _smtpHost.text.trim(),
        port: int.tryParse(_smtpPort.text.trim()) ?? 587,
        username: _smtpUser.text.trim(),
        password: _smtpPass.text,
        tls: _smtpTls,
        from: _smtpFrom.text.trim(),
      );

  Future<void> _saveSmtp() async {
    if (_smtpHost.text.trim().isEmpty ||
        _smtpUser.text.trim().isEmpty) {
      _snack('SMTP host and username are required.');
      return;
    }
    setState(() => _savingSmtp = true);
    await ConfigService.saveSmtp(_readSmtp());
    NotificationService.logActivity(
      'SMTP settings updated',
      'Mail host ${_smtpHost.text.trim()} saved on this device.',
      category: 'System',
    );
    if (!mounted) return;
    setState(() => _savingSmtp = false);
    _snack('SMTP settings saved on this device.', ok: true);
  }

  Future<void> _testMail() async {
    final to = _smtpUser.text.trim();
    if (to.isEmpty) {
      _snack('Enter the SMTP username (your email) first.');
      return;
    }
    setState(() => _testingMail = true);
    final ok = await _attendance.SendEmail(
      to,
      'GIS Attendance — test email',
      'This is a test email from the GIS Attendance app. If you received it, outbound mail works.',
    );
    if (!mounted) return;
    setState(() => _testingMail = false);
    _snack(
      ok
          ? 'Test email sent — check the inbox.'
          : 'Test email failed. The server mailer (MAIL_USER/MAIL_PASS) may not be configured.',
      ok: ok,
    );
  }

  Future<void> _saveSms() async {
    setState(() => _savingSms = true);
    await ConfigService.saveSms(SmsConfig(
      provider: _smsProvider.text.trim(),
      apiKey: _smsKey.text.trim(),
      senderId: _smsSender.text.trim(),
      enabled: _smsEnabled,
    ));
    NotificationService.logActivity(
      'SMS settings updated',
      'SMS gateway settings saved on this device.',
      category: 'System',
    );
    if (!mounted) return;
    setState(() => _savingSms = false);
    _snack('SMS settings saved on this device.', ok: true);
  }

  void _smsStatus() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('SMS gateway status',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: Text(
          _smsEnabled && _smsProvider.text.trim().isNotEmpty
              ? 'Configured for "${_smsProvider.text.trim()}" on this device, but the backend SMS endpoint (POST /notification/send-sms) is a documented stub and ignores message bodies. Broadcasts fall back to the in-app log until the server gateway is connected.'
              : 'No SMS gateway is active. The backend SMS endpoint (POST /notification/send-sms) is a documented stub — configure a provider here so credentials are ready when the server gateway is connected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it',
                style: TextStyle(
                    color: olive, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCutoff(bool late) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: late ? _late : _early,
    );
    if (picked == null) return;
    if (late) {
      await ConfigService.setLateCutoff(picked);
      setState(() => _late = picked);
    } else {
      await ConfigService.setEarlyCutoff(picked);
      setState(() => _early = picked);
    }
    NotificationService.logActivity(
      'Attendance window updated',
      late
          ? 'Late threshold set to ${picked.format(context)}.'
          : 'Early-leaving threshold set to ${picked.format(context)}.',
      category: 'System',
    );
    _snack('Saved.', ok: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: dark,
        iconTheme: const IconThemeData(color: olive),
        elevation: 0,
        title: const Text('System Config',
            style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: dark)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: hairline),
        ),
      ),
      body: _checkingAccess || (_loading && _allowed)
          ? const Center(child: CircularProgressIndicator(color: olive))
          : !_allowed
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Only admins and super admins can change system configuration.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: dark,
                          height: 1.5),
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxWidth: 720),
                      child: Column(
                        children: [
                          _smtpCard(),
                          const SizedBox(height: 14),
                          _twoFactorCard(),
                          const SizedBox(height: 14),
                          _smsCard(),
                          const SizedBox(height: 14),
                          _attendanceCard(),
                          const SizedBox(height: 14),
                          _notificationsCard(),
                          const SizedBox(height: 14),
                          _sessionCard(),
                          const SizedBox(height: 14),
                          _serverCard(),
                          const SizedBox(height: 8),
                          const Text(
                            'Mail, SMS and server values apply to this device. Attendance windows apply app-wide on this device.',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(fontSize: 11.5, color: muted),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _card({required String title, required String subtitle,
      required IconData icon, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: hairline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: olive.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 19, color: olive),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: dark)),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12, color: muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
      {bool obscure = false,
      Widget? suffix,
      TextInputType? keyboard,
      bool readOnly = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        obscureText: obscure,
        keyboardType: keyboard,
        readOnly: readOnly,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          filled: true,
          fillColor: bg,
          suffixIcon: suffix,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _smtpCard() {
    return _card(
      title: 'SMTP mail',
      subtitle: 'Outbound email for test mail and alerts',
      icon: Icons.mark_email_read_outlined,
      children: [
        _field(_smtpHost, 'SMTP host (e.g. smtp.gmail.com)'),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: _field(_smtpPort, 'Port',
                  keyboard: TextInputType.number),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: _field(_smtpFrom, 'From address (optional)'),
            ),
          ],
        ),
        _field(_smtpUser, 'Username (email)',
            keyboard: TextInputType.emailAddress),
        _field(
          _smtpPass,
          'Password / app password',
          obscure: _obscureSmtpPass,
          suffix: IconButton(
            icon: Icon(
                _obscureSmtpPass
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 19,
                color: muted),
            onPressed: () =>
                setState(() => _obscureSmtpPass = !_obscureSmtpPass),
          ),
        ),
        Row(
          children: [
            const Expanded(
                child: Text('Use TLS',
                    style: TextStyle(fontSize: 13.5, color: dark))),
            Switch(
              value: _smtpTls,
              activeThumbColor: olive,
              onChanged: (v) => setState(() => _smtpTls = v),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _savingSmtp ? null : _saveSmtp,
                icon: const Icon(Icons.save_outlined, size: 17),
                label:
                    Text(_savingSmtp ? 'Saving…' : 'Save SMTP'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: olive,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding:
                      const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _testingMail ? null : _testMail,
                icon: const Icon(Icons.send_outlined, size: 17),
                label:
                    Text(_testingMail ? 'Sending…' : 'Send test'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: olive,
                  side: const BorderSide(color: olive),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding:
                      const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _twoFactorCard() {
    return _card(
      title: 'Two-factor authentication',
      subtitle: 'Email OTP codes at sign-in',
      icon: Icons.mark_email_read_outlined,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _twoFactorAllowed ? olive.withValues(alpha: 0.08) : goldTint,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _twoFactorAllowed
                ? 'ON — officers who enable 2FA in Profile Settings receive a 6-digit code by email at each sign-in (valid 5 minutes).'
                : 'OFF — 2FA is dormant. Confirm outbound mail works with “Send test” above, then flip this on so officers can opt in from Profile Settings.',
            style: TextStyle(
                fontSize: 12,
                color: _twoFactorAllowed ? olive : darkAmber),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Allow email OTP 2FA',
                      style:
                          TextStyle(fontSize: 13.5, color: dark)),
                  Text('Officers opt in per-account in Profile Settings',
                      style:
                          TextStyle(fontSize: 12, color: muted)),
                ],
              ),
            ),
            Switch(
              value: _twoFactorAllowed,
              activeThumbColor: olive,
              onChanged: (v) async {
                await ConfigService.setTwoFactorAllowed(v);
                setState(() => _twoFactorAllowed = v);
                NotificationService.logActivity(
                  v
                      ? 'Two-factor authentication enabled'
                      : 'Two-factor authentication disabled',
                  v
                      ? 'Email OTP 2FA was turned on for this device — officers can now opt in.'
                      : 'Email OTP 2FA was turned off for this device.',
                  category: 'System',
                );
                _snack(
                  v
                      ? '2FA enabled — officers can now opt in.'
                      : '2FA disabled.',
                  ok: v,
                );
              },
            ),
          ],
        ),
        const Text(
          'Codes are sent through POST /notification/send-email, which needs MAIL_USER/MAIL_PASS on the server. If test mail fails, keep this off until the mailer is configured.',
          style: TextStyle(fontSize: 12, color: muted),
        ),
      ],
    );
  }

  Widget _smsCard() {
    return _card(
      title: 'SMS gateway',
      subtitle: 'Credentials for the SMS provider',
      icon: Icons.sms_outlined,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: goldTint,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'Backend SMS endpoint is a stub — settings are kept ready for when the server gateway is connected.',
            style: TextStyle(fontSize: 12, color: darkAmber),
          ),
        ),
        const SizedBox(height: 10),
        _field(_smsProvider, 'Provider (e.g. Twilio, Arkesel, Hubtel)'),
        _field(
          _smsKey,
          'API key / token',
          obscure: _obscureSmsKey,
          suffix: IconButton(
            icon: Icon(
                _obscureSmsKey
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 19,
                color: muted),
            onPressed: () =>
                setState(() => _obscureSmsKey = !_obscureSmsKey),
          ),
        ),
        _field(_smsSender, 'Sender ID'),
        Row(
          children: [
            const Expanded(
                child: Text('SMS enabled',
                    style: TextStyle(fontSize: 13.5, color: dark))),
            Switch(
              value: _smsEnabled,
              activeThumbColor: olive,
              onChanged: (v) => setState(() => _smsEnabled = v),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _savingSms ? null : _saveSms,
                icon: const Icon(Icons.save_outlined, size: 17),
                label: Text(_savingSms ? 'Saving…' : 'Save SMS'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: olive,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding:
                      const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _smsStatus,
                icon: const Icon(Icons.info_outline_rounded,
                    size: 17),
                label: const Text('Check status'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: olive,
                  side: const BorderSide(color: olive),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding:
                      const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _attendanceCard() {
    return _card(
      title: 'Attendance windows',
      subtitle: 'Late arrival and early-leaving prompts',
      icon: Icons.schedule_outlined,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: goldTint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.timer_outlined,
                size: 18, color: darkAmber),
          ),
          title: const Text('Late threshold',
              style: TextStyle(fontSize: 13.5, color: dark)),
          subtitle: const Text(
              'Clocking in after this asks for a reason',
              style: TextStyle(fontSize: 12, color: muted)),
          trailing: TextButton(
            onPressed: () => _pickCutoff(true),
            child: Text(
              _late.format(context),
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: olive),
            ),
          ),
        ),
        const Divider(height: 8, color: hairline),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFBE6E6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.logout_rounded,
                size: 18, color: danger),
          ),
          title: const Text('Early-leaving threshold',
              style: TextStyle(fontSize: 13.5, color: dark)),
          subtitle: const Text(
              'Clocking out before this asks for a reason',
              style: TextStyle(fontSize: 12, color: muted)),
          trailing: TextButton(
            onPressed: () => _pickCutoff(false),
            child: Text(
              _early.format(context),
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: olive),
            ),
          ),
        ),
      ],
    );
  }

  Widget _notificationsCard() {
    return _card(
      title: 'Notifications',
      subtitle: 'What gets captured in the inbox',
      icon: Icons.notifications_outlined,
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Activity logging',
                      style:
                          TextStyle(fontSize: 13.5, color: dark)),
                  Text('Clock in/out, broadcasts, roster exports',
                      style:
                          TextStyle(fontSize: 12, color: muted)),
                ],
              ),
            ),
            Switch(
              value: _activityLogging,
              activeThumbColor: olive,
              onChanged: (v) async {
                await ConfigService.setActivityLogging(v);
                setState(() => _activityLogging = v);
              },
            ),
          ],
        ),
        const Divider(height: 16, color: hairline),
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sign-in alerts',
                      style:
                          TextStyle(fontSize: 13.5, color: dark)),
                  Text('Log successful and failed sign-ins',
                      style:
                          TextStyle(fontSize: 12, color: muted)),
                ],
              ),
            ),
            Switch(
              value: _loginAlerts,
              activeThumbColor: olive,
              onChanged: (v) async {
                await ConfigService.setLoginAlerts(v);
                setState(() => _loginAlerts = v);
              },
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _saveSession() async {
    final hours = int.tryParse(_sessionCtrl.text.trim());
    final mins = int.tryParse(_inactivityCtrl.text.trim());
    if (hours == null ||
        hours < 1 ||
        hours > 720 ||
        mins == null ||
        mins < 1 ||
        mins > 480) {
      _snack('Enter session 1–720 hours and inactivity 1–480 minutes.');
      return;
    }
    setState(() => _savingSession = true);
    await ConfigService.setSessionHours(hours);
    await ConfigService.setInactivityMinutes(mins);
    NotificationService.logActivity(
      'Session settings updated',
      'Session length $hours h · inactivity logout $mins min.',
      category: 'System',
    );
    if (!mounted) return;
    setState(() => _savingSession = false);
    _snack(
        'Session settings saved. Session length applies from the next sign-in.',
        ok: true);
  }

  Widget _sessionCard() {
    return _card(
      title: 'Session & auto-logout',
      subtitle: 'How long sign-ins last',
      icon: Icons.timer_outlined,
      children: [
        Row(
          children: [
            Expanded(
              child: _field(_sessionCtrl, 'Session length (hours)',
                  keyboard: TextInputType.number),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _field(_inactivityCtrl, 'Inactivity logout (min)',
                  keyboard: TextInputType.number),
            ),
          ],
        ),
        const Text(
          'Session length is stamped into the token at sign-in, so changes apply from the next sign-in. Inactivity logout applies right away.',
          style: TextStyle(fontSize: 12, color: muted),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _savingSession ? null : _saveSession,
            icon: const Icon(Icons.save_outlined, size: 17),
            label: Text(
                _savingSession ? 'Saving…' : 'Save session settings'),
            style: ElevatedButton.styleFrom(
              backgroundColor: olive,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
          ),
        ),
      ],
    );
  }

  Widget _serverCard() {
    return _card(
      title: 'Server',
      subtitle: 'Backend connection (read-only)',
      icon: Icons.dns_outlined,
      children: [
        _field(
          TextEditingController(text: AppConfig.apiBaseUrl),
          'API base URL',
          readOnly: true,
          suffix: IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy_rounded,
                size: 18, color: muted),
            onPressed: () {
              Clipboard.setData(
                  ClipboardData(text: AppConfig.apiBaseUrl));
              _snack('API URL copied.', ok: true);
            },
          ),
        ),
        const Text(
          'Change API_BASE_URL in the .env file to point at a different server.',
          style: TextStyle(fontSize: 12, color: muted),
        ),
      ],
    );
  }
}
