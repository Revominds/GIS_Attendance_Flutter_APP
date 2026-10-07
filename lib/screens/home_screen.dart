// HOME SCREEN

// ignore_for_file: unused_field

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:gis_attendance/screens/under_development_screen.dart';
import 'package:local_auth/local_auth.dart';
import 'package:gis_attendance/screens/settings_screen.dart';
import 'package:gis_attendance/services/attendance_service.dart';
import 'package:gis_attendance/services/auth_service.dart';
import 'package:gis_attendance/services/config_service.dart';
import 'package:gis_attendance/services/geofence_service.dart';
import 'package:gis_attendance/services/notification_service.dart';
import 'package:gis_attendance/services/permissions.dart';
import 'package:gis_attendance/services/update_service.dart';
import 'package:gis_attendance/theme/gis_palette.dart';
import 'package:gis_attendance/widgets/app_update.dart';
import 'package:gis_attendance/widgets/notification_bell.dart';
import 'package:gis_attendance/screens/admin/roles_permissions_screen.dart';
import 'package:gis_attendance/screens/admin/system_config_screen.dart';
// import 'package:gis_attendance/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'attendance_history_screen.dart';
import 'package:camera/camera.dart';
import 'package:gis_attendance/screens/face_verification_screen.dart';
import 'package:gis_attendance/screens/login_screen.dart';
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
  int _inactivityMinutes = 5;
  bool _loading = false;
  bool _profileLoading = true;
  String? _status;
  Map<String, dynamic>? _profile;
  Map<String, double>? _lastLocation;
  String? _locationName;
  bool _resolvingPlace = false;
  double? _locationAccuracy;
  bool _inGeoFence = false;
  bool _historyLoading = false;

  List<Map<String, dynamic>> _history = [];
  int _historyPage = 0;
  static const int _historyPageSize = 20;
  bool _biometricAvailable = false;
  bool _isAdmin = false;
  bool _isSuperAdmin = false;
  String _role = AppRoles.officer;
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
    _inactivityMinutes = await ConfigService.inactivityMinutes();
    _resetInactivityTimer();
    await _loadAllBranchLocation();
    await _loadProfile();       // profile loads first ✅
    await _checkLocation();
    await _initBiometrics();    // now _profile is ready ✅
    await _checkAdmin();
    await _autoUpdateCheck(); // silent — prompts only if an update exists
  }

  /// Silent update check on launch. Prompts only when a newer build is
  /// published; "Later" skips that version until a newer one appears.
  Future<void> _autoUpdateCheck() async {
    try {
      final result = await UpdateService.check();
      if (!mounted || result.update == null) return;
      final prefs = await SharedPreferences.getInstance();
      final skipped = prefs.getString('skipped_update_version');
      final info = result.update!;
      if (!info.mandatory && skipped == info.version) return;
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      await AppUpdate.prompt(
        context,
        info,
        onSkip: () =>
            prefs.setString('skipped_update_version', info.version),
      );
    } catch (_) {
      // never block launch for an update check
    }
  }

  Future<void> _checkAdmin() async {
    final admin = await _authService.isAdmin();
    final superAdmin = await _authService.isSuperAdmin();
    final role = await _authService.currentRole();
    if (!mounted) return;
    setState(() {
      _isAdmin = admin;
      _isSuperAdmin = superAdmin;
      _role = role;
    });
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
    _inactivityTimer =
        Timer(Duration(minutes: _inactivityMinutes), _logout);
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

  /// Best-effort reverse-geocode so the card shows a precise place name
  /// ("Law Faculty Building, Pentecost University, Sowutuom") instead of
  /// raw coordinates or a coarse city label. Tries, in order:
  /// 1. OpenStreetMap Nominatim (building/amenity-level detail, works on
  ///    web and mobile; single low-volume lookups + result caching keep us
  ///    inside the usage policy).
  /// 2. BigDataCloud client API (no key, CORS-enabled).
  /// 3. The native geocoder (Android/iOS/macOS — not web).
  /// Returns null when everything fails — callers keep the previous name.
  double? _resolvedLat;
  double? _resolvedLng;

  Future<String?> _resolvePlaceName(double lat, double lng) async {
    // Reuse the last name when we barely moved (saves quota + latency).
    if (_resolvedLat != null &&
        _locationName != null &&
        _attendanceService.distanceMeters(
                lat, lng, _resolvedLat!, _resolvedLng!) <
            50) {
      return _locationName;
    }
    final httpName = await _nominatimName(lat, lng) ??
        await _bigDataCloudName(lat, lng);
    if (httpName != null) {
      _resolvedLat = lat;
      _resolvedLng = lng;
      return httpName;
    }
    try {
      final marks = await Geocoding().placemarkFromCoordinates(lat, lng);
      if (marks.isNotEmpty) {
        final m = marks.first;
        final name = _joinPlaceParts([
          m.street,
          m.subLocality,
          m.locality,
          m.administrativeArea,
          m.country,
        ]);
        if (name.isNotEmpty) {
          _resolvedLat = lat;
          _resolvedLng = lng;
          return name;
        }
      }
    } catch (_) {
      // no name available
    }
    return null;
  }

  /// Joins non-empty, non-duplicate place parts ("Accra" inside
  /// "Accra New Town" is dropped).
  String _joinPlaceParts(List<dynamic> raw) {
    final parts = <String>[];
    for (final p in raw) {
      final t = (p ?? '').toString().trim();
      if (t.isEmpty) continue;
      final lower = t.toLowerCase();
      if (parts.any((e) => e.toLowerCase() == lower)) continue;
      if (parts.isNotEmpty &&
          parts.join(', ').toLowerCase().contains(lower)) {
        continue;
      }
      parts.add(t);
    }
    return parts.join(', ');
  }

  /// Building-level lookup via OpenStreetMap Nominatim.
  Future<String?> _nominatimName(double lat, double lng) async {
    try {
      final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lng&format=jsonv2&zoom=18&addressdetails=1');
      final resp = await http.get(
        uri,
        headers: kIsWeb
            ? const {'Accept': 'application/json'}
            : const {
                'Accept': 'application/json',
                'User-Agent': 'GIS-Attendance-App/1.0',
              },
      ).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body);
      if (body is! Map) return null;
      final addr = body['address'];
      if (addr is Map) {
        final name = _joinPlaceParts([
          addr['building'],
          addr['amenity'],
          addr['office'],
          addr['university'],
          addr['college'],
          addr['school'],
          addr['shop'],
          addr['road'],
          addr['footway'],
          addr['path'],
          addr['suburb'],
          addr['neighbourhood'],
          addr['quarter'],
          addr['city_district'],
          addr['city'],
          addr['town'],
          addr['village'],
          addr['country'],
        ]);
        if (name.isNotEmpty) return name;
      }
      // Fallback: most-specific segments of the display name.
      final display = (body['display_name'] ?? '').toString();
      if (display.isNotEmpty) {
        final segs = display
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .take(3)
            .toList();
        if (segs.isNotEmpty) return segs.join(', ');
      }
    } catch (_) {
      // fall through
    }
    return null;
  }

  /// Coarse city-level lookup (backup when Nominatim has no detail).
  Future<String?> _bigDataCloudName(double lat, double lng) async {
    try {
      final uri = Uri.parse(
          'https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=$lat&longitude=$lng&localityLanguage=en');
      final resp =
          await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body);
      if (body is Map) {
        final name = _joinPlaceParts([
          body['city'],
          body['locality'],
          body['principalSubdivision'],
          body['countryName'],
        ]);
        if (name.isNotEmpty) return name;
      }
    } catch (_) {
      // fall through
    }
    return null;
  }

  Future<void> _checkLocation() async {
    if (mounted) {
      setState(() {
        _locationStatusMessage = "Checking location...";
        _resolvingPlace = true;
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
          _resolvingPlace = false;
          _locationStatusMessage = locationResponse.message;
        });
        return;
      }

      final loc = locationResponse.location!;
      final fixAcc = (loc["acc"] as num?)?.toDouble();

      // Precision gate — never gate attendance on a guessed fix. Anything
      // worse than ±100 m is treated as unknown, not as in/out.
      if (fixAcc == null || fixAcc > 100) {
        // Still try to show a real place name (never coordinates).
        final placeName =
            await _resolvePlaceName(loc["lat"]!, loc["lng"]!);
        if (!mounted) return;
        setState(() {
          _lastLocation = loc;
          _locationAccuracy = loc["acc"];
          _inGeoFence = false;
          _matchedBranchId = null;
          _matchedBranchName = null;
          if (placeName != null && placeName.isNotEmpty) {
            _locationName = placeName;
          }
          _resolvingPlace = false;
          _locationStatusMessage = fixAcc == null
              ? "Waiting for GPS fix…"
              : "GPS not precise yet — move outdoors.";
        });
        return;
      }

      // A locally-set fence (admin → Geo-fence tab) takes priority over
      // the server's branch list. Always show its real name — never raw
      // coordinates.
      final fence = await GeoFenceService.load();
      if (fence != null) {
        final distance = _attendanceService.distanceMeters(
          loc["lat"]!,
          loc["lng"]!,
          fence.lat,
          fence.lng,
        );
        final inside = distance <= fence.radiusMeters;
        // Reverse-geocode for the street/area line, but fall back to the
        // fence's real name so the card never shows "Lat … Lng …".
        final placeName =
            await _resolvePlaceName(loc["lat"]!, loc["lng"]!);
        if (!mounted) return;
        setState(() {
          _lastLocation = loc;
          _locationAccuracy = loc["acc"];
          _inGeoFence = inside;
          _matchedBranchId = null;
          _matchedBranchName = fence.name;
          if (placeName != null && placeName.isNotEmpty) {
            _locationName = placeName;
          } else {
            _locationName ??= fence.name;
          }
          _resolvingPlace = false;
          _locationStatusMessage = inside
              ? "At ${fence.name}"
              : "Outside ${fence.name} fence";
        });
        return;
      }

      // Resolve a precise place name for the card (keeps the previous
      // name when resolution fails — never falls back to coordinates).
      final placeName =
          await _resolvePlaceName(loc["lat"]!, loc["lng"]!);
      if (placeName != null && placeName.isNotEmpty && mounted) {
        _locationName = placeName;
      }

      // Allowed distance/radius for attendance location
      num allowedMeters = await _attendanceService.GetAllowedDistance();

      bool isWithinLocation = false;
      String? matchedName;

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
          final rawName = location["name"]?.toString().trim();
          if (rawName != null && rawName.isNotEmpty) matchedName = rawName;
          break;
        }
      }

      setState(() {
        _lastLocation = loc;
        _locationAccuracy = loc["acc"];
        _resolvingPlace = false;

        _inGeoFence = isWithinLocation;

        if (isWithinLocation) {
          _locationStatusMessage =
              matchedName != null ? "At $matchedName" : "At Authorized Location";
        } else {
          _locationStatusMessage = "Not at Authorized Location";
        }

        // Keep the real branch name for the card; the street-level
        // reverse-geocoded name (_locationName) takes display priority.
        _matchedBranchId = null;
        _matchedBranchName = matchedName;
      });

    } catch (e) {
      if (!mounted) return;

      setState(() {
        _inGeoFence = false;
        _matchedBranchId = null;
        _matchedBranchName = null;
        _resolvingPlace = false;
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
                color: GisPalette.of(context).greenTint,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.verified_user_rounded, color: GisPalette.of(context).primary, size: 30),
            ),
            const SizedBox(height: 14),
            Text(
              "Verify Your Identity",
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: GisPalette.of(context).ink),
            ),
            const SizedBox(height: 4),
            Text(
              "Clocking in",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: GisPalette.of(context).muted, letterSpacing: 0.4),
            ),
          ],
        ),
        content: Text(
          "Choose how you'd like to verify your identity to clock in.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: GisPalette.of(context).muted),
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
                backgroundColor: GisPalette.of(context).primary,
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
                side: BorderSide(color: hasFaceImage ? GisPalette.of(context).primary : Colors.grey.shade400, width: 1.4),
                foregroundColor: hasFaceImage ? GisPalette.of(context).primary : Colors.grey,
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
                color: GisPalette.of(context).redTint,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.verified_user_rounded, color: GisPalette.of(context).danger, size: 30),
            ),
            const SizedBox(height: 14),
            Text(
              "Verify Your Identity",
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: GisPalette.of(context).ink),
            ),
            const SizedBox(height: 4),
            Text(
              "Clocking out",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: GisPalette.of(context).muted, letterSpacing: 0.4),
            ),
          ],
        ),
        content: Text(
          "Choose how you'd like to verify your identity to clock out.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: GisPalette.of(context).muted),
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
                backgroundColor: GisPalette.of(context).danger,
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
                side: BorderSide(color: hasFaceImage ? GisPalette.of(context).danger : Colors.grey.shade400, width: 1.4),
                foregroundColor: hasFaceImage ? GisPalette.of(context).danger : Colors.grey,
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
    final late = await ConfigService.lateCutoff();
    final cutoffTime =
        DateTime(now.year, now.month, now.day, late.hour, late.minute);

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
            children: [
              Icon(Icons.schedule_rounded, color: GisPalette.of(context).gold),
              SizedBox(width: 10),
              Text("You are late", style: TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: "Enter reason for being late",
              filled: true,
              fillColor: GisPalette.of(context).bg,
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
                  backgroundColor: GisPalette.of(context).primary,
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
    final early = await ConfigService.earlyCutoff();
    final clockOutCutoff =
        DateTime(now.year, now.month, now.day, early.hour, early.minute);
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
            children: [
              Icon(Icons.exit_to_app_rounded, color: GisPalette.of(context).danger),
              SizedBox(width: 10),
              Text("You are leaving earlier", style: TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: "Enter reason for leaving earlier",
              filled: true,
              fillColor: GisPalette.of(context).bg,
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
                  backgroundColor: GisPalette.of(context).primary,
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
      NotificationService.logActivity(
        'Clocked in',
        'Officer $userId clocked in${_locationName == null ? '' : ' at $_locationName'}.',
        category: 'Attendance',
      );
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
      NotificationService.logActivity(
        'Clocked out',
        'Officer $userId clocked out${_locationName == null ? '' : ' from $_locationName'}.',
        category: 'Attendance',
      );
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
    final who =
        (_profile?["officerId"] ?? _profile?["username"] ?? 'Officer')
            .toString();
    NotificationService.logActivity(
      'Signed out',
      'Officer $who signed out.',
      category: 'Security',
      loginEvent: true,
    );
    await _authService.logout();
    if (!mounted) return;
    // Go back to the sign-in page (clearing the whole stack so Back can
    // never return to the dashboard). The sign-in page offers the
    // "Close app" option. Because the session token is cleared first, a
    // later reopen also lands on sign-in, not the dashboard.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(fromLogout: true),
      ),
      (_) => false,
    );
  }

  Future<void> _logoutPressed() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Logout", style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text("Are you sure you want to logout? You will be taken to the sign-in page."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false), // Cancel
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true), // Confirm
            child: Text("Logout", style: TextStyle(color: GisPalette.of(context).danger, fontWeight: FontWeight.w700)),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: GisPalette.of(context).hairline),
        boxShadow: [
          BoxShadow(
            color: GisPalette.of(context).ink.withValues(alpha: 0.06),
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

  Widget _sectionEyebrow(String text, {Color? color}) {
    final c = color ?? GisPalette.of(context).muted;
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: c,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Premium home sections (visual-only — all data comes from existing state)
  // ---------------------------------------------------------------------

  /// Profile photo URL — the stored profile carries it as `faceImageUrl`
  /// (auth flattening), with legacy/alternate `faceImage` /
  /// `face_image_url` spellings tolerated. Empty strings count as missing,
  /// so a blank URL never reaches [NetworkImage].
  String? _facePhotoUrl() {
    if (_profileLoading || _profile == null) return null;
    for (final k in const ['faceImageUrl', 'faceImage', 'face_image_url']) {
      final v = _profile![k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  Widget _avatar({required String initials, String? faceImage, double radius = 30}) {
    final ready = !_profileLoading && _profile != null;
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: GisPalette.of(context).gold, width: 2),
      ),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: Colors.white,
        backgroundImage:
            (ready && faceImage != null) ? NetworkImage(faceImage) : null,
        child: (!ready || faceImage == null)
            ? Text(
                initials,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: radius * 0.7,
                  color: GisPalette.of(context).primary,
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildGreetingHeader() {
    final ready = !_profileLoading && _profile != null;
    final name =
        (_profile?["fullName"] ?? _profile?["email"] ?? "GIS Staff").toString();
    final firstName = name.split(' ').first;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionEyebrow("Staff dashboard"),
              const SizedBox(height: 6),
              Text(
                '${_getGreeting()}, $firstName',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: GisPalette.of(context).ink,
                  letterSpacing: -0.5,
                ),
              ),
              if (!ready)
                Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    "Loading your profile…",
                    style: TextStyle(fontSize: 12.5, color: GisPalette.of(context).muted),
                  ),
                ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: GisPalette.of(context).hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_today_rounded,
                  size: 14, color: GisPalette.of(context).primary),
              const SizedBox(width: 6),
              Text(
                _currentDateString.isEmpty ? '—' : _currentDateString,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: GisPalette.of(context).ink),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIdCard() {
    final ready = !_profileLoading && _profile != null;
    final name =
        (_profile?["fullName"] ?? _profile?["email"] ?? "GIS Staff").toString();
    final email = (_profile?["email"] ?? "----").toString();
    final username = (_profile?["username"] ?? "----").toString();
    final department =
        (_profile?["department"] ?? _profile?["branch"] ?? "----").toString();
    final role = (_profile?["role"] ?? "STAFF").toString();
    final faceImage = _facePhotoUrl();
    final initials = name.isNotEmpty ? name[0].toUpperCase() : "A";
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [GisPalette.of(context).primary, GisPalette.of(context).darkBg],
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
      child: Stack(
        children: [
          Positioned(
            top: -40,
            right: -40,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            left: -30,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: GisPalette.of(context).gold.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: GisPalette.of(context).gold,
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(24),
                  bottomLeft: Radius.circular(16),
                ),
              ),
              child: Text(
                role.toUpperCase(),
                style: TextStyle(
                  color: GisPalette.of(context).darkBg,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _avatar(
                        initials: initials,
                        faceImage: faceImage,
                        radius: 30),
                    const SizedBox(width: 14),
                    Expanded(
                      child: ready
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 17),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  email,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12.5),
                                ),
                              ],
                            )
                          : const Text(
                              "Loading user…",
                              style: TextStyle(
                                  color: Colors.white, fontSize: 14),
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
                        child: const Icon(Icons.refresh_rounded,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  height: 1,
                  color: GisPalette.of(context).gold.withValues(alpha: 0.35),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "OFFICER ID",
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.apartment_rounded,
                                size: 14, color: GisPalette.of(context).gold),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                department,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard() {
    final bool branchMissing = _profile != null &&
        (_profile!['department'] == null ||
            _profile!['department'].toString().isEmpty);
    final String statusText = branchMissing
        ? "Profile error: no branch assigned"
        : (_locationStatusMessage.isEmpty
            ? "No home branch assigned"
            : _locationStatusMessage);

    late final IconData statusIcon;
    late final Color iconFg;
    late final Color iconBg;
    late final Color pillBg;
    late final Color pillFg;
    if (branchMissing) {
      statusIcon = Icons.error_outline_rounded;
      iconFg = GisPalette.of(context).danger;
      iconBg = GisPalette.of(context).redTint;
      pillBg = GisPalette.of(context).redTint;
      pillFg = const Color(0xFF9E2B2B);
    } else if (_inGeoFence) {
      statusIcon = Icons.check_circle_rounded;
      iconFg = const Color(0xFF1FAA53);
      iconBg = GisPalette.of(context).greenTint;
      pillBg = GisPalette.of(context).greenTint;
      pillFg = const Color(0xFF14663A);
    } else {
      statusIcon = Icons.location_on_rounded;
      iconFg = const Color(0xFF9A7B0A);
      iconBg = GisPalette.of(context).goldTint;
      pillBg = GisPalette.of(context).goldTint;
      pillFg = const Color(0xFF7A5F00);
    }

    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _iconBadge(statusIcon, fg: iconFg, bg: iconBg, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Location",
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: GisPalette.of(context).ink),
                ),
              ),
              InkWell(
                onTap: _checkLocation,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: GisPalette.of(context).bg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.my_location_rounded,
                      size: 18, color: GisPalette.of(context).primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: pillBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(statusIcon, size: 16, color: pillFg),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    statusText,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: pillFg),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.place_outlined,
                    size: 13, color: GisPalette.of(context).muted),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  // Real place name only — never raw coordinates.
                  _locationName ??
                      _matchedBranchName ??
                      (_resolvingPlace || _lastLocation != null
                          ? "Locating precise location…"
                          : "Place name unavailable — tap refresh"),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11.5, color: GisPalette.of(context).muted),
                ),
              ),
              if (_locationAccuracy != null) ...[
                const SizedBox(width: 6),
                _AccuracyBadge(meters: _locationAccuracy!),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildClockPanel() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF24401F), GisPalette.of(context).darkBg],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.20),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _sectionEyebrow("Today's shift",
                        color: Colors.white60),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.calendar_today_rounded,
                              size: 12, color: GisPalette.of(context).gold),
                          const SizedBox(width: 6),
                          Text(
                            _currentDateString.isEmpty
                                ? '—'
                                : _currentDateString,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _currentTimeString.isEmpty
                      ? '--:--:--'
                      : _currentTimeString,
                  style: const TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 1,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _inGeoFence
                      ? 'You are at an authorized location'
                      : 'Clock-in requires an authorized location',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.white60),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: _perforatedDivider(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: (_loading) ? null : _onClockInPressed,
                        icon: const Icon(Icons.login_rounded,
                            color: Colors.white, size: 20),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: GisPalette.of(context).success,
                          disabledBackgroundColor:
                              GisPalette.of(context).success.withValues(alpha: 0.4),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding:
                              const EdgeInsets.symmetric(vertical: 15),
                        ),
                        label: const Text(
                          "Clock In",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: (_loading) ? null : _onClockOutPressed,
                        icon: const Icon(Icons.logout_rounded,
                            color: Colors.white, size: 20),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: GisPalette.of(context).danger,
                          disabledBackgroundColor:
                              GisPalette.of(context).danger.withValues(alpha: 0.4),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding:
                              const EdgeInsets.symmetric(vertical: 15),
                        ),
                        label: const Text(
                          "Clock Out",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_loading) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: GisPalette.of(context).gold),
                  ),
                ],
                if (_status != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_rounded,
                            color: GisPalette.of(context).success, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _status!,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600),
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
    );
  }

  Widget _buildHistoryCard() {
    final total = _history.length;
    final totalPages =
        (total + _historyPageSize - 1) ~/ _historyPageSize;
    final currentPage = _historyPage.clamp(
        0, totalPages == 0 ? 0 : totalPages - 1);
    final start = currentPage * _historyPageSize;
    final endExclusive = (start + _historyPageSize) > total
        ? total
        : (start + _historyPageSize);
    final pageSlice = _history.sublist(start, endExclusive);

    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _iconBadge(Icons.calendar_today_rounded,
                  fg: GisPalette.of(context).primary, bg: GisPalette.of(context).goldTint, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Attendance History",
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: GisPalette.of(context).ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "$total record${total == 1 ? '' : 's'}",
                      style: TextStyle(
                          fontSize: 11.5, color: GisPalette.of(context).muted),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: _historyLoading ? null : _loadHistory,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                      color: GisPalette.of(context).bg, shape: BoxShape.circle),
                  child: Icon(Icons.refresh_rounded,
                      size: 18, color: GisPalette.of(context).primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_historyLoading)
            Center(
                child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: GisPalette.of(context).primary),
            ))
          else if (_history.isEmpty)
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: GisPalette.of(context).bg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Icon(Icons.inbox_outlined,
                      color: GisPalette.of(context).muted, size: 26),
                  SizedBox(height: 8),
                  Text(
                    "No attendance records",
                    style: TextStyle(color: GisPalette.of(context).muted, fontSize: 12.5),
                  ),
                ],
              ),
            )
          else
            Column(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                          flex: 3,
                          child: Text("Date",
                              style: TextStyle(
                                  fontSize: 11,
                                  color: GisPalette.of(context).muted,
                                  fontWeight: FontWeight.w700))),
                      Expanded(
                          flex: 2,
                          child: Text("In",
                              style: TextStyle(
                                  fontSize: 11,
                                  color: GisPalette.of(context).muted,
                                  fontWeight: FontWeight.w700))),
                      Expanded(
                          flex: 2,
                          child: Text("Out",
                              style: TextStyle(
                                  fontSize: 11,
                                  color: GisPalette.of(context).muted,
                                  fontWeight: FontWeight.w700))),
                      Expanded(
                          flex: 3,
                          child: Text("Hours",
                              style: TextStyle(
                                  fontSize: 11,
                                  color: GisPalette.of(context).muted,
                                  fontWeight: FontWeight.w700))),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                ...pageSlice
                    .asMap()
                    .entries
                    .map((e) =>
                        _HistoryRow(record: e.value, alt: e.key.isOdd))
                    .toList(),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      "Showing ${total == 0 ? 0 : start + 1}-$endExclusive of $total",
                      style:
                          TextStyle(fontSize: 11.5, color: GisPalette.of(context).muted),
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
                          border: Border.all(color: GisPalette.of(context).hairline),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.chevron_left_rounded,
                            size: 20,
                            color: currentPage > 0
                                ? GisPalette.of(context).ink
                                : Colors.grey.shade300),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text("${currentPage + 1} / ${totalPages == 0 ? 1 : totalPages}",
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: GisPalette.of(context).ink)),
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
                          border: Border.all(color: GisPalette.of(context).hairline),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.chevron_right_rounded,
                            size: 20,
                            color: (currentPage + 1) < totalPages
                                ? GisPalette.of(context).ink
                                : Colors.grey.shade300),
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
                    icon: Icon(Icons.history_rounded,
                        size: 18, color: GisPalette.of(context).primary),
                    label: Text("View Full History",
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: GisPalette.of(context).primary)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      side: BorderSide(
                          color: GisPalette.of(context).primary, width: 1.4),
                      foregroundColor: GisPalette.of(context).primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _drawerSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: GisPalette.of(context).muted,
        ),
      ),
    );
  }

  Widget _buildPremiumDrawer() {
    final name =
        (_profile?["fullName"] ?? _profile?["email"] ?? "GIS Staff").toString();
    final email = (_profile?["email"] ?? "----").toString();
    final role = (_profile?["role"] ?? "STAFF").toString();
    final faceImage = _facePhotoUrl();
    final initials = name.isNotEmpty ? name[0].toUpperCase() : "A";
    return Drawer(
      backgroundColor: Colors.white,
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          Container(
            padding: EdgeInsets.fromLTRB(20, 56, 20, 22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [GisPalette.of(context).darkBg, GisPalette.of(context).primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _avatar(
                        initials: initials,
                        faceImage: faceImage,
                        radius: 28),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 16),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: GisPalette.of(context).gold,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    role.toUpperCase(),
                    style: TextStyle(
                      color: GisPalette.of(context).darkBg,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _drawerSectionLabel("Menu"),
          _DrawerTile(
            icon: Icons.home_outlined,
            label: 'Dashboard',
            onTap: () => Navigator.pop(context),
          ),
          _DrawerTile(
            icon: Icons.history_rounded,
            label: 'Attendance History',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AttendanceHistoryScreen(
                      profile: _profile,
                      attendanceService: _attendanceService),
                ),
              );
            },
          ),
          _DrawerTile(
            icon: Icons.apps_outlined,
            label: 'Other pages',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) =>
                        const UnderDevelopmentScreen()),
              ).then((_) => _initBiometrics());
            },
          ),
          _DrawerTile(
            icon: Icons.settings_outlined,
            label: 'Profile Settings',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const SettingsScreen()),
              ).then((_) => _initBiometrics());
            },
          ),
          if (_isAdmin || _isSuperAdmin) ...[
            _DrawerTile(
              icon: Icons.admin_panel_settings_rounded,
              label: 'Admin',
              iconColor: const Color(0xFF9A7B0A),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const AdminHomeScreen()),
                );
              },
            ),
            _DrawerTile(
              icon: Icons.manage_accounts_outlined,
              label: 'Roles & Permissions',
              iconColor: GisPalette.of(context).primary,
              labelColor: GisPalette.of(context).primary,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) =>
                          const RolesPermissionsScreen()),
                );
              },
            ),
            _DrawerTile(
              icon: Icons.tune_rounded,
              label: 'System Config',
              iconColor: const Color(0xFF9A7B0A),
              labelColor: const Color(0xFF7A5F00),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) =>
                          const SystemConfigScreen()),
                );
              },
            ),
          ],
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Divider(height: 1, color: GisPalette.of(context).hairline),
          ),
          _drawerSectionLabel("Account"),
          _DrawerTile(
            icon: Icons.logout_rounded,
            label: 'Logout',
            iconColor: GisPalette.of(context).danger,
            labelColor: GisPalette.of(context).danger,
            onTap: _logoutPressed,
          ),
          const SizedBox(height: 8),
          Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                "GIS Attendance · v1.0.0",
                style: TextStyle(fontSize: 11, color: GisPalette.of(context).muted),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Duty-roster PDF shortcut for roles holding the roster permission
  /// (admins and super admins).
  Widget _buildRosterShortcut() {
    if (!RolePermissions.can(_role, AppPermissions.rosterPdf)) {
      return const SizedBox.shrink();
    }
    return _sectionCard(
      child: Row(
        children: [
          _iconBadge(
            Icons.picture_as_pdf_outlined,
            fg: const Color(0xFF6C5CE7),
            bg: const Color(0xFFEDEBFF),
            size: 42,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Duty roster PDF',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: GisPalette.of(context).ink),
                ),
                SizedBox(height: 2),
                Text(
                  'Generate, preview & share the attendance roster',
                  style: TextStyle(fontSize: 12, color: GisPalette.of(context).muted),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      const AdminHomeScreen(initialTab: 4),
                ),
              );
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 17),
            label: const Text('Open'),
            style: ElevatedButton.styleFrom(
              backgroundColor: GisPalette.of(context).primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 1000;

    return GestureDetector(
      onTap: _resetInactivityTimer,
      onPanDown: (_) => _resetInactivityTimer(),
      onScaleStart: (_) => _resetInactivityTimer(),
      child: Scaffold(
        backgroundColor: GisPalette.of(context).bg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: GisPalette.of(context).ink,
          elevation: 0,
          titleSpacing: 4,
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [GisPalette.of(context).primary, GisPalette.of(context).darkBg],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(Icons.security_rounded,
                    color: GisPalette.of(context).gold, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "GIS Attendance",
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: GisPalette.of(context).ink),
                    ),
                    Text(
                      _currentDateString.isEmpty
                          ? 'Safe Migration, Secure Ghana'
                          : 'Today · $_currentDateString',
                      style: TextStyle(
                          fontSize: 11,
                          color: GisPalette.of(context).muted,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),
          centerTitle: false,
          actions: [
            const NotificationBell(),
            IconButton(
              onPressed: _logoutPressed,
              icon: Icon(Icons.logout_rounded,
                  color: GisPalette.of(context).primary, size: 21),
            ),
            const SizedBox(width: 4),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: GisPalette.of(context).hairline),
          ),
        ),

        drawer: _buildPremiumDrawer(),

        body: RefreshIndicator(
          color: GisPalette.of(context).primary,
          onRefresh: () async {
            await _loadProfile();
            await _checkLocation();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildGreetingHeader(),
                    const SizedBox(height: 16),
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: Column(
                              children: [
                                _buildIdCard(),
                                const SizedBox(height: 16),
                                _buildClockPanel(),
                                const SizedBox(height: 16),
                                _buildRosterShortcut(),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 6,
                            child: Column(
                              children: [
                                _buildLocationCard(),
                                const SizedBox(height: 16),
                                _buildHistoryCard(),
                              ],
                            ),
                          ),
                        ],
                      )
                    else ...[
                      _buildIdCard(),
                      const SizedBox(height: 16),
                      _buildClockPanel(),
                      const SizedBox(height: 16),
                      _buildRosterShortcut(),
                      const SizedBox(height: 16),
                      _buildLocationCard(),
                      const SizedBox(height: 16),
                      _buildHistoryCard(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // (Officer meta rows now live inline in _buildIdCard.)
}

/// Honest GPS precision pill: green ≤100 m, amber ≤500 m, red beyond.
/// A red badge means the fix — and therefore the displayed name — is
/// unreliable, e.g. a coarse browser fix measured in kilometres.
class _AccuracyBadge extends StatelessWidget {
  final double meters;
  const _AccuracyBadge({required this.meters});

  @override
  Widget build(BuildContext context) {
    final label = meters < 1000
        ? '±${meters.round()} m'
        : '±${(meters / 1000).toStringAsFixed(1)} km';
    final Color fg;
    final Color bg;
    if (meters <= 100) {
      fg = const Color(0xFF14663A);
      bg = const Color(0xFFE1F9EC);
    } else if (meters <= 500) {
      fg = const Color(0xFF7A5F00);
      bg = const Color(0xFFFBF1D8);
    } else {
      fg = const Color(0xFF9E2B2B);
      bg = const Color(0xFFFBE6E6);
    }
    return Tooltip(
      message: meters > 100
          ? 'GPS fix is coarse — move outdoors for a precise location'
          : 'GPS fix precision',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(8)),
        child: Text(label,
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: fg)),
      ),
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
          color: (iconColor ?? GisPalette.of(context).primary).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor ?? GisPalette.of(context).primary, size: 19),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: labelColor ?? GisPalette.of(context).ink,
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
        color: alt ? const Color(0xFFF1F4F0) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          // Date column - use 'date' field
          Expanded(
            flex: 3,
            child: Text(
              date != null ? _formatDate(date.toString()) : '-',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: GisPalette.of(context).ink),
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
              style: TextStyle(fontSize: 12.5, color: GisPalette.of(context).success, fontWeight: FontWeight.w600),
            ),
          ),
          // Clock-out time
          Expanded(
            flex: 2,
            child: Text(
              clockOut != null ? _formatTime(clockOut.toString()) : '-',
              style: TextStyle(fontSize: 12.5, color: GisPalette.of(context).danger, fontWeight: FontWeight.w600),
            ),
          ),
          // Total hours
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: GisPalette.of(context).goldTint,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _formatTotalHours(durationMinutes, clockIn, clockOut),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: GisPalette.of(context).primary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
