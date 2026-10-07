// LOGIN SCREEN

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:gis_attendance/services/auth_service.dart';
import 'package:gis_attendance/services/notification_service.dart';
import 'package:gis_attendance/services/two_factor_service.dart';
import 'home_screen.dart';
import 'register_screen.dart';
import 'otp_verification_screen.dart';
import 'package:gis_attendance/widgets/loading_indicator.dart';
import 'package:gis_attendance/theme/gis_palette.dart';

class LoginScreen extends StatefulWidget {
  /// When true the user just signed out: show a "signed out" note plus a
  /// "Close app" option underneath the form.
  final bool fromLogout;
  const LoginScreen({super.key, this.fromLogout = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;

  bool _loading = false;
  String? _error;
  bool _obscureText = true;

  final AuthService _authService = AuthService();
  final LocalAuthentication _localAuth = LocalAuthentication();
  final TwoFactorService _twoFactor = TwoFactorService();


  bool _biometricAvailable = false;
  bool _hasStoredCredentials = false;

  // GIS Theme Colors now resolve from GisPalette (light/dark aware).

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _initBiometrics();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _initBiometrics() async {
    if (kIsWeb) {
      setState(() => _biometricAvailable = false);
      return;
    }

    try {
      // Check biometric support
      final canCheck = await _localAuth.canCheckBiometrics;
      final supported = await _localAuth.isDeviceSupported();

      // Check if credentials are stored
      final hasCreds = await _authService.hasStoredCredentials();

      // Fetch stored username if credentials exist
      String storedUsername = '';
      if (hasCreds) {
        try {
          final credentials = await _authService.getStoredCredentials();
          if (credentials != null && credentials.containsKey('username')) {
            storedUsername = credentials['username'] ?? '';
            if (kDebugMode) {
              print("✅ Loaded username from storage: $storedUsername");
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print("❌ Error fetching stored credentials: $e");
          }
        }
      }

      if (!mounted) return;

      // Update state with all data
      setState(() {
        _biometricAvailable = canCheck && supported;
        _hasStoredCredentials = hasCreds;
        // Set the username field
        if (storedUsername.isNotEmpty) {
          _usernameController.text = storedUsername;
        }
      });

      if (kDebugMode) {
        print("Init Biometrics - Available: $_biometricAvailable, HasCreds: $_hasStoredCredentials");
      }
    } catch (e) {
      if (kDebugMode) {
        print("❌ Error in _initBiometrics: $e");
      }
      if (!mounted) return;
      setState(() {
        _biometricAvailable = false;
        _hasStoredCredentials = false;
      });
    }
  }

  Future<void> _login() async {
    final String username = _usernameController.text.trim();
    final String password = _passwordController.text.trim();

    // Validation
    if (username.isEmpty && password.isEmpty) {
      setState(() {
        _error = "Username and Password cannot be empty.";
      });
      return;
    }

    if (username.isEmpty) {
      setState(() {
        _error = "Username cannot be empty.";
      });
      return;
    }

    if (password.isEmpty) {
      setState(() {
        _error = "Enter a valid password";
      });
      return;
    }

    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _authService.login(username, password);

      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      if (result.success) {
        await _enterAfterPassword(username, viaBiometrics: false);
      } else {
        NotificationService.logActivity(
          'Sign-in failed',
          'Failed sign-in attempt for officer $username.',
          category: 'Security',
          loginEvent: true,
        );
        setState(() {
          _error = result.message;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print("❌ Login error: $e");
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "An error occurred during login.";
      });
    }
  }

  /// Shared post-password gate: plain sign-in when 2FA is OFF (default),
  /// otherwise send an email OTP and only enter Home after it verifies.
  /// The session is discarded if the code step is cancelled so the token
  /// alone can't be used to bypass the second factor.
  Future<void> _enterAfterPassword(String username,
      {required bool viaBiometrics}) async {
    final label = viaBiometrics ? ' with biometrics' : '';
    // Effective gate: System Config switch AND this officer's opt-in.
    // Ships dormant (both default OFF) until SMTP is live and enabled.
    final enabled = await _twoFactor.isRequiredFor(username);
    if (!enabled) {
      NotificationService.logActivity(
        'Signed in',
        'Officer $username signed in$label.',
        category: 'Security',
        loginEvent: true,
      );
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
      return;
    }

    final profile = await _authService.getStoredProfile();
    final email = (profile?['email'] ?? '').toString().trim();
    if (email.isEmpty || !RegExp(r'\S+@\S+\.\S+').hasMatch(email)) {
      // Fail open (don't lock the officer out) but say so plainly.
      NotificationService.logActivity(
        'Signed in',
        'Officer $username signed in$label (2FA skipped — no email).',
        category: 'Security',
        loginEvent: true,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                '2FA is on but no email is on file — signed in without the code. Update your email in Settings.'),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final sent = await _twoFactor.sendOtp(
      officerIdOrUsername: username,
      email: email,
    );
    if (!mounted) return;
    setState(() => _loading = false);

    if (!sent.ok) {
      await _authService.logout();
      setState(() => _error = sent.message);
      return;
    }

    final verified = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => OtpVerificationScreen(
          officerIdOrUsername: username,
          email: email,
        ),
      ),
    );
    if (!mounted) return;
    if (verified == true) {
      NotificationService.logActivity(
        'Signed in',
        'Officer $username signed in$label (2FA verified).',
        category: 'Security',
        loginEvent: true,
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      await _authService.logout();
      setState(() {
        _error = 'Verification cancelled — you are still signed out.';
      });
    }
  }

  Future<void> _loginWithBiometrics() async {
    // Check if biometric is available
    if (!_biometricAvailable) {
      setState(() {
        _error = 'Biometric authentication is not available on this device.';
      });
      return;
    }

    // Check if credentials are stored
    if (!_hasStoredCredentials) {
      setState(() {
        _error = 'No stored credentials found. Please sign in manually first.';
      });
      return;
    }

    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Authenticate with biometrics
      final didAuth = await _localAuth.authenticate(
        localizedReason: 'Authenticate to sign in',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () => false,
      );

      if (!didAuth) {
        setState(() {
          _loading = false;
          _error = 'Biometric authentication was cancelled.';
        });
        return;
      }

      // Get stored credentials
      final credentials = await _authService.getStoredCredentials();
      if (credentials == null || credentials['username'] == null || credentials['password'] == null) {
        setState(() {
          _loading = false;
          _error = 'Stored credentials not found.';
        });
        return;
      }

      // Perform login
      final result = await _authService.login(
        credentials['username']!,
        credentials['password']!,
      );

      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      if (result.success) {
        await _enterAfterPassword(credentials['username']!,
            viaBiometrics: true);
      } else {
        NotificationService.logActivity(
          'Sign-in failed',
          "Failed biometric sign-in for officer ${credentials['username']}.",
          category: 'Security',
          loginEvent: true,
        );
        setState(() {
          _error = result.message;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print("❌ Biometric login error: $e");
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Biometric error: $e';
      });
    }
  }

  void _navigateToRegister() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
    );
  }

  /// Exit the app from the sign-in page (offered after a logout). Web
  /// can't close the window programmatically, so the button is hidden
  /// there.
  Future<void> _closeApp() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Close app?',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('The app will be closed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay',
                style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: GisPalette.of(context).primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Close app'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      SystemNavigator.pop();
    }
  }

  /// Side image for wide screens (left panel, larger, full height).
  Widget _buildSideImage() {
    return Container(
      height: double.infinity,
      width: double.infinity,
      color: GisPalette.of(context).darkBg,
      child: Image.asset(
        'assets/login.png',
        fit: BoxFit.cover,
        alignment: Alignment.center,
        errorBuilder: (_, __, ___) => Center(
          child: Icon(Icons.shield_outlined, color: GisPalette.of(context).gold, size: 64),
        ),
      ),
    );
  }

  /// Top banner for narrow screens.
  Widget _buildTopBanner() {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(28),
        bottomRight: Radius.circular(28),
      ),
      child: Image.asset(
        'assets/login.png',
        width: double.infinity,
        height: 250,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        errorBuilder: (_, __, ___) => Container(
          width: double.infinity,
          height: 250,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [GisPalette.of(context).darkBg, GisPalette.of(context).primary],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Center(
            child: Icon(Icons.shield_outlined, color: GisPalette.of(context).gold, size: 64),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        Text(
          "© ${DateTime.now().year} Ghana Immigration Service (GIS)",
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          "Safe Migration, Secure Ghana",
          style: TextStyle(
            color: Colors.grey.shade500,
            fontSize: 11,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  /// Shared login form card (used by both wide and narrow layouts).
  Widget _buildLoginCard() {
    return Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 26,
                                horizontal: 20,
                              ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Card header — banner already carries GIS branding
                          Text(
                            "Welcome back",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: GisPalette.of(context).primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Sign in with your Officer ID to continue",
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Username Label
                          Text(
                            "Officer ID",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: GisPalette.of(context).primary, // Brand color labels
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Username Field
                          TextFormField(
                            controller: _usernameController,
                            keyboardType: TextInputType.text,
                            enabled: !_loading,
                            style: const TextStyle(color: Colors.black87),
                            decoration: InputDecoration(
                              hintText: "Enter your officer ID",
                              hintStyle: TextStyle(color: Colors.grey.shade400),
                              prefixIcon: Icon(
                                Icons.person_outline_rounded,
                                color: GisPalette.of(context).primary,
                              ),
                              filled: true,
                              fillColor: GisPalette.of(context).bg,
                              contentPadding: const EdgeInsets.symmetric(vertical: 18),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: GisPalette.of(context).primary,
                                  width: 2.0,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),

                          // Password Label
                          Text(
                            "Secure Password",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: GisPalette.of(context).primary,
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Password Field
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscureText,
                            enabled: !_loading,
                            style: const TextStyle(color: Colors.black87),
                            decoration: InputDecoration(
                              hintText: "Enter your password",
                              hintStyle: TextStyle(color: Colors.grey.shade400),
                              prefixIcon: Icon(
                                Icons.lock_outline_rounded,
                                color: GisPalette.of(context).primary,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureText
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: GisPalette.of(context).primary.withValues(alpha: 0.7),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscureText = !_obscureText;
                                  });
                                },
                              ),
                              filled: true,
                              fillColor: GisPalette.of(context).bg,
                              contentPadding: const EdgeInsets.symmetric(vertical: 18),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: GisPalette.of(context).primary,
                                  width: 2.0,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Error Message State (Styled using Brand National Red)
                          if (_error != null)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: GisPalette.of(context).danger.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: GisPalette.of(context).danger.withValues(alpha: 0.3),
                                ),
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
                          const SizedBox(height: 24),

                          // Sign In Button (Deep Olive & Gold Elevation Theme)
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _loading ? null : _login,
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
                                _loading ? "Authenticating..." : "SECURE SIGN IN",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Biometric Button (Aligned with Ghana Gold highlights)
                          if (_biometricAvailable)
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _loading ? null : _loginWithBiometrics,
                                icon: Icon(
                                  Icons.fingerprint,
                                  color: GisPalette.of(context).gold,
                                  size: 24,
                                ),
                                label: Text(
                                  'Sign In with Biometrics',
                                  style: TextStyle(
                                    color: GisPalette.of(context).primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: GisPalette.of(context).primary,
                                  disabledForegroundColor: Colors.grey.shade300,
                                  side: BorderSide(
                                    color: GisPalette.of(context).gold,
                                    width: 1.5,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                              ),
                            )
                          else if (_hasStoredCredentials && !_biometricAvailable)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: GisPalette.of(context).gold.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'Biometric login is inactive on this device',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: GisPalette.of(context).primary,
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          const SizedBox(height: 20),

                          // Divider
                          Row(
                            children: [
                              Expanded(
                                child: Divider(
                                  color: Colors.grey.shade300,
                                  thickness: 1,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  "OR",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Divider(
                                  color: Colors.grey.shade300,
                                  thickness: 1,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),

                          // Register Button
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: _loading ? null : _navigateToRegister,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: GisPalette.of(context).primary,
                                disabledForegroundColor: Colors.grey.shade300,
                                side: BorderSide(
                                  color: GisPalette.of(context).primary.withValues(alpha: 0.5),
                                  width: 1.5,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              child: Text(
                                "CREATE ACCOUNT",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  letterSpacing: 0.5,
                                  color: GisPalette.of(context).primary,
                                ),
                              ),
                            ),
                          ),

                          // After a logout: signed-out note + Close app option.
                          if (widget.fromLogout && !kIsWeb) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: GisPalette.of(context)
                                    .primary
                                    .withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'You have been signed out.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: TextButton.icon(
                                onPressed:
                                    _loading ? null : _closeApp,
                                icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18),
                                label: const Text(
                                  'Close app',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                          ],

                        ],
                      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 800;
    if (wide) {
      // Wide grid: image on the left (larger, full height),
      // form on the right (smaller).
      return Scaffold(
        backgroundColor: GisPalette.of(context).bg,
        body: Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: _buildSideImage()),
                Expanded(
                  flex: 2,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 28),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Column(
                          children: [
                            _buildLoginCard(),
                            const SizedBox(height: 24),
                            _buildFooter(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_loading) const StylishLoadingIndicator(),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: GisPalette.of(context).bg,
      body: Stack(
        children: [
          // Light background with GIS hero banner (assets/login.png)
          SingleChildScrollView(
            child: Column(
              children: [
                _buildTopBanner(),

                // --- Form area (overlaps banner, constrained for web) ---
                Transform.translate(
                  offset: const Offset(0, -28),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          children: [
                            _buildLoginCard(),
                            const SizedBox(height: 24),
                            _buildFooter(),
                            const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            ), // Center
          ), // Transform.translate
        ], // outer Column
      ), // outer Column
    ), // SingleChildScrollView,

          // Loading Indicator Overlay
          if (_loading)
            const StylishLoadingIndicator(),
        ],
      ),
    );
  }
}
