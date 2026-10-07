// OTP verification screen — second step of email 2FA.
//
// Used in two places:
//   1. Login: after password login succeeds for an officer with 2FA on.
//   2. Settings: after tapping "enable", to prove the email reaches them
//      before the toggle is persisted.
//
// Caller must have already sent the OTP via TwoFactorService.sendOtp().
// This screen only collects + verifies the code (and handles resend).

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gis_attendance/services/two_factor_service.dart';
import 'package:gis_attendance/theme/gis_palette.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String officerIdOrUsername;
  final String email;
  final String title;
  final String subtitle;
  final String confirmLabel;
  final Future<void> Function()? onVerified;

  const OtpVerificationScreen({
    super.key,
    required this.officerIdOrUsername,
    required this.email,
    this.title = 'Check your email',
    this.subtitle = '',
    this.confirmLabel = 'Verify & Continue',
    this.onVerified,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  // GIS Theme Colors now resolve from GisPalette (light/dark aware).

  final _twoFactor = TwoFactorService();
  final _codeController = TextEditingController();

  bool _verifying = false;
  bool _resending = false;
  String? _error;
  int _resendIn = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
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

  Future<void> _resend() async {
    if (_resendIn > 0 || _resending) return;
    setState(() {
      _resending = true;
      _error = null;
    });
    final res = await _twoFactor.sendOtp(
      officerIdOrUsername: widget.officerIdOrUsername,
      email: widget.email,
    );
    if (!mounted) return;
    setState(() => _resending = false);
    if (res.ok) {
      _startResendTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message), backgroundColor: Colors.green),
      );
    } else {
      setState(() => _error = res.message);
    }
  }

  Future<void> _verify() async {
    if (_verifying) return;
    setState(() {
      _verifying = true;
      _error = null;
    });
    final res = await _twoFactor.verifyOtp(
      officerIdOrUsername: widget.officerIdOrUsername,
      code: _codeController.text,
    );
    if (!mounted) return;
    setState(() => _verifying = false);
    if (res.ok) {
      if (widget.onVerified != null) {
        await widget.onVerified!();
      }
      if (mounted) Navigator.of(context).pop(true);
    } else {
      setState(() => _error = res.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final masked = _twoFactor.maskEmail(widget.email);
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
            widget.title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: GisPalette.of(context).primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.subtitle.isNotEmpty
                ? widget.subtitle
                : 'We sent a 6-digit code to $masked. Enter it below to continue.',
            style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),
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
                borderSide: BorderSide(color: GisPalette.of(context).primary, width: 2.0),
              ),
            ),
          ),
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
              child: Text(
                _error!,
                style: TextStyle(
                  color: GisPalette.of(context).danger,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
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
                elevation: 4,
                shadowColor: GisPalette.of(context).primary.withValues(alpha: 0.5),
              ),
              child: Text(
                _verifying ? 'Verifying…' : widget.confirmLabel.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: _resending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton(
                    onPressed: _resendIn > 0 ? null : _resend,
                    child: Text(
                      _resendIn > 0
                          ? 'Resend code in ${_resendIn}s'
                          : 'Resend code',
                      style: TextStyle(
                        color: _resendIn > 0
                            ? Colors.grey.shade500
                            : GisPalette.of(context).primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
          ),
          Center(
            child: TextButton(
              onPressed: _verifying ? null : () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: GisPalette.of(context).bg,
      appBar: AppBar(
        title: const Text(
          'Two-factor verification',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        backgroundColor: Colors.white,
        foregroundColor: GisPalette.of(context).darkBg,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxWidth: wide ? 420 : double.infinity),
            child: card,
          ),
        ),
      ),
    );
  }
}
