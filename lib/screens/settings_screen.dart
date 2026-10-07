//SETTINGS SCREEN

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gis_attendance/services/auth_service.dart';
import 'package:gis_attendance/services/attendance_service.dart';
import 'package:gis_attendance/services/config_service.dart';
import 'package:gis_attendance/services/notification_service.dart';
import 'package:gis_attendance/services/two_factor_service.dart';
import 'package:gis_attendance/services/update_service.dart';
import 'package:gis_attendance/theme/gis_palette.dart';
import 'package:gis_attendance/widgets/app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:gis_attendance/screens/otp_verification_screen.dart';


class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}


class Department {
  final int id;
  final String name;

  Department({required this.id, required this.name});

  factory Department.fromJson(Map<String, dynamic> json) {
    return Department(
      id: json['id'],
      name: json['name'],
    );
  }
}

class Branch {
  final int id;
  final String name;
  final List<Department> departments;

  Branch({required this.id, required this.name, required this.departments});

  factory Branch.fromJson(Map<String, dynamic> json) {
    var deptsFromJson = json['departments'] as List;
    List<Department> deptList = deptsFromJson.map((i) => Department.fromJson(i)).toList();
    return Branch(
      id: json['id'],
      name: json['name'],
      departments: deptList,
    );
  }
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _attendanceService = AttendanceService();
  final _localAuth = LocalAuthentication();
  final _picker = ImagePicker();

  // GIS theme resolves from GisPalette (light only).

  bool _biometricsEnabled = true;
  bool _canCheckBiometrics = false;
  String _currentVersion = '';
  bool _updateChecking = false;
  File? _profileImage;
  File? _newProfileImage;
  bool _isSaving = false;
  Uint8List? imageBytes;

  // Two-factor authentication (email OTP). Defaults to OFF — only true
  // after the officer explicitly enables + verifies it below.
  final _twoFactor = TwoFactorService();
  bool _twoFactorEnabled = false;
  bool _twoFactorBusy = false;
  // Global kill-switch from System Config (admin). The card stays visible
  // either way so it's ready to use once SMTP is configured and an admin
  // flips it on; enabling is blocked until then.
  bool _twoFactorAllowedByConfig = false;


  final _fullNameController = TextEditingController();
  final _idController = TextEditingController();
  // final _name = TextEditingController();
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _departmentController = TextEditingController();

  // static const String _isBiometricEnabledKey = "is_biometric_enabled";

  late Future<Map<String, dynamic>> _profileFuture;

  List<Branch> _branchOptions = [];
  Branch? _selectedBranch;
  // Department? _selectedDepartment;

  @override
  void initState() {
    super.initState();
    // _loadBranchesAndDepartments();

    _loadSettings();
    _profileFuture = _fetchProfile();
  }


  Future<void> _removeBiometric() async {
    await _authService.clearStoredCredentials();
    print("Biometric credentials cleared.");
  }

  // -- NEW METHOD TO SET INITIAL VALUES --
  Future<void> _initializeSelectionsFromProfile() async {
    // Wait for the profile to be loaded
    final user = await _profileFuture;
    final userBranchName = user['branch']; // Assuming profile contains branch name/ID
    final userDeptName = user['department']; // Assuming profile contains department name/ID

    if (_branchOptions.isNotEmpty && userBranchName != null) {
      try {
        _selectedBranch = _branchOptions.firstWhere((b) => b.name == userBranchName);

        if (_selectedBranch != null && _selectedBranch!.name.toLowerCase() == 'head office' && userDeptName != null) {
     
        }
      } catch (e) {
        print("Could not pre-select branch/department from profile: $e");
        _selectedBranch = null;
      }
      setState(() {});
    }
  }

  @override
  void dispose() {
    // Dispose controllers to free up resources
    
    _idController.dispose();
    _fullNameController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    _departmentController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _biometricsEnabled = prefs.getBool('biometrics_enabled') ?? false;

    try {
      _canCheckBiometrics = await _localAuth.canCheckBiometrics;
    } catch (e) {
      _canCheckBiometrics = false;
    }
    try {
      final pkg = await PackageInfo.fromPlatform();
      _currentVersion = pkg.version;
    } catch (_) {
      _currentVersion = '';
    }
    if (mounted) {
      setState(() {});
    }
    // 2FA toggle is per-officer and defaults to OFF — refresh once the
    // cached profile (username) is available.
    _refreshTwoFactorFlag();
  }

  /// Manual "Check for updates" — downloads + installs over the current
  /// app, keeping all data. No uninstall needed.
  Future<void> _manualUpdateCheck() async {
    if (_updateChecking) return;
    setState(() => _updateChecking = true);
    try {
      final result = await UpdateService.check();
      if (!mounted) return;
      setState(() => _updateChecking = false);
      if (result.update != null) {
        await AppUpdate.prompt(context, result.update!);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _updateChecking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update check failed: $e')),
      );
    }
  }

  Future<void> _refreshTwoFactorFlag() async {
    try {
      final stored = await _authService.getStoredProfile();
      final key = _twoFactorKey(stored);
      final enabled = await _twoFactor.isEnabled(key);
      final allowed = await ConfigService.twoFactorAllowed();
      if (mounted) {
        setState(() {
          _twoFactorEnabled = enabled;
          _twoFactorAllowedByConfig = allowed;
        });
      }
    } catch (_) {
      // stays OFF on any failure
    }
  }

  String _twoFactorKey([Map<String, dynamic>? profile]) {
    final username = _usernameController.text.trim().isNotEmpty
        ? _usernameController.text.trim()
        : (profile?['username'] ?? profile?['officerId'] ?? 'unknown')
            .toString();
    return _twoFactor.keyFor(username);
  }

  String _twoFactorEmail([Map<String, dynamic>? profile]) {
    if (_emailController.text.trim().isNotEmpty) {
      return _emailController.text.trim();
    }
    return (profile?['email'] ?? '').toString().trim();
  }

  /// Enabling = send OTP -> verify on the OTP screen -> persist ON.
  /// Disabling = confirm dialog -> persist OFF. The switch visually
  /// reverts on any cancel/failure so it never lies about the state.
  Future<void> _toggleTwoFactor(bool value, Map<String, dynamic> profile) async {
    if (_twoFactorBusy) return;
    if (value == _twoFactorEnabled) return;

    final officerKey = _twoFactorKey(profile);
    final email = _twoFactorEmail(profile);

    if (value) {
      // Global switch (System Config) must be on first — it stays OFF
      // until the server mailer is configured.
      final allowed = await ConfigService.twoFactorAllowed();
      if (mounted) setState(() => _twoFactorAllowedByConfig = allowed);
      if (!allowed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Two-factor authentication is not enabled by your administrator yet. Ask an admin to turn it on in System Config once email is working.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
      if (email.isEmpty || !RegExp(r'\S+@\S+\.\S+').hasMatch(email)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Add a valid email to your profile first — the code is sent there.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      setState(() => _twoFactorBusy = true);
      final sent = await _twoFactor.sendOtp(
        officerIdOrUsername: officerKey,
        email: email,
      );
      if (!mounted) return;
      setState(() => _twoFactorBusy = false);
      if (!sent.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sent.message), backgroundColor: Colors.red),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sent.message), backgroundColor: Colors.green),
      );
      final verified = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(
            officerIdOrUsername: officerKey,
            email: email,
            title: 'Verify your email',
            subtitle:
                'Enter the 6-digit code we just sent to ${_twoFactor.maskEmail(email)} to turn on two-factor authentication.',
            confirmLabel: 'Verify & Enable',
          ),
        ),
      );
      if (!mounted) return;
      if (verified == true) {
        await _twoFactor.setEnabled(officerKey, true);
        setState(() => _twoFactorEnabled = true);
        NotificationService.logActivity(
          'Two-factor authentication enabled',
          'Email OTP sign-in was turned on.',
          category: 'Security',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Two-factor authentication enabled.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        await _twoFactor.clearOtp(officerKey);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verification cancelled — 2FA stays off.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // Turning OFF — confirm so an accidental tap doesn't drop protection.
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Turn off 2FA?',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text(
            'You will sign in with just your officer ID and password.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Keep it on',
                style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: GisPalette.of(context).danger,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Turn off'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await _twoFactor.setEnabled(officerKey, false);
    setState(() => _twoFactorEnabled = false);
    NotificationService.logActivity(
      'Two-factor authentication disabled',
      'Email OTP sign-in was turned off.',
      category: 'Security',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Two-factor authentication disabled.'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Future<Map<String, dynamic>> _fetchProfile() async {
    try {
      final user = await _attendanceService.getMyProfile();

      if (user != null) {
        // Pre-fill controllers when data is fetched
        _idController.text = user["id"]?.toString() ?? '';
        _fullNameController.text = user['fullName'] ?? '';
        _emailController.text = user['email'] ?? '';
        _usernameController.text = user['username'] ?? '';
        _departmentController.text = user['department'] ?? '';
        _profileImage != null ? Image.file(_profileImage!, fit: BoxFit.cover)
            : const Icon(Icons.account_circle, size: 100, color: Colors.grey);

        // Profile (username) is now known — resolve the per-officer 2FA
        // flag (defaults to OFF).
        _refreshTwoFactorFlag();
        return user;
      } else {
        throw Exception('User profile not found.');
      }
    } catch (e) {
      // Propagate error to FutureBuilder
      throw Exception('Failed to load profile: $e');
    }
  }

  Future<void> _showImageSourceDialog() async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Select Image Source", style: TextStyle(fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: GisPalette.of(context).oliveTint, borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.camera_alt, color: GisPalette.of(context).primary, size: 19),
                ),
                title: const Text('Camera'),
                onTap: () {
                  Navigator.of(context).pop(); // Close the dialog
                  _getImage(ImageSource.camera); // Get image from camera
                },
              ),
              ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: GisPalette.of(context).goldTint, borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.photo_library, color: GisPalette.of(context).goldText, size: 19),
                ),
                title: const Text('Gallery'),
                onTap: () {
                  Navigator.of(context).pop(); // Close the dialog
                  _getImage(ImageSource.gallery); // Get image from gallery
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _getImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(
      source: source,
      preferredCameraDevice: CameraDevice.front, // selfie for face match
      imageQuality: 80, // You can adjust quality
      maxWidth: 800, // You can resize the image to save space
    );

    if (pickedFile != null) {
      setState(() {
        _newProfileImage = File(pickedFile.path);
      });
    }
  }


  Future<void> _toggleBiometrics(bool value) async {
    if (value) {
      // Enabling biometrics
      try {
        // First check if device has biometrics available
        final isAvailable = await _localAuth.canCheckBiometrics;
        if (!isAvailable) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No biometrics enrolled on this device. Please set up fingerprint or Face ID in your device settings first.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          setState(() => _biometricsEnabled = false);
          return;
        }

        // Authenticate to enable
        final didAuthenticate = await _localAuth.authenticate(
          localizedReason: 'Please authenticate to enable biometric login',
          options: const AuthenticationOptions(
            biometricOnly: true,
            stickyAuth: true,
          ),
        );

        if (didAuthenticate) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('biometrics_enabled', true);

          final user = await _attendanceService.getMyProfile();
          // Must be the same identifier AuthService.login() writes as the
          // biometric owner (the login officer_id/username) — home_screen's
          // _canUseBiometrics() checks isBiometricOwner(_profile['username']),
          // so storing the internal 'id' (uuid) here instead would silently
          // make that check fail and hide "Use Biometrics" again right after
          // the user just turned it on.
          final username = user?['username']?.toString();
          if (username != null) {
            await _authService.enableBiometrics(username);
            // Save credentials for biometric login
            // You'll need to have password stored or prompt for it
            await _promptAndSavePassword(username);
          }

          if (mounted) {
            setState(() => _biometricsEnabled = true);
            NotificationService.logActivity(
              'Biometric login enabled',
              'Biometric sign-in was turned on for this device.',
              category: 'Security',
            );
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Biometric login enabled successfully!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          if (mounted) {
            setState(() => _biometricsEnabled = false);
          }
        }
      } catch (e) {
        print("Error enabling biometrics: $e");
        if (mounted) {
          setState(() => _biometricsEnabled = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error enabling biometrics: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else {
      // Disabling biometrics
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('biometrics_enabled', false);
      await _authService.clearStoredCredentials();

      if (mounted) {
        setState(() => _biometricsEnabled = false);
        NotificationService.logActivity(
          'Biometric login disabled',
          'Biometric sign-in was turned off and saved credentials cleared.',
          category: 'Security',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Biometric login disabled'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

// Add this helper method to prompt for password when enabling biometrics
//
  Future<void> _promptAndSavePassword(String username) async {
    final passwordController = TextEditingController();
    bool _obscurePassword = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Save Password for Biometrics', style: TextStyle(fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Please enter your password to enable biometric login:'),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: _obscurePassword,
                onChanged: (value) {
                  setState(() {}); // Rebuild to update button state
                },
                decoration: InputDecoration(
                  labelText: 'Password',
                  filled: true,
                  fillColor: GisPalette.of(context).bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600)),
            ),
            ElevatedButton(
              // Disable button if password is empty
              onPressed: passwordController.text.isNotEmpty
                  ? () => Navigator.pop(context, true)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: GisPalette.of(context).primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    passwordController.dispose();

    if (confirmed == true && passwordController.text.isNotEmpty) {
      await _authService.saveCredentials(
        username,
        passwordController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password saved for biometric login')),
        );
      }
    }
  }

  Future<void> _updateProfile(Map<String, dynamic> currentProfile) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // officerId (e.g. "P/012/2025") is what PATCH /api/officers matches
    // on — not currentProfile['id'], which is the internal row uuid and
    // isn't accepted by that route at all.
    final officerId = currentProfile['officerId']?.toString();

    if (officerId == null || officerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update profile. Officer ID not found.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Only send fields that actually changed from what was loaded.
    String? changedOrNull(String currentText, dynamic original) {
      final trimmed = currentText.trim();
      final originalText = (original ?? '').toString();
      return trimmed != originalText ? trimmed : null;
    }

    final fullName = changedOrNull(_fullNameController.text, currentProfile['fullName']);
    final email = changedOrNull(_emailController.text, currentProfile['email']);
    final department = changedOrNull(_departmentController.text, currentProfile['department']);
    final hasImageChange = _newProfileImage != null;
    final hasFieldChange = fullName != null || email != null || department != null;

    if (!hasImageChange && !hasFieldChange) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No changes to save.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    final successes = <String>[];
    final failures = <String>[];

    // Photo goes through POST /api/officers/register-face (not the
    // admin-gated PATCH /api/officers), so a regular officer can actually
    // save it. Do this first — it's the change most likely to succeed.
    if (hasImageChange) {
      final res = await _authService.registerFace(
        officerId: officerId,
        faceFile: _newProfileImage!,
      );
      if (res.ok) {
        successes.add('photo');
      } else {
        failures.add('photo — ${res.message}');
      }
    }

    if (hasFieldChange) {
      final result = await _authService.updateOfficerProfile(
        officerId: officerId,
        fullName: fullName,
        email: email,
        department: department,
      );
      if (result.success) {
        successes.add('profile details');
      } else {
        // PATCH /api/officers is admin-only server-side (see docs/API.md)
        // and this app has no admin login flow, so a regular officer's
        // field edits reliably 401 here — say that plainly.
        failures.add(result.isAdminGated
            ? 'profile details (needs an administrator)'
            : 'profile details${result.message != null ? " — ${result.message}" : ""}');
      }
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (failures.isEmpty) {
      NotificationService.logActivity(
        'Profile settings saved',
        'Officer $officerId updated ${successes.join(' and ')}.',
        category: 'System',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved ${successes.join(' and ')}.'),
          backgroundColor: Colors.green,
        ),
      );
      _retry();
      return;
    }

    final parts = <String>[
      if (successes.isNotEmpty) 'Saved ${successes.join(' and ')}.',
      'Couldn\'t save ${failures.join('; ')}.',
    ];
    if (successes.isNotEmpty) {
      NotificationService.logActivity(
        'Profile settings saved',
        'Officer $officerId updated ${successes.join(' and ')}.',
        category: 'System',
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(parts.join(' ')),
        backgroundColor: successes.isEmpty ? Colors.red : Colors.orange,
      ),
    );
    if (successes.isNotEmpty) _retry();
  }

  void _retry() {
    setState(() {
      _newProfileImage = null; // Clear picked image on retry
      _profileFuture = _fetchProfile();
    });
  }

  // ---------------------------------------------------------------------
  // Small presentational helpers (visual-only — no state, no side effects)
  // ---------------------------------------------------------------------

  InputDecoration _fieldDecoration(
      {required String label,
      required bool readOnly,
      IconData? prefix}) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: readOnly ? GisPalette.of(context).bg : Colors.white,
      labelStyle: TextStyle(color: GisPalette.of(context).muted),
      prefixIcon: prefix == null
          ? null
          : Icon(prefix,
              size: 19,
              color: readOnly ? GisPalette.of(context).muted : GisPalette.of(context).primary),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: readOnly ? Colors.transparent : GisPalette.of(context).hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: GisPalette.of(context).primary, width: 1.6),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: readOnly ? Colors.transparent : GisPalette.of(context).hairline),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: GisPalette.of(context).hairline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _cardEyebrow(String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: GisPalette.of(context).muted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GisPalette.of(context).bg,
      appBar: AppBar(
        title: Text(
          'Profile Settings',
          style: TextStyle(
              fontWeight: FontWeight.w800,
              color: GisPalette.of(context).ink,
              fontSize: 17),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        foregroundColor: GisPalette.of(context).ink,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: GisPalette.of(context).hairline),
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _profileFuture,
        builder: (context, snapshot) {
          // 1. Handle Loading State
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: GisPalette.of(context).primary, strokeWidth: 2.4),
                  SizedBox(height: 16),
                  Text(
                    'Loading profile...',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: GisPalette.of(context).muted),
                  ),
                ],
              ),
            );
          }

          // 2. Handle Error State
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline_rounded, color: GisPalette.of(context).danger, size: 36),
                    const SizedBox(height: 12),
                    Text('Failed to load profile: ${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: GisPalette.of(context).ink)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _retry,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: GisPalette.of(context).primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          // 3. Handle Success State
          final profile = snapshot.data!;
          return _buildSettingsForm(profile);
        },
      ),
    );
  }

  Widget _heroChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: GisPalette.of(context).gold),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsForm(Map<String, dynamic> profile) {
    // Determine if fields should be read-only based on whether they have existing values.
    // final bool isFullNameReadOnly = profile['name'] != null && (profile['name'] as String).isNotEmpty;
    final bool isEmailReadOnly = profile['email'] != null && (profile['email'] as String).isNotEmpty;

    // Field widgets built once, laid out as a 2-column grid on wide
    // screens and a single column on narrow ones.
    final officerIdField = TextFormField(
      controller: _usernameController,
      readOnly: true,
      decoration: _fieldDecoration(
          label: 'Officer ID',
          readOnly: true,
          prefix: Icons.badge_outlined),
    );
    final fullNameField = TextFormField(
      controller: _fullNameController,
      readOnly: isEmailReadOnly,
      decoration: _fieldDecoration(
          label: 'Full Name',
          readOnly: isEmailReadOnly,
          prefix: Icons.person_outline_rounded),
      validator: (value) =>
          (value == null || value.isEmpty) ? 'Please enter your full name' : null,
    );
    final emailField = TextFormField(
      controller: _emailController,
      readOnly: isEmailReadOnly,
      decoration: _fieldDecoration(
          label: 'Email',
          readOnly: isEmailReadOnly,
          prefix: Icons.mail_outline_rounded),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter your email';
        }
        if (!RegExp(r'\S+@\S+\.\S+').hasMatch(value)) {
          return 'Please enter a valid email address';
        }
        return null;
      },
    );
    final appIdField = TextFormField(
      controller: _idController,
      readOnly: isEmailReadOnly,
      decoration: _fieldDecoration(
          label: 'APP ID',
          readOnly: isEmailReadOnly,
          prefix: Icons.numbers_rounded),
      validator: (value) =>
          (value == null || value.isEmpty) ? 'Please enter your full name' : null,
    );
    final deptField = TextFormField(
      controller: _departmentController,
      readOnly: isEmailReadOnly,
      decoration: _fieldDecoration(
          label: 'Department',
          readOnly: isEmailReadOnly,
          prefix: Icons.apartment_rounded),
      validator: (value) =>
          (value == null || value.isEmpty) ? '' : null,
    );

    ImageProvider? buildProfileImage() {
      if (_newProfileImage != null) {
        return FileImage(_newProfileImage!);
      }

      final faceImage = profile['faceImageUrl'];
      // The real API (auth_service._flattenProfile) always returns this as
      // a plain Supabase Storage URL string — not a Buffer-shaped map.
      // NetworkImage was previously unreachable here, so a registered
      // face photo never actually rendered; only the default avatar did.
      if (faceImage is String && faceImage.isNotEmpty) {
        return NetworkImage(faceImage);
      }
      if (faceImage is Map && faceImage['type'] == 'Buffer' && faceImage['data'] is List) {
        final List<int> byteData = List<int>.from(faceImage['data']);
        final Uint8List bytes = Uint8List.fromList(byteData);
        return MemoryImage(bytes);
      }
      return const AssetImage('assets/default_avatar.png');
    }

    final displayName =
        (profile['fullName'] ?? profile['email'] ?? 'Officer').toString();
    final displayEmail = (profile['email'] ?? '').toString();
    final displayId = (profile['username'] ?? profile['officerId'] ?? '')
        .toString();
    final displayDept = (profile['department'] ?? '').toString();

    return AbsorbPointer(
      absorbing: _isSaving,
      child: Form(
        key: _formKey,
        child: Stack(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: ListView(
                  padding: const EdgeInsets.all(16.0),
                  children: [
                    // ---- Profile hero ----
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF2E4D2A),
                        Color(0xFF142412)
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: GisPalette.of(context).primary.withValues(alpha: 0.30),
                        blurRadius: 22,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: GisPalette.of(context).gold, width: 3),
                            ),
                            child: CircleAvatar(
                              radius: 56,
                              backgroundColor: Colors.white,
                              backgroundImage: buildProfileImage(),
                            ),
                          ),
                          Material(
                            color: GisPalette.of(context).gold,
                            shape: const CircleBorder(),
                            child: InkWell(
                              onTap: _showImageSourceDialog,
                              customBorder: const CircleBorder(),
                              child: const Padding(
                                padding: EdgeInsets.all(9.0),
                                child: Icon(Icons.camera_alt,
                                    color: Color(0xFF142412),
                                    size: 18),
                              ),
                            ),
                          )
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        displayName,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 19,
                          letterSpacing: -0.3,
                        ),
                      ),
                      if (displayEmail.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          displayEmail,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (displayId.isNotEmpty)
                            _heroChip(Icons.badge_outlined, displayId),
                          if (displayDept.isNotEmpty)
                            _heroChip(
                                Icons.apartment_rounded, displayDept),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        "Tap the camera icon to update your photo — it doubles as your face-verification image.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white60, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _cardEyebrow("Personal details"),
                      const SizedBox(height: 4),
                      Text(
                        "Fields locked by the system can't be edited here — ask an administrator.",
                        style:
                            TextStyle(fontSize: 12, color: GisPalette.of(context).muted),
                      ),
                      const SizedBox(height: 14),
                      officerIdField,
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (ctx, c) {
                          if (c.maxWidth < 560) {
                            return Column(
                              children: [
                                fullNameField,
                                const SizedBox(height: 14),
                                emailField,
                                const SizedBox(height: 14),
                                appIdField,
                                const SizedBox(height: 14),
                                deptField,
                              ],
                            );
                          }
                          return Column(
                            children: [
                              Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: fullNameField),
                                  const SizedBox(width: 12),
                                  Expanded(child: emailField),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: appIdField),
                                  const SizedBox(width: 12),
                                  Expanded(child: deptField),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 2),


                    ],
                  ),
                ),

                const SizedBox(height: 16),


                // ---- Two-factor authentication (email OTP, default OFF) ----
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _cardEyebrow("Two-factor authentication"),
                      const SizedBox(height: 6),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Enable Two-Factor Authentication',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: GisPalette.of(context).ink)),
                        subtitle: Text(
                          _twoFactorBusy
                              ? 'Sending code…'
                              : !_twoFactorAllowedByConfig
                                  ? 'Not enabled by administrator yet — ready once email is configured'
                                  : _twoFactorEnabled
                                      ? 'On — a code is emailed at each sign-in'
                                      : 'Off — get a 6-digit code by email at sign-in',
                          style: TextStyle(
                              color: GisPalette.of(context).muted, fontSize: 12.5),
                        ),
                        value: _twoFactorEnabled,
                        onChanged: _twoFactorBusy
                            ? null
                            : (v) => _toggleTwoFactor(v, profile),
                        activeThumbColor: GisPalette.of(context).primary,
                        secondary: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: _twoFactorEnabled
                                    ? GisPalette.of(context).oliveTint
                                    : GisPalette.of(context).bg,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.mark_email_read_outlined,
                                color: _twoFactorEnabled
                                    ? GisPalette.of(context).primary
                                    : Colors.grey,
                              ),
                            ),
                            if (_twoFactorBusy)
                              SizedBox(
                                width: 38,
                                height: 38,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: GisPalette.of(context).primary),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        'When on, signing in also requires a 6-digit code sent to your profile email (valid 5 minutes). An administrator turns the feature on in System Config once outbound email works.',
                        style: TextStyle(fontSize: 12, color: GisPalette.of(context).muted),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                if (_canCheckBiometrics)
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _cardEyebrow("Security"),
                        const SizedBox(height: 6),
                        SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Enable Biometric Login', style: TextStyle(fontWeight: FontWeight.w600, color: GisPalette.of(context).ink)),
                      subtitle: Text(
                        _biometricsEnabled
                            ? 'Fingerprint/Face ID'
                            : 'Enable to use fingerprint or face ID instead of password',
                        style: TextStyle(color: GisPalette.of(context).muted, fontSize: 12.5),
                      ),
                      value: _biometricsEnabled,
                      onChanged: _canCheckBiometrics ? _toggleBiometrics : null,
                      activeThumbColor: GisPalette.of(context).primary,
                      secondary: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: _biometricsEnabled ? GisPalette.of(context).oliveTint : GisPalette.of(context).bg,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.fingerprint,
                          color: _biometricsEnabled ? GisPalette.of(context).primary : Colors.grey,
                        ),
                      ),
                    ),
                      ],
                    ),
                  ),

                // ---- App updates (in-place, no reinstall) ----
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _cardEyebrow("App updates"),
                      const SizedBox(height: 6),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: GisPalette.of(context).oliveTint,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.system_update_outlined,
                            color: GisPalette.of(context).primary,
                          ),
                        ),
                        title: Text(
                          _currentVersion.isEmpty
                              ? 'GIS_Attendance'
                              : 'GIS_Attendance v$_currentVersion',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: GisPalette.of(context).ink),
                        ),
                        subtitle: Text(
                          'Updates install over this app — your data is kept, no uninstall needed.',
                          style:
                              TextStyle(color: GisPalette.of(context).muted, fontSize: 12.5),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _updateChecking
                            ? SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: GisPalette.of(context).primary),
                              )
                            : TextButton.icon(
                                onPressed: _manualUpdateCheck,
                                icon: const Icon(Icons.refresh, size: 17),
                                label:
                                    const Text('Check for updates'),
                              ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GisPalette.of(context).primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: () => _updateProfile(profile),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_outlined, size: 19),
                    label: Text(
                        _isSaving ? 'Saving…' : 'Save Changes',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                ),

                // _buildVersionHistorySection(),
                const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            if (_isSaving)
              Container(
                color: Colors.black.withValues(alpha: 0.5),
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }

}
