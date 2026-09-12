// LOGIN SCREEN

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:gis_attendance/services/auth_service.dart';
import 'home_screen.dart';
import 'register_screen.dart';
import 'package:gis_attendance/widgets/loading_indicator.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

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


  bool _biometricAvailable = false;
  bool _hasStoredCredentials = false;

  // GIS Theme Colors
  static const Color gisDeepOlive = Color(0xFF2E4D2A);
  static const Color gisDarkBackground = Color(0xFF142412);
  static const Color ghanaGold = Color(0xFFE1B12C);
  static const Color nationalRed = Color(0xFFD63031);
  static const Color lightGrayBg = Color(0xFFF5F6F5);

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
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      } else {
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
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      } else {
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
        _error = 'An error occurred during biometric login.';
      });
    }
  }

  void _navigateToRegister() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient (Deep Secure GIS Olive to Vigilant Dark Forest Green)
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  gisDarkBackground,
                  gisDeepOlive,
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // GIS Themed Crest/Logo Placeholder
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: ghanaGold.withValues(alpha: 0.5),
                          width: 2,
                        ),
                      ),
                      child: SizedBox(
                        height: 80,
                        width: 80,
                        child: ImageIcon(
                          const AssetImage('assets/default_avatar.png'),
                          color: ghanaGold, // Changed default icon to represent GIS Gold
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Official Title
                    const Text(
                      "Ghana Immigration Service",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),

                    // Motto Subtitle (Friendship with Vigilance)
                    const Text(
                      "Friendship with Vigilance",
                      style: TextStyle(
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w500,
                        color: ghanaGold, // Highlights motto in Gold
                        letterSpacing: 1.0,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 30),

                    // Login Card
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 30,
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
                          // Username Label
                          const Text(
                            "Officer ID",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: gisDeepOlive, // Brand color labels
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
                              prefixIcon: const Icon(
                                Icons.person_outline_rounded,
                                color: gisDeepOlive,
                              ),
                              filled: true,
                              fillColor: lightGrayBg,
                              contentPadding: const EdgeInsets.symmetric(vertical: 18),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: gisDeepOlive,
                                  width: 2.0,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),

                          // Password Label
                          const Text(
                            "Secure Password",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: gisDeepOlive,
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
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                                color: gisDeepOlive,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureText
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: gisDeepOlive.withValues(alpha: 0.7),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscureText = !_obscureText;
                                  });
                                },
                              ),
                              filled: true,
                              fillColor: lightGrayBg,
                              contentPadding: const EdgeInsets.symmetric(vertical: 18),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: gisDeepOlive,
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
                                color: nationalRed.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: nationalRed.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: nationalRed,
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
                                backgroundColor: gisDeepOlive,
                                disabledBackgroundColor: Colors.grey.shade400,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 4,
                                shadowColor: gisDeepOlive.withValues(alpha: 0.5),
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
                                icon: const Icon(
                                  Icons.fingerprint,
                                  color: ghanaGold,
                                  size: 24,
                                ),
                                label: const Text(
                                  'Sign In with Biometrics',
                                  style: TextStyle(
                                    color: gisDeepOlive,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: gisDeepOlive,
                                  disabledForegroundColor: Colors.grey.shade300,
                                  side: const BorderSide(
                                    color: ghanaGold,
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
                                color: ghanaGold.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'Biometric login is inactive on this device',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: gisDeepOlive,
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
                                foregroundColor: gisDeepOlive,
                                disabledForegroundColor: Colors.grey.shade300,
                                side: BorderSide(
                                  color: gisDeepOlive.withValues(alpha: 0.5),
                                  width: 1.5,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              child: const Text(
                                "CREATE ACCOUNT",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  letterSpacing: 0.5,
                                  color: gisDeepOlive,
                                ),
                              ),
                            ),
                          ),

                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Official Footer Info
                    Text(
                      "© ${DateTime.now().year} Ghana Immigration Service (GIS)",
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "ICT & Digital Transformation Division",
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Loading Indicator Overlay
          if (_loading)
            const StylishLoadingIndicator(),
        ],
      ),
    );
  }
}