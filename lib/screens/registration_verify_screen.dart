// Registration contact-verification screen.
//
// Shown when POST /api/auth/register answers that the officer must verify
// their email/phone with a code first (instead of a dead-end error
// banner). The officer picks the channel (Email / SMS — only channels they
// actually provided an address/number for are offered), receives the code
// the server sends, and enters it here. On success the screen pops `true`
// and the caller finishes registration (face upload + pending-approval
// message).

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gis_attendance/services/auth_service.dart';
import 'package:gis_attendance/theme/gis_palette.dart';

class RegistrationVerifyScreen extends StatefulWidget {
  final String officerId;
  final String email;
  final String phoneNumber;

  const RegistrationVerifyScreen({
    super.key,
    required this.officerId,
    required this.email,
    required this.phoneNumber,
  });

  @override
  State<RegistrationVerifyScreen> createState() =>
      _RegistrationVerifyScreenState();
}

class _RegistrationVerifyScreenState extends State<RegistrationVerifyScreen> {
  final _authService = AuthService();
  final _codeController = TextEditingController();

  late String _channel; // 'email' or 'sms'
  bool _sending = false;
  bool _verifying = false;
  bool _codeSent = false;
  String? _error;
  String? _info;
  int _resendIn = 0;
  Timer? _timer;

  String get _identifier =>
      _channel == 'email' ? widget.email.trim() : widget.phoneNumber.trim();

  String get _maskedTarget {
    final id = _identifier;
    if (_channel == 'email') {
      final parts = id.split('@');
      if (parts.length != 2) return id;
      final name = parts[0];
      final shown = name.length <= 2 ? '${name[0]}…' : '${name.substring(0, 2)}…';
      return '$shown@${parts[1]}';
    }
    return id.length <= 4 ? id : '…${id.substring(id.length - 4)}';
  }

  @override
  void initState() {
    super.initState();
    // Default to email when one is on file, else SMS.
    _channel = widget.email.trim().isNotEmpty ? 'email' : 'sms';
    // The register call already triggered one code; offer resend after 30s.
    _startResendTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _timer?.cancel();
    setState(() => _resendIn = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_resendIn <= 1) {
        t.cancel();
        setState(() => _resendIn = 0);
      } else {
        setState(() => _resendIn -= 1);
      }
    });
  }

  Future<void> _sendCode() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = null;
      _info = null;
    });
    final res = await _authService.sendRegistrationOtp(
      identifier: _identifier,
      channel: _channel,
    );
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (res.ok) {
        _codeSent = true;
        _info = res.message;
        _startResendTimer();
      } else {
        _error = res.message;
      }
    });
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter the code that was sent to you.');
      return;
    }
    if (_verifying) return;
    setState(() {
      _verifying = true;
      _error = null;
    });
    final res = await _authService.verifyRegistrationOtp(
      identifier: _identifier,
      code: code,
    );
    if (!mounted) return;
    setState(() => _verifying = false);
    if (res.ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = res.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasEmail = widget.email.trim().isNotEmpty;
    final hasPhone = widget.phoneNumber.trim().isNotEmpty;
    final wide = MediaQuery.of(context).size.width >= 800;

    final card = Container(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: GisPalette.of(context).primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.mark_email_read_outlined,
                color: GisPalette.of(context).primary, size: 26),
          ),
          const SizedBox(height: 16),
          Text(
            'Verify your contact',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: GisPalette.of(context).primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'The server requires email/phone verification before your '
            'account is created. Pick where to receive the code — '
            'registration completes as soon as it verifies.',
            style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          // Channel choice — only offered channels are selectable.
          Row(
            children: [
              Expanded(
                child: _ChannelOption(
                  icon: Icons.mail_outline_rounded,
                  label: 'Email',
                  selected: _channel == 'email',
                  enabled: hasEmail,
                  onTap: hasEmail
                      ? () => setState(() {
                            _channel = 'email';
                            _codeSent = false;
                            _error = null;
                            _info = null;
                          })
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ChannelOption(
                  icon: Icons.sms_outlined,
                  label: 'SMS',
                  selected: _channel == 'sms',
                  enabled: hasPhone,
                  onTap: hasPhone
                      ? () => setState(() {
                            _channel = 'sms';
                            _codeSent = false;
                            _error = null;
                            _info = null;
                          })
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _channel == 'email'
                ? (hasEmail
                    ? 'Code goes to $_maskedTarget'
                    : 'No email on file — add one or use SMS.')
                : (hasPhone
                    ? 'Code goes to $_maskedTarget'
                    : 'No phone number on file — add one or use email.'),
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: _sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined, size: 18),
              label: Text(_codeSent ? 'Send again' : 'Send code'),
              onPressed: _sending || _identifier.isEmpty ? null : _sendCode,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            enabled: !_verifying,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: 8,
              color: GisPalette.of(context).darkBg,
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) => _verify(),
            decoration: InputDecoration(
              hintText: '••••••',
              counterText: '',
              filled: true,
              fillColor: GisPalette.of(context).bg,
              contentPadding: const EdgeInsets.symmetric(vertical: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    BorderSide(color: GisPalette.of(context).primary, width: 2.0),
              ),
            ),
          ),
          if (_info != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Text(_info!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.green,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: GisPalette.of(context).danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: GisPalette.of(context).danger.withValues(alpha: 0.3)),
              ),
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: GisPalette.of(context).danger,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _verifying ? null : _verify,
              style: ElevatedButton.styleFrom(
                backgroundColor: GisPalette.of(context).primary,
                disabledBackgroundColor: Colors.grey.shade400,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _verifying ? 'Verifying…' : 'VERIFY & COMPLETE REGISTRATION',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _verifying
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: Text('Back',
                  style: TextStyle(color: Colors.grey.shade600)),
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: GisPalette.of(context).bg,
      appBar: AppBar(
        title: Text('Verify contact',
            style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: GisPalette.of(context).ink)),
        backgroundColor: Colors.white,
        foregroundColor: GisPalette.of(context).ink,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxWidth: wide ? 440 : double.infinity),
            child: card,
          ),
        ),
      ),
    );
  }
}

class _ChannelOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  const _ChannelOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = GisPalette.of(context);
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? palette.primary.withValues(alpha: 0.1) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? palette.primary : Colors.grey.shade300,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 18,
                  color: selected ? palette.primary : Colors.grey.shade600),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: selected ? palette.primary : Colors.grey.shade700)),
            ],
          ),
        ),
      ),
    );
  }
}
