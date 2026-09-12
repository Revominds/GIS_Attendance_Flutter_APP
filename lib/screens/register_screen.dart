// REGISTER SCREEN

import 'dart:io';

// ignore: unused_import
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gis_attendance/services/auth_service.dart';
import 'package:image_picker/image_picker.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  int _currentStep = 0; // 0: Officer ID, 1: Face Capture & Details, 2: Passwords

  final _step1Key = GlobalKey<FormState>();
  final _step3Key = GlobalKey<FormState>();
  final _idCtrl =  TextEditingController();
  final _staffIdCtrl = TextEditingController();
  final _fullNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _departmentCtrl = TextEditingController();
  final _positionCtrl = TextEditingController();
  final _phoneNumberCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  bool _loading = false;
  bool _fetchingDetails = false;
  String? _error;
  File? _faceFile;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  final AuthService _authService = AuthService();
  final ImagePicker _picker = ImagePicker();

  // GIS Theme Colors
  static const Color gisDeepOlive = Color(0xFF2E4D2A);
  static const Color gisDarkBackground = Color(0xFF142412);
  static const Color ghanaGold = Color(0xFFE1B12C);
  static const Color nationalRed = Color(0xFFD63031);
  static const Color lightGrayBg = Color(0xFFF5F6F5);

  @override
  void dispose() {
    _staffIdCtrl.dispose();
    _idCtrl.dispose();
    _fullNameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  // --- STEP 1: Fetch Officer Data by ID ---
  Future<void> _fetchOfficerData() async {
    if (!_step1Key.currentState!.validate()) return;

    setState(() {
      _fetchingDetails = true;
      _error = null;
    });

    try {
      // Look up by the ID the officer actually typed into the Step 1
      // field, which is bound to _staffIdCtrl (not _idCtrl — _idCtrl only
      // ever gets written to below, after a successful fetch, to hold the
      // record's internal id).
      final officerData = await _authService.getOfficerDetails(_staffIdCtrl.text.trim());

      if (!mounted) return;

      if (officerData != null) {
        _idCtrl.text = officerData['id'] ?? '';
        _fullNameCtrl.text = officerData['fullName'] ?? '';
        _emailCtrl.text = officerData['email'] ?? '';
        _departmentCtrl.text = officerData['department']?? '';

        setState(() {
          _fetchingDetails = false;
          _currentStep = 1; // Move to next step
        });
      } else {
        setState(() {
          _fetchingDetails = false;
          _error = "Officer ID not found in system record.";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _fetchingDetails = false;
          _error = "Failed to pull officer data. Please try again.";
        });
      }
    }
  }

  // --- STEP 2: Pick Face Image ---
  Future<void> _pickFace() async {
    final xfile = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 90,
    );
    if (xfile != null) {
      setState(() {
        _faceFile = File(xfile.path);
        _error = null;
      });
    }
  }

  void _proceedToStep3() {
    if (_faceFile == null) {
      setState(() {
        _error = "Face photo is required for registration.";
      });
      return;
    }
    setState(() {
      _error = null;
      _currentStep = 2;
    });
  }

  // --- STEP 3: Final Submit ---
  Future<void> _submitRegistration() async {
    if (!_step3Key.currentState!.validate()) return;

    if (_passwordCtrl.text.trim() != _confirmPasswordCtrl.text.trim()) {
      setState(() {
        _error = "Passwords do not match.";
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _authService.register(
        officerId: _staffIdCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text.trim(),
        department: _departmentCtrl.text.trim(),
        position: _positionCtrl.text.trim(),
        phoneNumber: _phoneNumberCtrl.text.trim(),
        fullName: _fullNameCtrl.text.trim(),
        faceFile: _faceFile!,
      );

      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      final ok = result["success"] == true;
      final message = result["message"]?.toString() ??
          (ok ? "Registration complete." : "Registration failed. Please try again.");

      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: gisDeepOlive,
            duration: const Duration(seconds: 4),
          ),
        );
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _error = message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = "An error occurred during registration.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: gisDarkBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (_currentStep > 0) {
              setState(() {
                _currentStep--;
                _error = null;
              });
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        title: const Text(
          "Officer Registration",
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [gisDarkBackground, gisDeepOlive],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              children: [
                // Step Indicator Bar
                _buildStepHeader(),
                const SizedBox(height: 24),

                // Card Wrapper
                Container(
                  padding: const EdgeInsets.all(24),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_error != null) _buildErrorBanner(),

                      // Active Step View
                      if (_currentStep == 0) _buildStep1OfficerId(),
                      if (_currentStep == 1) _buildStep2BiometricsAndData(),
                      if (_currentStep == 2) _buildStep3Password(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Section 1 UI: Fetch Officer Info ---
  Widget _buildStep1OfficerId() {
    return Form(
      key: _step1Key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Step 1: Verify Officer ID",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: gisDeepOlive,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Enter your Officer ID to fetch your record from the system.",
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),
          const Text(
            "Officer ID",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: gisDeepOlive,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _staffIdCtrl,
            enabled: !_fetchingDetails,
            keyboardType: TextInputType.text,
            style: const TextStyle(color: Colors.black87),
            decoration: InputDecoration(
              hintText: "e.g., GIS-88421",
              hintStyle: TextStyle(color: Colors.grey.shade400),
              prefixIcon: const Icon(Icons.badge_outlined, color: gisDeepOlive),
              filled: true,
              fillColor: lightGrayBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? "Officer ID is required"
                : null,
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _fetchingDetails ? null : _fetchOfficerData,
              style: ElevatedButton.styleFrom(
                backgroundColor: gisDeepOlive,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _fetchingDetails
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      "VERIFY & CONTINUE",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Section 2 UI: Biometrics & Pulled Details ---
  Widget _buildStep2BiometricsAndData() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Step 2: Biometric & Record Check",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: gisDeepOlive,
          ),
        ),
        const SizedBox(height: 20),

        // Display Pulled Data Cards
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: lightGrayBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: gisDeepOlive.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              _infoRow("Officer ID", _staffIdCtrl.text),
              const Divider(height: 16),
              _infoRow("Full Name", _fullNameCtrl.text),
              const Divider(height: 16),
              _infoRow("Email", _emailCtrl.text),
              const Divider(height: 16),
              _infoRow("Department", _departmentCtrl.text),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Face Capture Area
        Center(
          child: GestureDetector(
            onTap: _pickFace,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _faceFile != null ? ghanaGold : gisDeepOlive,
                      width: 3,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 46,
                    backgroundColor: lightGrayBg,
                    backgroundImage:
                        _faceFile != null ? FileImage(_faceFile!) : null,
                    child: _faceFile == null
                        ? const Icon(
                            Icons.camera_alt_rounded,
                            color: gisDeepOlive,
                            size: 34,
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _faceFile == null
                      ? "Tap to capture face ID"
                      : "Face photo captured ✔",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _faceFile == null ? gisDeepOlive : ghanaGold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _proceedToStep3,
            style: ElevatedButton.styleFrom(
              backgroundColor: gisDeepOlive,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              "NEXT: SET PASSWORD",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- Section 3 UI: Password Setup & Submit ---
  Widget _buildStep3Password() {
    return Form(
      key: _step3Key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Step 3: Account Credentials",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: gisDeepOlive,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Set up a password to complete your account registration.",
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),

          // Password Field
          const Text(
            "Password",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: gisDeepOlive,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _passwordCtrl,
            enabled: !_loading,
            obscureText: _obscurePassword,
            style: const TextStyle(color: Colors.black87),
            decoration: InputDecoration(
              hintText: "Enter password",
              prefixIcon: const Icon(Icons.lock_outline, color: gisDeepOlive),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: gisDeepOlive,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
              filled: true,
              fillColor: lightGrayBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return "Password is required";
              if (v.length < 6) return "Must be at least 6 characters";
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Confirm Password Field
          const Text(
            "Confirm Password",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: gisDeepOlive,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _confirmPasswordCtrl,
            enabled: !_loading,
            obscureText: _obscureConfirmPassword,
            style: const TextStyle(color: Colors.black87),
            decoration: InputDecoration(
              hintText: "Confirm password",
              prefixIcon: const Icon(Icons.lock_outline, color: gisDeepOlive),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility_off
                      : Icons.visibility,
                  color: gisDeepOlive,
                ),
                onPressed: () => setState(
                    () => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
              filled: true,
              fillColor: lightGrayBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            validator: (v) =>
                (v == null || v.isEmpty) ? "Please confirm password" : null,
          ),
          const SizedBox(height: 28),

          // Submit Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _submitRegistration,
              style: ElevatedButton.styleFrom(
                backgroundColor: gisDeepOlive,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      "COMPLETE REGISTRATION",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Helper Widgets ---
  Widget _buildStepHeader() {
    return Row(
      children: [
        _stepCircle(0, "1", "ID Check"),
        _stepDivider(0),
        _stepCircle(1, "2", "Face ID"),
        _stepDivider(1),
        _stepCircle(2, "3", "Security"),
      ],
    );
  }

  Widget _stepCircle(int stepIndex, String label, String title) {
    final isActive = _currentStep == stepIndex;
    final isDone = _currentStep > stepIndex;

    return Expanded(
      child: Column(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: isDone
                ? ghanaGold
                : isActive
                    ? Colors.white
                    : Colors.white24,
            child: isDone
                ? const Icon(Icons.check, size: 18, color: gisDarkBackground)
                : Text(
                    label,
                    style: TextStyle(
                      color: isActive ? gisDarkBackground : Colors.white70,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              color: isActive ? Colors.white : Colors.white60,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepDivider(int stepIndex) {
    final isDone = _currentStep > stepIndex;
    return Container(
      width: 30,
      height: 2,
      margin: const EdgeInsets.only(bottom: 18),
      color: isDone ? ghanaGold : Colors.white24,
    );
  }

  Widget _infoRow(String title, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        Flexible(
          child: Text(
            value.isEmpty ? "—" : value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: gisDarkBackground,
              fontSize: 13,
            ),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: nationalRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: nationalRed.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: nationalRed, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(color: nationalRed, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}