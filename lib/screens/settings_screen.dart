//SETTINGS SCREEN

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gis_attendance/services/auth_service.dart';
import 'package:gis_attendance/services/attendance_service.dart';


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

  // GIS theme — matches the home & notifications screens for a consistent brand feel.
  static const Color gisDeepOlive = Color(0xFF2E4D2A);
  // static const Color gisDarkBackground = Color(0xFF142412);
  static const Color ghanaGold = Color(0xFFE1B12C);
  static const Color goldText = Color(0xFF8A6D1D);
  static const Color nationalRed = Color(0xFFD63031);
  static const Color darkCharcoal = Color(0xFF1A2519);
  static const Color lightGrayBg = Color(0xFFF5F6F5);
  static const Color mutedText = Color(0xFF6E7A6C);
  static const Color hairline = Color(0xFFE7E9E4);
  static const Color goldTint = Color(0xFFFBF1D8);
  static const Color oliveTint = Color(0xFFE3EAE1);

  bool _biometricsEnabled = true;
  bool _canCheckBiometrics = false;
  File? _profileImage;
  File? _newProfileImage;
  bool _isSaving = false;
  Uint8List? imageBytes;


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
    if (mounted) {
      setState(() {});
    }
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
                  decoration: BoxDecoration(color: oliveTint, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.camera_alt, color: gisDeepOlive, size: 19),
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
                  decoration: BoxDecoration(color: goldTint, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.photo_library, color: goldText, size: 19),
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
                  fillColor: lightGrayBg,
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
                backgroundColor: gisDeepOlive,
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

  InputDecoration _fieldDecoration({required String label, required bool readOnly}) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: readOnly ? lightGrayBg : Colors.white,
      labelStyle: const TextStyle(color: mutedText),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: readOnly ? Colors.transparent : hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: gisDeepOlive, width: 1.6),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: readOnly ? Colors.transparent : hairline),
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
        border: Border.all(color: hairline),
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
      style: const TextStyle(
        color: mutedText,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightGrayBg,
      appBar: AppBar(
        title: const Text(
          'Settings - Profile Update',
          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 16),
        ),
        centerTitle: true,
        backgroundColor: gisDeepOlive,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _profileFuture,
        builder: (context, snapshot) {
          // 1. Handle Loading State
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: gisDeepOlive, strokeWidth: 2.4),
                  SizedBox(height: 16),
                  Text(
                    'Loading profile...',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: mutedText),
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
                    const Icon(Icons.error_outline_rounded, color: nationalRed, size: 36),
                    const SizedBox(height: 12),
                    Text('Failed to load profile: ${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14, color: darkCharcoal)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _retry,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: gisDeepOlive,
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

  Widget _buildSettingsForm(Map<String, dynamic> profile) {
    // Determine if fields should be read-only based on whether they have existing values.
    // final bool isFullNameReadOnly = profile['name'] != null && (profile['name'] as String).isNotEmpty;
    final bool isEmailReadOnly = profile['email'] != null && (profile['email'] as String).isNotEmpty;

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

    return AbsorbPointer(
      absorbing: _isSaving,
      child: Form(
        key: _formKey,
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                Center(
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: ghanaGold, width: 3),
                        ),
                        child: CircleAvatar(
                          radius: 76,
                          backgroundColor: lightGrayBg,
                          backgroundImage: buildProfileImage(),
                        ),
                      ),
                      Material(
                        color: gisDeepOlive,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          onTap: _showImageSourceDialog,
                          borderRadius: BorderRadius.circular(20),
                          child: const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Icon(Icons.camera_alt, color: Colors.white, size: 20),
                          ),
                        ),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text("Tap the camera icon to update your photo",
                  style: TextStyle(color: mutedText, fontSize: 12.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _cardEyebrow("Profile information"),
                      const SizedBox(height: 14),
                      // Read-only Username
                      TextFormField(
                        controller: _usernameController,
                        readOnly: true,
                        decoration: _fieldDecoration(label: 'Officer ID', readOnly: true),
                      ),
                      const SizedBox(height: 14),

                      // Editable Full Name (only if empty)
                      TextFormField(
                        controller: _fullNameController,
                        readOnly: isEmailReadOnly, // Set readOnly based on initial value
                        decoration: _fieldDecoration(label: 'Full Name', readOnly: isEmailReadOnly),
                        validator: (value) => (value == null || value.isEmpty) ? 'Please enter your full name' : null,
                      ),
                      const SizedBox(height: 14),


                      TextFormField(
                        controller: _emailController,
                        readOnly: isEmailReadOnly, // Set readOnly based on initial value
                        decoration: _fieldDecoration(label: 'Email', readOnly: isEmailReadOnly),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your email';
                          }
                          // Basic email validation
                          if (!RegExp(r'\S+@\S+\.\S+').hasMatch(value)) {
                            return 'Please enter a valid email address';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      
                      TextFormField(
                        controller: _idController,
                        readOnly: isEmailReadOnly, // Set readOnly based on initial value
                        decoration: _fieldDecoration(label: 'APP ID', readOnly: isEmailReadOnly),
                        validator: (value) => (value == null || value.isEmpty) ? 'Please enter your full name' : null,
                      ),
                      const SizedBox(height: 14),

                      TextFormField(
                        controller: _departmentController,
                        readOnly: isEmailReadOnly, // Set readOnly based on initial value
                        decoration: _fieldDecoration(label: 'Department', readOnly: isEmailReadOnly),
                        validator: (value) => (value == null || value.isEmpty) ? '' : null,
                      ),
                      const SizedBox(height: 14),


                    ],
                  ),
                ),

                const SizedBox(height: 16),


                if (_canCheckBiometrics)
                  _card(
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enable Biometric Login', style: TextStyle(fontWeight: FontWeight.w600, color: darkCharcoal)),
                      subtitle: Text(
                        _biometricsEnabled
                            ? 'Fingerprint/Face ID'
                            : 'Enable to use fingerprint or face ID instead of password',
                        style: const TextStyle(color: mutedText, fontSize: 12.5),
                      ),
                      value: _biometricsEnabled,
                      onChanged: _canCheckBiometrics ? _toggleBiometrics : null,
                      activeThumbColor: gisDeepOlive,
                      secondary: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: _biometricsEnabled ? oliveTint : lightGrayBg,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.fingerprint,
                          color: _biometricsEnabled ? gisDeepOlive : Colors.grey,
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: gisDeepOlive,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: () => _updateProfile(profile),
                    child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                ),

                // _buildVersionHistorySection(),
                const SizedBox(height: 24),
              ],
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