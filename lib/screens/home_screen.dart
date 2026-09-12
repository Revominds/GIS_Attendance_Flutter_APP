// HOME SCREEN

// ignore_for_file: unused_field

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:gis_attendance/screens/under_development_screen.dart';
import 'package:local_auth/local_auth.dart';
import 'package:gis_attendance/screens/settings_screen.dart';
import 'package:gis_attendance/services/attendance_service.dart';
import 'package:gis_attendance/services/auth_service.dart';
// import 'package:gis_attendance/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'attendance_history_screen.dart';
import 'login_screen.dart';
import 'package:camera/camera.dart';
import 'package:gis_attendance/screens/face_verification_screen.dart';
import 'package:gis_attendance/screens/notifications_screen.dart';
import 'package:gis_attendance/screens/admin/admin_home_screen.dart';
// import 'package:intl/intl.dart';


class HomeScreen extends StatefulWidget {

  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AttendanceService _attendanceService = AttendanceService();
  final AuthService _authService = AuthService();
  final LocalAuthentication _localAuth = LocalAuthentication();
  List<Map<String, dynamic>> _allBranchLocations = [];
  Timer? clockTimer;
  Timer? _inactivityTimer;
  bool _loading = false;
  bool _profileLoading = true;
  String? _status;
  Map<String, dynamic>? _profile;
  Map<String, double>? _lastLocation;
  bool _inGeoFence = false;
  bool _historyLoading = false;

  // GIS Theme Colors
  static const Color gisDeepOlive = Color(0xFF2E4D2A);
  static const Color gisDarkBackground = Color(0xFF142412);
  static const Color ghanaGold = Color(0xFFE1B12C);
  static const Color nationalRed = Color(0xFFD63031);
  static const Color successGreen = Color(0xFF2ED573);
  static const Color darkCharcoal = Color(0xFF1A2519);
  static const Color lightGrayBg = Color(0xFFF5F6F5);

  // Additional design tokens (visual-only, no behavioural impact)
  static const Color mutedText = Color(0xFF6E7A6C);
  static const Color hairline = Color(0xFFE7E9E4);
  static const Color goldTint = Color(0xFFFBF1D8);
  static const Color greenTint = Color(0xFFE1F9EC);
  static const Color redTint = Color(0xFFFBE6E6);

  List<Map<String, dynamic>> _history = [];
  int _historyPage = 0;
  static const int _historyPageSize = 20;
  bool _biometricAvailable = false;
  bool _isAdmin = false;
  String _currentTimeString = '';
  String _currentDateString = '';
  String _locationStatusMessage = "Checking location...";
  int? _matchedBranchId;
  String? _matchedBranchName;
  bool _isHomeBranch = false;

  @override
  void initState() {
    super.initState();
    _resetInactivityTimer();
    _loadInitialData(); // This handles everything in the right order
    clockTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      _updateTime();
    });
  }

  Future<void> _loadInitialData() async {
    await _loadAllBranchLocation();
    await _loadProfile();       // profile loads first ✅
    await _checkLocation();
    await _initBiometrics();    // now _profile is ready ✅
    await _checkAdmin();
  }

  Future<void> _checkAdmin() async {
    final admin = await _authService.isAdmin();
    if (!mounted) return;
    setState(() => _isAdmin = admin);
    print("Isadmin = $admin()");
  }

  Future<void> _loadAllBranchLocation() async {
    final AllBranchLocations = await _attendanceService.getAllBranchLocations();
    if (!mounted) return;
    setState(() {
      _allBranchLocations = AllBranchLocations;
    });
  }

  void _updateTime() {
    final now = DateTime.now();
    setState(() {
      _currentTimeString = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
      _currentDateString = "${now.day}/${now.month}/${now.year}";
    });
  }

  @override
  void dispose() {
    clockTimer?.cancel();
    _inactivityTimer?.cancel();
    super.dispose();
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(const Duration(minutes: 5), _logout);
  }

  Future<void> _loadProfile() async {
    setState(() => _profileLoading = true);
    final me = await _attendanceService.getMyProfile();
    if (!mounted) return;
    setState(() {
      _profile = me;
      _profileLoading = false;
    });
    await _loadHistory();
  }

  Future<void> _checkLocation() async {
    if (mounted) {
      setState(() {
        _locationStatusMessage = "Checking location...";
      });
    }

    try {
      final locationResponse = await _attendanceService.getCurrentLocation();

      if (!mounted) return;

      if (!locationResponse.success) {
        setState(() {
          _inGeoFence = false;
          _matchedBranchId = null;
          _matchedBranchName = null;
          _locationStatusMessage = locationResponse.message;
        });
        return;
      }

      final loc = locationResponse.location!;

      // Allowed distance/radius for attendance location
      num allowedMeters = await _attendanceService.GetAllowedDistance();

      bool isWithinLocation = false;

      // Check user location against registered attendance locations
      for (final location in _allBranchLocations) {
        final locationLat = (location["lat"] as num?)?.toDouble();
        final locationLng = (location["lng"] as num?)?.toDouble();

        if (locationLat == null || locationLng == null) continue;

        final distance = _attendanceService.distanceMeters(
          loc["lat"]!,
          loc["lng"]!,
          locationLat,
          locationLng,
        );

        if (distance <= allowedMeters) {
          isWithinLocation = true;
          break;
        }
      }

      setState(() {
        _lastLocation = loc;

        _inGeoFence = isWithinLocation;

        if (isWithinLocation) {
          _locationStatusMessage = "At Authorized Location";
        } else {
          _locationStatusMessage = "Not at Authorized Location";
        }

        // No branch assignment
        _matchedBranchId = null;
        _matchedBranchName = null;
      });

    } catch (e) {
      if (!mounted) return;

      setState(() {
        _inGeoFence = false;
        _matchedBranchId = null;
        _matchedBranchName = null;
        _locationStatusMessage = "Unable to verify location.";
      });

      debugPrint("🚨 Exception in _checkLocation: $e");
    }
  }

  Future<void> _initBiometrics() async {
    if (kIsWeb) {
      setState(() => _biometricAvailable = false);
      return;
    }

    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final supported = await _localAuth.isDeviceSupported();
      final prefs = await SharedPreferences.getInstance();
      final userEnabled = prefs.getBool('biometrics_enabled') ?? false;
      final username = _profile?['username']?.toString();
      final isOwner = username != null ? await _authService.isBiometricOwner(username) : false;
      final hasCredentials = await _authService.hasStoredCredentials();

      if (!mounted) return;
      setState(() {
        _biometricAvailable = canCheck && supported && userEnabled && isOwner && hasCredentials;
      });

      print("Biometric status - canCheck: $canCheck, supported: $supported, enabled: $userEnabled, isOwner: $isOwner, hasCreds: $hasCredentials");
    } catch (e) {
      print("Error in _initBiometrics: $e");
      if (!mounted) return;
      setState(() => _biometricAvailable = false);
    }
  }

  Future<bool> _canUseBiometrics() async {
    final username = _profile?['username']?.toString() ?? null;
    if (username == null) return false;

    return await _authService.canUseBiometrics(username);
  }

  Future<void> _onClockInPressed() async {
    setState(() => _loading = true);  // ← Add this immediately

    try {
      await _checkLocation();

      if (!_inGeoFence) {
        _showSnack('You must be within your registered branch to clock in.', ok: false);
        setState(() => _loading = false);  // ← Reset before returning
        return;
      }

      // final faceImageUrl = _profile?['faceImageUrl'];
      final canUseBio = await _canUseBiometrics();

      if (canUseBio) {
        final choice = await _showVerificationChoiceDialog(hasFaceImage: true);
        if (choice == null) {
          setState(() => _loading = false);  // ← Reset if user cancels
          return;
        }

        if (choice == 'biometric') {
          await _clockInWithBiometric();
        } else {
          await _clockInWithFace();
        }
      } else {
        await _clockInWithFace();
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);  // ← Ensure it's always reset
      }
    }
  }

  Future<void> _onClockOutPressed() async {
    setState(() => _loading = true);  // ← Add at start

    try {
      await _checkLocation();

      if (!_inGeoFence) {
        _showSnack('You must be within an GIS registered branch to clock out.',
            ok: false);
        return;
      }

      final canUseBio = await _canUseBiometrics();

      if (canUseBio) {
        final choice = await _showClockOutVerificationChoiceDialog(
            hasFaceImage: true);
        if (choice == null) return;

        if (choice == 'biometric') {
          await _clockOutWithBiometric();
        } else {
          await _clockOutWithFace();
        }
      } else {
        await _clockOutWithFace();
      }
    }finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<String?> _showVerificationChoiceDialog({required bool hasFaceImage}) {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titlePadding: const EdgeInsets.fromLTRB(24, 26, 24, 8),
        contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        title: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: greenTint,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.verified_user_rounded, color: gisDeepOlive, size: 30),
            ),
            const SizedBox(height: 14),
            const Text(
              "Verify Your Identity",
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: darkCharcoal),
            ),
            const SizedBox(height: 4),
            const Text(
              "Clocking in",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: mutedText, letterSpacing: 0.4),
            ),
          ],
        ),
        content: const Text(
          "Choose how you'd like to verify your identity to clock in.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: mutedText),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 22),
        actionsOverflowButtonSpacing: 10,
        actions: [
          // Biometric option
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.fingerprint, color: Colors.white),
              label: const Text(
                "Use Biometrics",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: gisDeepOlive,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () => Navigator.pop(context, 'biometric'),
            ),
          ),
          const SizedBox(height: 10),
          // Face verification option
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.face_retouching_natural),
              label: const Text("Use Face Verification", style: TextStyle(fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: hasFaceImage ? gisDeepOlive : Colors.grey.shade400, width: 1.4),
                foregroundColor: hasFaceImage ? gisDeepOlive : Colors.grey,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              // Disable face option if no face image is set up
              onPressed: hasFaceImage
                  ? () => Navigator.pop(context, 'face')
                  : () {
                Navigator.pop(context);
                _showSnack(
                  'Face verification not set up. Go to Settings to add your face image.',
                  ok: false,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _clockInWithBiometric() async {
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate to clock in',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (!authenticated) {
        _showSnack('Biometric authentication failed.', ok: false);
        return;
      }

      await _handleLateClockIn();
      setState(() => _status = "USER IS CLOCKED IN SUCCESSFULLY!");

    } catch (e) {
      _showSnack('Biometric error: $e', ok: false);
    }
  }

  Future<void> _clockInWithFace() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _showSnack('No camera found on this device', ok: false);
        return;
      }

      final frontCamera = cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      if (!mounted) return;

      final userId = (_profile?['officerId'] ??
              _profile?['username'] ??
              _profile?['id'] ??
              '')
          .toString();
      if (userId.isEmpty) {
        _showSnack('Profile not loaded — pull to refresh and try again.', ok: false);
        return;
      }

      // 1:1 verification against this officer's registered face. Only on a
      // match do we run the real clock-in.
      final verified = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => FaceVerificationScreen(
            camera: frontCamera,
            userId: userId,
          ),
        ),
      );

      if (verified == true) {
        await _handleLateClockIn();
        if (mounted) setState(() => _status = "USER IS CLOCKED IN SUCCESSFULLY!");
      } else {
        _showSnack('Face not verified — clock in cancelled.', ok: false);
      }
    } on CameraException catch (e) {
      _showSnack('Camera error: ${e.description}', ok: false);
    } catch (e) {
      _showSnack('Clock-in failed: $e', ok: false);
    }
  }

  Future<void> _clockOutWithBiometric() async {
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate to clock out',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (!authenticated) {
        _showSnack('Biometric authentication failed.', ok: false);
        return;
      }

      await handleEarlyClockOut();
      setState(() {
        _loading = false;
        _status = "USER IS CLOCKED OUT SUCCESSFULLY!";
      });

    } catch (e) {
      _showSnack('Biometric error: $e', ok: false);
    }
  }

  Future<void> _clockOutWithFace() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _showSnack('No camera found on this device', ok: false);
        return;
      }

      final frontCamera = cameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      if (!mounted) return;

      final userId = (_profile?['officerId'] ??
              _profile?['username'] ??
              _profile?['id'] ??
              '')
          .toString();
      if (userId.isEmpty) {
        _showSnack('Profile not loaded — pull to refresh and try again.', ok: false);
        return;
      }

      final verified = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (context) => FaceVerificationScreen(
            camera: frontCamera,
            userId: userId,
          ),
        ),
      );

      if (verified == true) {
        await handleEarlyClockOut();
        if (mounted) {
          setState(() {
            _loading = false;
            _status = "USER IS CLOCKED OUT SUCCESSFULLY!";
          });
        }
      } else {
        _showSnack('Face not verified — clock out cancelled.', ok: false);
      }
    } on CameraException catch (e) {
      _showSnack('Camera error: ${e.description}', ok: false);
    } catch (e) {
      _showSnack('Error during face verification: $e', ok: false);
    }
  }

  Future<String?> _showClockOutVerificationChoiceDialog({required bool hasFaceImage}) {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titlePadding: const EdgeInsets.fromLTRB(24, 26, 24, 8),
        contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        title: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: redTint,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.verified_user_rounded, color: nationalRed, size: 30),
            ),
            const SizedBox(height: 14),
            const Text(
              "Verify Your Identity",
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: darkCharcoal),
            ),
            const SizedBox(height: 4),
            const Text(
              "Clocking out",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: mutedText, letterSpacing: 0.4),
            ),
          ],
        ),
        content: const Text(
          "Choose how you'd like to verify your identity to clock out.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: mutedText),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 22),
        actionsOverflowButtonSpacing: 10,
        actions: [
          // Biometric option
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.fingerprint, color: Colors.white),
              label: const Text(
                "Use Biometrics",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: nationalRed,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () => Navigator.pop(context, 'biometric'),
            ),
          ),
          const SizedBox(height: 10),
          // Face verification option
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.face_retouching_natural),
              label: const Text("Use Face Verification", style: TextStyle(fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: hasFaceImage ? nationalRed : Colors.grey.shade400, width: 1.4),
                foregroundColor: hasFaceImage ? nationalRed : Colors.grey,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: hasFaceImage
                  ? () => Navigator.pop(context, 'face')
                  : () {
                Navigator.pop(context);
                _showSnack(
                  'Face verification not set up. Go to Settings to add your face image.',
                  ok: false,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadHistory() async {
    // Every attendance route keys rows by the business officer_id (e.g.
    // "P/012/2025"), not _profile['id'] (the officers table's internal
    // uuid) — using the uuid here would silently return zero rows for an
    // officer whose attendance was written under their real officer_id
    // (which is every face-based clock-in/out, see checkFace()).
    final userId = _profile?["officerId"]?.toString() ?? _profile?["username"]?.toString();
    if (userId == null) return;
    setState(() => _historyLoading = true);
    final items = await _attendanceService.getHistory(userId: userId);
    if (!mounted) return;
    setState(() {
      _history = items;
      _historyLoading = false;
      _historyPage = 0;
    });
  }

  Future<void> _handleLateClockIn() async {
    final now = DateTime.now();
    final cutoffTime = DateTime(now.year, now.month, now.day, 08, 30);

    if (now.isAfter(cutoffTime)) {
      final comment = await _showLateCommentDialog();
      if (comment == null) return;

      await _checkIn(comment: comment.isEmpty ? null : comment);
    } else {
      await _checkIn();
    }
  }

  Future<String?> _showLateCommentDialog() {
    final controller = TextEditingController();

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: const [
              Icon(Icons.schedule_rounded, color: ghanaGold),
              SizedBox(width: 10),
              Text("You are late", style: TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: "Enter reason for being late",
              filled: true,
              fillColor: lightGrayBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            maxLines: 3,
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: gisDeepOlive,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () {
                  Navigator.pop(context, "LATE CLOCK IN: ${controller.text.trim()}");
                },
                child: const Text("Submit", style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> handleEarlyClockOut() async {
    final now = DateTime.now();
    final clockOutCutoff = DateTime(now.year, now.month, now.day, 17, 0);
    if (now.isBefore(clockOutCutoff)) {
      // It's after 5 PM - Ask why they stayed late
      final comment = await _showEarlyClockOutComment();
      if (comment == null) return;
      await _checkOut(comment: comment);
    } else {
      // It's before 5 PM - Normal exit
      await _checkOut();
    }
  }

  Future<String?> _showEarlyClockOutComment() {
    final controller = TextEditingController();

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: const [
              Icon(Icons.exit_to_app_rounded, color: nationalRed),
              SizedBox(width: 10),
              Text("You are leaving earlier", style: TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: "Enter reason for leaving earlier",
              filled: true,
              fillColor: lightGrayBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            maxLines: 3,
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: gisDeepOlive,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () {
                  Navigator.pop(context, "EARLY CLOCK OUT: ${controller.text.trim()}");
                },
                child: const Text("Submit", style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        );
      },
    );
  }

// Updated _checkIn and _checkOut methods for the new API

  Future<void> _checkIn({String? comment}) async {
    setState(() {
      _loading = true;
      _status = null;
    });

    // Backend attendance rows are keyed by the business officer_id, not
    // the internal officers-table uuid (_profile['id']) — see _loadHistory.
    final userId = _profile?["officerId"]?.toString() ?? _profile?["username"]?.toString();
    if (userId == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = "No user available for clock in";
      });
      _showSnack(_status!, ok: false);
      return;
    }

    // Call the attendance service
    final result = await _attendanceService.clockIn(
      userId: userId,
      comment: comment,
    );

    if (!mounted) return;

    // Show notification
    _showSnack(result.message, ok: result.ok);

    // final DateTime now = DateTime.now();
    // String formattedTime = DateFormat('hh:mm a').format(now);
    // String formattedDate = DateFormat('MMM d, yyyy').format(now);

    // ✅ Save to local logs
    // await NotificationService.saveLocalLog(
    //   title: "Clock In Successful",
    //   message: "You have clocked in successfully.\nTime: $formattedTime\nDate: $formattedDate",
    // );

    // ✅ On success, just refresh history
    if (result.ok) {
      await _loadHistory();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = "Clocked in successfully";
      });
    } else {
      // ❌ On error, show the error message
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = result.message;
      });
    }
  }

  Future<void> _checkOut({String? comment}) async {
    setState(() {
      _loading = true;
      _status = null;
    });

    // Same officer_id-vs-internal-uuid distinction as _checkIn above.
    final userId = _profile?["officerId"]?.toString() ?? _profile?["username"]?.toString();
    if (userId == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = "No user available for clock out";
      });
      _showSnack(_status!, ok: false);
      return;
    }

    // ✅ Call the attendance service with just userId
    // Backend will find the open attendance for today automatically
    final result = await _attendanceService.clockOut(
      userId: userId,  // ✅ Changed from attendanceId
      comment: comment,
    );

    if (!mounted) return;

    // Show notification
    _showSnack(result.message, ok: result.ok);

    // final DateTime now = DateTime.now();
    // String formattedTime = DateFormat('hh:mm a').format(now);
    // String formattedDate = DateFormat('MMM d, yyyy').format(now);

    // ✅ On success, refresh history and update UI
    if (result.ok) {
      await _loadHistory();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = "Clocked out successfully";
      });
      // await NotificationService.saveLocalLog(
      //   title: "Clock Out Successful",
      //   message: "You have clocked out successfully.\nTime: $formattedTime\nDate: $formattedDate",
      // );
    } else {
      // ❌ On error, show the error message (e.g., "No open attendance")
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = result.message;
      });
    }
  }

  void _showSnack(String msg, {bool ok = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: ok ? Colors.green : Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(14),
      ),
    );
  }

  Future<void> _logout() async {
    clockTimer?.cancel();
    _inactivityTimer?.cancel();
    await _authService.logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
      );
    }
  }

  Future<void> _logoutPressed() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Logout", style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text("Are you sure you want to logout?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false), // Cancel
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true), // Confirm
            child: const Text("Logout", style: TextStyle(color: nationalRed, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _logout();
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good morning';
    }
    if (hour < 17) {
      return 'Good afternoon';
    }
    return 'Good evening';
  }

  // ---------------------------------------------------------------------
  // Small presentational helpers (visual-only — no state, no side effects)
  // ---------------------------------------------------------------------

  Widget _sectionCard({required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [gisDeepOlive, gisDarkBackground],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: gisDeepOlive.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _iconBadge(IconData icon, {required Color fg, required Color bg, double size = 40}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(icon, color: fg, size: size * 0.5),
    );
  }

  Widget _perforatedDivider() {
    return SizedBox(
      height: 1,
      child: Row(
        children: List.generate(36, (i) {
          return Expanded(
            child: Container(
              height: 1.4,
              color: i.isEven ? Colors.white.withValues(alpha: 0.28) : Colors.transparent,
            ),
          );
        }),
      ),
    );
  }

  Widget _sectionEyebrow(String text, {Color color = mutedText}) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: color,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isProfileReady = !_profileLoading && _profile != null;

    final name = isProfileReady ? (_profile!["fullName"] ?? _profile!["email"]) : "GIS Staff";
    final email = isProfileReady ? (_profile!["email"] ?? "----") : "----";
    final firstName = name.split(' ').first;
    final greeting = _getGreeting();
    final initials = name.isNotEmpty ? name[0].toUpperCase() : "A";
    final username = isProfileReady ? (_profile!["username"] ?? "----") : "----";
    final department = isProfileReady ? (_profile!["department"] ?? _profile!["branch"] ?? "----") : "----";
    final role = isProfileReady ? (_profile!["role"] ?? "STAFF") : "STAFF";
    final faceImage = isProfileReady ? _profile!["faceImage"] : null;

    final bool branchMissing = _profile != null &&
        (_profile!['department'] == null || _profile!['department'].toString().isEmpty);
    final Color locationColor = branchMissing ? nationalRed : (_inGeoFence ? successGreen : ghanaGold);
    final Color locationTint = branchMissing ? redTint : (_inGeoFence ? greenTint : goldTint);
    final IconData locationIcon = branchMissing
        ? Icons.error_outline_rounded
        : (_inGeoFence ? Icons.check_circle_rounded : Icons.warning_amber_rounded);
    final String locationText = branchMissing
        ? "⚠️ Profile Error: No Branch Assigned"
        : (_locationStatusMessage.isEmpty ? "⚠️ Profile Error: No Home Branch Assigned" : _locationStatusMessage);

    return GestureDetector(
      onTap: _resetInactivityTimer,
      onPanDown: (_) => _resetInactivityTimer(),
      onScaleStart: (_) => _resetInactivityTimer(),
      child: Scaffold(
        backgroundColor: lightGrayBg,
        appBar: AppBar(
          titleSpacing: 4,
          title: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: ghanaGold,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.security_rounded, color: gisDarkBackground, size: 19),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  "Ghana Immigration Attendance System - Kotoka Terminal 1",
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, height: 1.2),
                ),
              ),
            ],
          ),
          centerTitle: false,
          backgroundColor: gisDeepOlive,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.notifications_rounded, color: ghanaGold, size: 24),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const NotificationsScreen()),
                );
              },
            ),
            IconButton(
              onPressed: _logoutPressed,
              icon: const Icon(Icons.logout_rounded, color: ghanaGold, size: 22),
            ),
            const SizedBox(width: 4),
          ],
        ),

        drawer: Drawer(
          backgroundColor: Colors.white,
          child: ListView(
            padding: EdgeInsets.zero,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.fromLTRB(20, 60, 20, 22),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [gisDarkBackground, gisDeepOlive],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: ghanaGold, width: 2),
                      ),
                      child: CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.white,
                        backgroundImage: (isProfileReady && faceImage != null)
                            ? NetworkImage(faceImage)
                            : null,
                        child: (!isProfileReady || faceImage == null)
                            ? Text(
                          initials,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                            color: gisDeepOlive,
                          ),
                        )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _DrawerTile(
                icon: Icons.home_outlined,
                label: 'Dashboard',
                onTap: () => Navigator.pop(context),
              ),
              _DrawerTile(
                icon: Icons.settings_outlined,
                label: 'Settings',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SettingsScreen()),
                  ).then((_) => _initBiometrics()); // ✅ re-check when user returns
                },
              ),
              _DrawerTile(
                icon: Icons.apps_outlined,
                label: 'Other pages',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const UnderDevelopmentScreen()),
                  ).then((_) => _initBiometrics()); // ✅ re-check when user returns
                },
              ),
              _DrawerTile(
                icon: Icons.history_rounded,
                label: 'Attendance History',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => AttendanceHistoryScreen(profile: _profile, attendanceService: _attendanceService),),
                  );
                },
              ),
              _DrawerTile(
                icon: Icons.admin_panel_settings_rounded,
                label: 'Admin',
                iconColor: ghanaGold,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AdminHomeScreen()),
                  );
                },
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Divider(height: 1, color: hairline),
              ),
              _DrawerTile(
                icon: Icons.logout_rounded,
                label: 'Logout',
                iconColor: nationalRed,
                labelColor: nationalRed,
                onTap: _logoutPressed,
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),

        body: RefreshIndicator(
          color: gisDeepOlive,
          onRefresh: () async {
            await _loadProfile();
            await _checkLocation();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ///Greeting////
                _sectionEyebrow("Staff dashboard"),
                const SizedBox(height: 6),
                Text(
                  '$greeting, $firstName',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: darkCharcoal,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 18),

                //////////////////////// ID / profile card /////////////////////////////
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [gisDarkBackground, gisDeepOlive],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: gisDeepOlive.withValues(alpha: 0.28),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      // corner accent ribbon
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: ghanaGold,
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(22),
                              bottomLeft: Radius.circular(16),
                            ),
                          ),
                          child: Text(
                            role.toString().toUpperCase(),
                            style: const TextStyle(
                              color: gisDarkBackground,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: ghanaGold, width: 2),
                              ),
                              child: CircleAvatar(
                                radius: 30,
                                backgroundColor: Colors.white,
                                backgroundImage: (isProfileReady && faceImage != null)
                                    ? NetworkImage(faceImage)
                                    : null,
                                child: (!isProfileReady || faceImage == null)
                                    ? Text(
                                  initials,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 22,
                                    color: gisDeepOlive,
                                  ),
                                )
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: isProfileReady
                                  ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 17)),
                                  const SizedBox(height: 8),

                                  Text(email,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w400,
                                          fontSize: 17)),

                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 14,
                                    runSpacing: 6,
                                    children: [
                                      _idMeta(Icons.badge_outlined, "$username"),
                                      _idMeta(Icons.apartment_rounded, "$department"),
                                    ],
                                  ),
                                ],
                              )
                                  : const Text(
                                "Loading user...",
                                style: TextStyle(color: Colors.white, fontSize: 14),
                              ),
                            ),
                            InkWell(
                              onTap: _loadProfile,
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                /////////////////////// location card //////////////////////////
                _sectionCard(
                  child: Row(
                    children: [
                      _iconBadge(locationIcon, fg: locationColor, bg: locationTint, size: 44),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionEyebrow("Location status", color: Colors.white70),
                            const SizedBox(height: 4),
                            Text(
                              locationText,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                                color: locationColor,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              _lastLocation != null
                                  ? "Lat ${_lastLocation!["lat"]!.toStringAsFixed(5)}   ·   Lng ${_lastLocation!["lng"]!.toStringAsFixed(5)}"
                                  : "No location yet",
                              style: const TextStyle(fontSize: 11.5, color: Colors.white60),
                            ),
                          ],
                        ),
                      ),
                      InkWell(
                        onTap: _checkLocation,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), shape: BoxShape.circle),
                          child: const Icon(Icons.my_location_rounded, size: 19, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                ////////////////////// clock in/out — "boarding pass" panel /////////////////////////////////
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: gisDarkBackground,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                        child: Column(
                          children: [
                            _sectionEyebrow("Today · $_currentDateString"),
                            const SizedBox(height: 8),
                            Text(
                              _currentTimeString,
                              style: const TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 1.2,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
                      _perforatedDivider(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
                        child: Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: (_loading) ? null : _onClockInPressed,
                                icon: const Icon(Icons.login_rounded, color: Colors.white, size: 20),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: successGreen,
                                  disabledBackgroundColor: successGreen.withValues(alpha: 0.4),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 15),
                                ),
                                label: const Text(
                                  "Clock In",
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: (_loading) ? null : _onClockOutPressed,
                                icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 20),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: nationalRed,
                                  disabledBackgroundColor: nationalRed.withValues(alpha: 0.4),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 15),
                                ),
                                label: const Text(
                                  "Clock Out",
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                                ),
                              ),
                            ),
                            if (_loading) ...[
                              const SizedBox(height: 16),
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: ghanaGold),
                              ),
                            ],
                            if (_status != null) ...[
                              const SizedBox(height: 14),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.check_circle_rounded, color: successGreen, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _status!,
                                        style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                /////////////////////// attendance history//////////////////////
                _sectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _iconBadge(Icons.calendar_today_rounded, fg: gisDeepOlive, bg: goldTint, size: 34),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              "Attendance History",
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white),
                            ),
                          ),
                          InkWell(
                            onTap: _historyLoading ? null : _loadHistory,
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), shape: BoxShape.circle),
                              child: const Icon(Icons.refresh_rounded, size: 18, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (_historyLoading)
                        const Center(child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: CircularProgressIndicator(strokeWidth: 2, color: ghanaGold),
                        ))
                      else if (_history.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 22),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Column(
                            children: [
                              Icon(Icons.inbox_outlined, color: Colors.white70, size: 26),
                              SizedBox(height: 8),
                              Text(
                                "No attendance records",
                                style: TextStyle(color: Colors.white70, fontSize: 12.5),
                              ),
                            ],
                          ),
                        )
                      else
                        Builder(builder: (context) {
                          final total = _history.length;
                          final totalPages = (total + _historyPageSize - 1) ~/ _historyPageSize;
                          final currentPage = _historyPage.clamp(0, totalPages == 0 ? 0 : totalPages - 1);
                          final start = currentPage * _historyPageSize;
                          final endExclusive = (start + _historyPageSize) > total ? total : (start + _historyPageSize);
                          final pageSlice = _history.sublist(start, endExclusive);

                          return Column(
                            children: [
                              // header row
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Row(
                                  children: const [
                                    Expanded(flex: 3, child: Text("Date", style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w700))),
                                    Expanded(flex: 2, child: Text("In", style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w700))),
                                    Expanded(flex: 2, child: Text("Out", style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w700))),
                                    Expanded(flex: 3, child: Text("Hours", style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w700))),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              ...pageSlice.asMap().entries.map((e) => _HistoryRow(record: e.value, alt: e.key.isOdd)).toList(),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Text(
                                    "Showing ${total == 0 ? 0 : start + 1}-${endExclusive} of ${total}",
                                    style: const TextStyle(fontSize: 11.5, color: Colors.white60),
                                  ),
                                  const Spacer(),
                                  InkWell(
                                    onTap: currentPage > 0
                                        ? () {
                                      setState(() {
                                        _historyPage = currentPage - 1;
                                      });
                                    }
                                        : null,
                                    borderRadius: BorderRadius.circular(16),
                                    child: Container(
                                      padding: const EdgeInsets.all(5),
                                      decoration: BoxDecoration(
                                        color: currentPage > 0 ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(Icons.chevron_left_rounded, size: 20, color: currentPage > 0 ? Colors.white : Colors.white24),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text("${currentPage + 1} / ${totalPages == 0 ? 1 : totalPages}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                                  const SizedBox(width: 6),
                                  InkWell(
                                    onTap: (currentPage + 1) < totalPages
                                        ? () {
                                      setState(() {
                                        _historyPage = currentPage + 1;
                                      });
                                    }
                                        : null,
                                    borderRadius: BorderRadius.circular(16),
                                    child: Container(
                                      padding: const EdgeInsets.all(5),
                                      decoration: BoxDecoration(
                                        color: (currentPage + 1) < totalPages ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(Icons.chevron_right_rounded, size: 20, color: (currentPage + 1) < totalPages ? Colors.white : Colors.white24),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => AttendanceHistoryScreen(
                                          profile: _profile,
                                          attendanceService: _attendanceService,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.history_rounded, size: 18, color: ghanaGold),
                                  label: const Text("View Full History", style: TextStyle(fontWeight: FontWeight.w700, color: ghanaGold)),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 13),
                                    side: const BorderSide(color: ghanaGold, width: 1.4),
                                    foregroundColor: ghanaGold,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }),
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

  Widget _idMeta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.white70),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(color: Colors.white70, fontSize: 12.5),
        ),
      ],
    );
  }
}

class _DrawerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? labelColor;

  const _DrawerTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: (iconColor ?? _HomeScreenState.gisDeepOlive).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor ?? _HomeScreenState.gisDeepOlive, size: 19),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: labelColor ?? _HomeScreenState.darkCharcoal,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final Map<String, dynamic> record;
  final bool alt;
  const _HistoryRow({required this.record, this.alt = false});

  String _formatDate(String v) {
    try {
      final dt = DateTime.parse(v).toLocal();
      return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
    } catch (_) {
      return v;
    }
  }

  String _formatTime(String v) {
    try {
      final dt = DateTime.parse(v).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return "$h:$m";
    } catch (_) {
      return v;
    }
  }

  /// Backend sends duration in MINUTES via `duration_minutes`, and it can be
  /// null (e.g. still-open shifts). Falls back to computing the duration
  /// from check_in/check_out timestamps when duration_minutes is missing.
  String _formatTotalHours(dynamic durationMinutes, dynamic clockIn, dynamic clockOut) {
    num? minutes;

    if (durationMinutes != null) {
      minutes = num.tryParse(durationMinutes.toString());
    }

    if (minutes == null && clockIn is String && clockOut is String) {
      try {
        final inDt = DateTime.parse(clockIn);
        final outDt = DateTime.parse(clockOut);
        minutes = outDt.difference(inDt).inMinutes;
      } catch (_) {
        minutes = null;
      }
    }

    if (minutes == null) return "-";

    final totalMinutes = minutes.abs().round();
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    return "$hours hrs $mins mins";
  }

  @override
  Widget build(BuildContext context) {
    // Backend uses 'clock_in' and 'clock_out' directly
    final date = record['date'];
    final clockIn = record['clock_in'] ?? 
                    record['check_in_time'] ?? 
                    record['clock_in_time'] ?? 
                    record['clockIn'] ?? 
                    record['clockInTime'] ?? 
                    record['in'];
    
    final clockOut = record['clock_out'] ?? 
                    record['check_out_time'] ?? 
                    record['clock_out_time'] ?? 
                    record['clockOut'] ?? 
                    record['clockOutTime'] ?? 
                    record['out'];
    
    final durationMinutes = record['duration_minutes'] ?? 
                            record['total_hours'] ?? 
                            record['totalHours'] ?? 
                            record['total'];

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
      decoration: BoxDecoration(
        color: alt ? Colors.white.withValues(alpha: 0.06) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          // Date column - use 'date' field
          Expanded(
            flex: 3,
            child: Text(
              date != null ? _formatDate(date.toString()) : '-',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white),
            ),
          ),
          // Clock-in date (redundant with above, but keeping for layout)
          // Expanded(
          //   flex: 3,
          //   child: Text(
          //     clockIn != null ? _formatDate(clockIn.toString()) : '-',
          //     style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white),
          //   ),
          // ),
          // // Clock-in time
          Expanded(
            flex: 2,
            child: Text(
              clockIn != null ? _formatTime(clockIn.toString()) : '-',
              style: const TextStyle(fontSize: 12.5, color: _HomeScreenState.successGreen, fontWeight: FontWeight.w600),
            ),
          ),
          // Clock-out time
          Expanded(
            flex: 2,
            child: Text(
              clockOut != null ? _formatTime(clockOut.toString()) : '-',
              style: const TextStyle(fontSize: 12.5, color: _HomeScreenState.nationalRed, fontWeight: FontWeight.w600),
            ),
          ),
          // Total hours
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _HomeScreenState.goldTint,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _formatTotalHours(durationMinutes, clockIn, clockOut),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _HomeScreenState.gisDeepOlive),
              ),
            ),
          ),
        ],
      ),
    );
  }
}