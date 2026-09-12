// AUTH SERVICE (fixed)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:gis_attendance/config/app_config.dart';
import 'package:gis_attendance/services/api_result.dart';
import 'package:gis_attendance/utils/app_log.dart';

class ProfileUpdateResult {
  final bool success;
  final int? statusCode;
  final String? message;
  const ProfileUpdateResult({required this.success, this.statusCode, this.message});

  /// True when the failure is specifically "not authorized as admin" —
  /// PATCH /api/officers requires an admin bearer token this client
  /// never has for a regular officer, so 401/403 here doesn't mean the
  /// request itself was wrong.
  bool get isAdminGated => statusCode == 401 || statusCode == 403;
}

/// Outcome of a login attempt. `message` is always safe to show the user
/// directly — it distinguishes wrong credentials, an inactive account, a
/// server fault and a network failure instead of collapsing them all into
/// a single "login failed".
class LoginResult {
  final bool success;
  final String message;
  const LoginResult(this.success, this.message);
}

class AuthService {
  // ==================== API Configuration ====================
  // Single source of truth lives in AppConfig.apiBaseUrl (reads
  // API_BASE_URL from .env, falls back to the deployed API). Every URL
  // below is derived from it so login/register/officer/upload can never
  // silently drift apart from the rest of the app again.
  static String get _baseUrl => AppConfig.apiBaseUrl;

  static String get _authLoginUrl => "$_baseUrl/auth/login";
  static String get _authRegisterUrl => "$_baseUrl/auth/register";
  static String get _officerUrl => "$_baseUrl/officers";
  static String get _registerFaceUrl => "$_baseUrl/officers/register-face";

  // Storage Keys
  static const String _tokenKey = "auth_token";
  static const String _userKey = "auth_user";
  static const String _secureUsernameKey = "secure_username";
  static const String _securePasswordKey = "secure_password";
  static const String _biometricEnabledKey = "biometric_enabled";
  static const String _biometricOwnerKey = "biometric_owner";

  final _storage = const FlutterSecureStorage();

  // ==================== AUTHENTICATION ====================

  /// Login with officer ID and password.
  ///
  /// Never throws — every failure path (bad credentials, inactive account,
  /// server error, no connectivity) comes back as a [LoginResult] whose
  /// `message` can be shown to the user as-is.
  Future<LoginResult> login(String officerId, String password) async {
    http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(_authLoginUrl),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"officer_id": officerId, "password": password}),
          )
          .timeout(const Duration(seconds: 20));
    } catch (e, st) {
      AppLog.e("AuthService", "login network failure", e, st);
      return LoginResult(false, describeNetworkError(e));
    }

    Map<String, dynamic> data = const {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {
      // Non-JSON body (proxy error page, empty response, etc.)
    }

    if (response.statusCode == 200 && data["code"] == "000") {
      await _generateAndStoreToken(data, officerId);
      await _storeSession(data, officerId);

      // Save credentials only if no biometric owner exists
      final existingOwner = await _storage.read(key: _biometricOwnerKey);
      if (existingOwner == null) {
        await _storage.write(key: _secureUsernameKey, value: officerId);
        await _storage.write(key: _securePasswordKey, value: password);
        await _storage.write(key: _biometricOwnerKey, value: officerId);
      }

      AppLog.i("AuthService", "login ok for $officerId");
      return const LoginResult(true, "Login successful");
    }

    AppLog.w("AuthService",
        "login failed HTTP ${response.statusCode}: ${response.body}");

    // Endpoint-specific wording where the generic mapper is too vague;
    // otherwise fall through to the server message / shared fallback.
    final serverMessage = serverMessageOf(data);
    switch (response.statusCode) {
      case 400:
        return const LoginResult(
            false, "Enter both your officer ID and password.");
      case 401:
        return LoginResult(
            false, serverMessage ?? "Invalid officer ID or password.");
      case 403:
        return LoginResult(false,
            serverMessage ?? "Your account isn't active yet. Contact an administrator.");
      case 404:
        return const LoginResult(
            false, "No account found for that officer ID.");
      default:
        return LoginResult(
            false, describeHttpError(response.statusCode, serverMessage));
    }
  }

  /// Logout - Clear all stored data
  Future<void> logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      await prefs.remove(_userKey);
      AppLog.i("AuthService", "✅ Logged out");
    } catch (e) {
      AppLog.e("AuthService", "❌ Logout error: $e");
    }
  }

  // ==================== TOKEN MANAGEMENT ====================

  Future<String?> getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_tokenKey);
    } catch (e) {
      AppLog.e("AuthService", "❌ Error getting token: $e");
      return null;
    }
  }

  Future<Map<String, dynamic>?> getUserFromToken() async {
    try {
      final token = await getToken();
      if (token == null) return null;

      final decoded = utf8.decode(base64Decode(token));
      final userData = jsonDecode(decoded) as Map<String, dynamic>;

      final expiryTime = userData["expiryTime"];
      if (expiryTime != null) {
        final expiry = DateTime.parse(expiryTime);
        if (DateTime.now().isAfter(expiry)) {
          AppLog.w("AuthService", "⚠️ Token expired");
          await logout();
          return null;
        }
      }

      return userData;
    } catch (e) {
      AppLog.e("AuthService", "❌ Error decoding token: $e");
      return null;
    }
  }

  Future<bool> hasValidToken() async {
    final user = await getUserFromToken();
    return user != null;
  }

  /// Read the full stored profile (everything HomeScreen/Attendance need:
  /// id, officerId, username, email, fullName, department, position,
  /// phoneNumber, faceImageUrl, isActive).
  Future<Map<String, dynamic>?> getStoredProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_userKey);
      if (raw == null) return null;
      AppLog.d("AuthService", jsonEncode(raw));
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      AppLog.e("AuthService", "❌ Error reading stored profile: $e");
      return null;
    }
  }

  // ==================== ADMIN ====================

  /// The admin bearer token from the last login, or null if this officer
  /// isn't an admin / the token has expired. Send it as
  /// `Authorization: Bearer <token>` on admin-gated endpoints.
  Future<String?> getAdminToken() async {
    final profile = await getStoredProfile();
    final token = profile?['adminToken'];
    if (token is! String || token.isEmpty) return null;
    return _adminTokenExpired(token) ? null : token;
  }

  /// True when the current session belongs to an admin with a still-valid
  /// admin token.
  Future<bool> isAdmin() async {
    final profile = await getStoredProfile();
    if ((profile?['role']?.toString() ?? 'officer') != 'admin') return false;
    return (await getAdminToken()) != null;
  }

  /// The admin token is `base64url(jsonClaims).signature`; claims carry
  /// `exp` in epoch millis. We only read `exp` here — the signature is
  /// verified server-side.
  bool _adminTokenExpired(String token) {
    try {
      final payload = token.split('.').first;
      final normalized = base64.normalize(payload);
      final claims = jsonDecode(utf8.decode(base64Url.decode(normalized)))
          as Map<String, dynamic>;
      final exp = claims['exp'];
      if (exp is! num) return false;
      return DateTime.now().millisecondsSinceEpoch >= exp;
    } catch (_) {
      return false;
    }
  }

  // ==================== OFFICER MANAGEMENT ====================

  /// Look up an existing (pre-registered / HR-directory) officer by ID,
  /// used to prefill Step 2 of registration. GET /api/officers/{id} takes
  /// the internal primary key, not officer_id, so this uses the
  /// collection route's ?officer_id= filter instead, which returns a list.
  Future<Map<String, String>?> getOfficerDetails(String officerId) async {
    try {
      final response = await http.get(
        Uri.parse("$_officerUrl?officer_id=$officerId"),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(response.body);

        if (body['code'] == '000' && body['data'] is List) {
          final list = body['data'] as List;
          if (list.isEmpty) return null;
          final data = Map<String, dynamic>.from(list.first as Map);
          return {
            'id': (data['id'] ?? '').toString(),
            'fullName': (data['full_name'] ?? '').toString(),
            'email': (data['email'] ?? '').toString(),
            'department': (data['department'] ?? '').toString(),
            'position': (data['position'] ?? '').toString(),
            'phoneNumber': (data['phone_number'] ?? '').toString(),
          };
        }
      }

      if (kDebugMode) {
        AppLog.e("AuthService", "❌ Failed to fetch officer: HTTP ${response.statusCode}");
      }
    } catch (e) {
      AppLog.e("AuthService", "❌ Error fetching officer data: $e");
    }
    return null;
  }

  /// Flattens a raw GET/POST /officer record (the same flat shape your
  /// "Officer inserted successfully" response uses) into the same key
  /// set the cached login profile uses, merging over `cachedFallback`
  /// so a partial/missing field never wipes out good cached data.
  Map<String, dynamic> _flattenOfficerRecord(
    Map<String, dynamic> data, {
    Map<String, dynamic>? cachedFallback,
  }) {
    final faceUrl = data['face_image_url'];
    return {
      "id": data['id'] ?? cachedFallback?['id'],
      "officerId": data['officer_id'] ?? cachedFallback?['officerId'],
      "username": data['officer_id'] ?? cachedFallback?['username'],
      "role": data['role'] ?? cachedFallback?['role'] ?? 'officer',
      "email": data['email'] ?? cachedFallback?['email'],
      "fullName": data['full_name'] ?? cachedFallback?['fullName'],
      "department": data['department'] ?? cachedFallback?['department'],
      "position": data['position'] ?? cachedFallback?['position'],
      "phoneNumber": data['phone_number'] ?? cachedFallback?['phoneNumber'],
      "faceImageUrl": (faceUrl is String && faceUrl.isNotEmpty)
          ? faceUrl
          : cachedFallback?['faceImageUrl'],
      "isActive": data['is_active'] ?? cachedFallback?['isActive'],
      // The admin bearer token is issued only by /api/auth/login and is
      // never part of an officer GET — always carry it over from the
      // cached login profile so a profile refresh doesn't drop it.
      "adminToken": cachedFallback?['adminToken'],
    };
  }

  /// Returns the officer's profile for use across the app (HomeScreen,
  /// AttendanceService, etc). Always prefers a fresh server copy, but
  /// falls back to the cached login profile on any network failure so
  /// the UI never regresses to "no profile" just because a request
  /// timed out. Returns null only if there's truly nothing cached and
  /// the server is unreachable — i.e. the person isn't logged in.
  Future<Map<String, dynamic>?> fetchLatestProfile() async {
    final cached = await getStoredProfile();
    final officerId = cached?['id'] ?? '';
    if (officerId == null) return cached;

    try {
      final response = await http.get(
        Uri.parse("$_officerUrl/$officerId"),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['code'] == '000' && body['data'] is Map) {
          final merged = _flattenOfficerRecord(
            body['data'] as Map<String, dynamic>,
            cachedFallback: cached,
          );
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_userKey, jsonEncode(merged));
          AppLog.i("AuthService", "✅ Profile refreshed from server");
          return merged;
        }
      }
      if (kDebugMode) {
        AppLog.w("AuthService", "⚠️ fetchLatestProfile: HTTP ${response.statusCode} — using cached profile");
      }
    } catch (e) {
      AppLog.w("AuthService", "⚠️ fetchLatestProfile error: $e — using cached profile");
    }
    return cached;
  }

  /// Self-registration via POST /api/auth/register. New accounts are
  /// created inactive server-side and need an admin to approve them
  /// (PATCH /api/officers with is_active: true) before they can log in —
  /// the returned message reflects that, so callers should surface it
  /// instead of implying an immediate working login.
  Future<Map<String, dynamic>> register({
    required String officerId,
    required String email,
    required String password,
    required String fullName,
    required String department,
    required String position,
    required String phoneNumber,
    File? faceFile,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(_authRegisterUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "officer_id": officerId,
          "password": password,
          "email": email,
          "name": fullName,
          "department": department,
          "position": position,
          "phone_number": phoneNumber,
        }),
      );

      final body = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && body["code"] == "000") {
        AppLog.i("AuthService", "✅ Registration successful");

        if (faceFile != null) {
          final faceRes = await registerFace(
            officerId: officerId,
            faceFile: faceFile,
          );
          if (!faceRes.ok) {
            AppLog.w("AuthService",
                "Registration succeeded but face upload failed for $officerId: ${faceRes.message}");
          }
        }

        return {
          "success": true,
          "message":
              "Registration successful. Your account is pending admin approval before you can log in.",
        };
      }

      if (kDebugMode) {
        AppLog.e("AuthService", "❌ Registration failed: HTTP ${response.statusCode} ${response.body}");
      }
      return {
        "success": false,
        "message": body["message"]?.toString() ?? "Registration failed. Please try again.",
      };
    } catch (e) {
      AppLog.e("AuthService", "❌ Registration error: $e");
      return {
        "success": false,
        "message": "Something went wrong. Please check your connection.",
      };
    }
  }

  /// Registers/updates the officer's face via POST
  /// /api/officers/register-face (multipart image + officer_id). Returns
  /// an [ApiResult] whose `message` is safe to show the user — it surfaces
  /// the backend's actual reason (e.g. "No face detected in image.")
  /// instead of a generic failure.
  Future<ApiResult<void>> registerFace({
    required String officerId,
    required File faceFile,
  }) async {
    http.Response response;
    try {
      final request = http.MultipartRequest("POST", Uri.parse(_registerFaceUrl))
        ..fields["officer_id"] = officerId
        ..files.add(await http.MultipartFile.fromPath("image", faceFile.path));

      final streamed = await request.send().timeout(const Duration(seconds: 30));
      response = await http.Response.fromStream(streamed);
    } catch (e, st) {
      AppLog.e("AuthService", "registerFace network failure", e, st);
      return ApiResult.failure(describeNetworkError(e));
    }

    dynamic body;
    try {
      body = response.body.isEmpty ? null : jsonDecode(response.body);
    } catch (_) {
      body = null;
    }

    if (response.statusCode == 200 && body is Map && body["success"] == true) {
      AppLog.i("AuthService", "Face registered for $officerId");
      return ApiResult.success(null, message: "Face photo saved.");
    }

    AppLog.w("AuthService",
        "registerFace failed HTTP ${response.statusCode}: ${response.body}");
    return ApiResult.failure(
      serverMessageOf(body) ??
          describeHttpError(response.statusCode) ,
      statusCode: response.statusCode,
    );
  }

  // ==================== PROFILE UPDATES ====================
  /// Updates officer fields (department/branch, phone, position, etc.) via
  /// PATCH /api/officers. Only include the fields you want changed — the
  /// backend only updates keys that are present in the body.
  /// ⚠️ Admin-gated server-side (requires Authorization: Bearer
  /// <admin_token>) — this client has no admin login flow, so calling
  /// this as a regular officer will reliably fail with 401 "Admin
  /// authorization required". Returns enough detail (statusCode/message)
  /// for the caller to show *that* reason specifically, instead of a
  /// generic failure.
  Future<ProfileUpdateResult> updateOfficerProfile({
    required String officerId,
    String? department,
    String? position,
    String? phoneNumber,
    String? fullName,
    String? email,
  }) async {
    final payload = <String, dynamic>{
      "officer_id": officerId,
      if (department != null) "department": department,
      if (position != null) "position": position,
      if (phoneNumber != null) "phone_number": phoneNumber,
      if (fullName != null) "full_name": fullName,
      if (email != null) "email": email,
    };

    try {
      final response = await http.patch(
        Uri.parse("$_baseUrl/officers"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );

      final data = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && data["code"] == "000") {
        AppLog.i("AuthService", "✅ Officer profile updated: $officerId");
        return ProfileUpdateResult(success: true, statusCode: response.statusCode);
      }

      final message = data["message"]?.toString();
      if (kDebugMode) {
        AppLog.e("AuthService", "❌ Failed to update officer profile (${response.statusCode}): ${message ?? "unknown error"}");
      }
      return ProfileUpdateResult(
        success: false,
        statusCode: response.statusCode,
        message: message,
      );
    } catch (e) {
      AppLog.e("AuthService", "❌ Error updating officer profile: $e");
      return ProfileUpdateResult(success: false, message: e.toString());
    }
  }
 
 
  // ==================== BIOMETRIC AUTHENTICATION ====================

  Future<void> enableBiometrics(String username) async {
    try {
      await _storage.write(key: _biometricEnabledKey, value: 'true');
      await _storage.write(key: _biometricOwnerKey, value: username);
      AppLog.i("AuthService", "✅ Biometrics enabled for $username");
    } catch (e) {
      AppLog.e("AuthService", "❌ Error enabling biometrics: $e");
    }
  }

  Future<bool> isBiometricEnabled() async {
    try {
      final value = await _storage.read(key: _biometricEnabledKey);
      return value == 'true';
    } catch (e) {
      AppLog.e("AuthService", "❌ Error checking biometric status: $e");
      return false;
    }
  }

  Future<bool> isBiometricOwner(String username) async {
    try {
      final owner = await _storage.read(key: _biometricOwnerKey);
      return owner != null && owner == username;
    } catch (e) {
      AppLog.e("AuthService", "❌ Error checking biometric owner: $e");
      return false;
    }
  }

  Future<bool> canUseBiometrics(String username) async {
    try {
      final isEnabled = await isBiometricEnabled();
      if (!isEnabled) return false;

      final isOwner = await isBiometricOwner(username);
      return isOwner && await hasStoredCredentials();
    } catch (e) {
      AppLog.e("AuthService", "❌ Error checking biometric usage: $e");
      return false;
    }
  }

  // ==================== CREDENTIAL STORAGE ====================

  Future<void> saveCredentials(String username, String password) async {
    try {
      await _storage.write(key: _secureUsernameKey, value: username);
      await _storage.write(key: _securePasswordKey, value: password);
      AppLog.i("AuthService", "✅ Credentials saved securely");
    } catch (e) {
      AppLog.e("AuthService", "❌ Error saving credentials: $e");
    }
  }

  Future<Map<String, String>?> getStoredCredentials() async {
    try {
      final username = await _storage.read(key: _secureUsernameKey);
      final password = await _storage.read(key: _securePasswordKey);

      if (username != null && password != null) {
        return {'username': username, 'password': password};
      }
    } catch (e) {
      AppLog.e("AuthService", "❌ Error retrieving credentials: $e");
    }
    return null;
  }

  Future<bool> hasStoredCredentials() async {
    try {
      final username = await _storage.read(key: _secureUsernameKey);
      return username != null && username.isNotEmpty;
    } catch (e) {
      AppLog.e("AuthService", "❌ Error checking stored credentials: $e");
      return false;
    }
  }

  Future<void> clearStoredCredentials() async {
    try {
      await _storage.deleteAll();
      AppLog.i("AuthService", "✅ All credentials cleared");
    } catch (e) {
      AppLog.e("AuthService", "❌ Error clearing credentials: $e");
    }
  }

  // ==================== PRIVATE HELPER METHODS ====================

  /// Flattens the login response into one consistent profile map.
  /// The real API nests most useful fields under data.directory
  /// (id, face_image_url, position, phone_number, is_active) while
  /// data itself only duplicates name/username/email/department/
  /// officer_id. Both layers get merged here so nothing is lost.
  Map<String, dynamic> _flattenProfile(
      Map<String, dynamic> loginData, String fallbackUsername) {
    final top = (loginData['data'] is Map)
        ? loginData['data'] as Map<String, dynamic>
        : <String, dynamic>{};
    final dir = (top['directory'] is Map)
        ? top['directory'] as Map<String, dynamic>
        : <String, dynamic>{};

    return {
      "id": dir['id'],
      "officerId": top['officer_id'] ?? dir['officer_id'] ?? fallbackUsername,
      "username": top['username'] ?? fallbackUsername,
      "email": top['email'] ?? dir['email'] ?? "$fallbackUsername@gis.gov.gh",
      "fullName": top['name'] ?? dir['full_name'] ?? fallbackUsername,
      "department": top['department'] ?? dir['department'],
      "position": dir['position'],
      "phoneNumber": dir['phone_number'],
      "faceImageUrl": (dir['face_image_url'] is String &&
              (dir['face_image_url'] as String).isNotEmpty)
          ? dir['face_image_url']
          : null,
      "isActive": dir['is_active'],
      "role": top['role'] ?? dir['role'] ?? 'officer',
      // Present only for admins — the bearer token for /api/officers,
      // /api/auth/forgot-password, etc. Expires 12h after login.
      "adminToken": top['admin_token'],
    };
  }

  /// Generate and store JWT-like token
  Future<void> _generateAndStoreToken(
      Map<String, dynamic> loginData, String username) async {
    try {
      final profile = _flattenProfile(loginData, username);

      final now = DateTime.now();
      final expiry = now.add(const Duration(hours: 24));

      final userInfo = {
        ...profile,
        "loginTime": now.toIso8601String(),
        "expiryTime": expiry.toIso8601String(),
      };

      final encodedToken = base64Encode(utf8.encode(jsonEncode(userInfo)));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, encodedToken);

      AppLog.i("AuthService", "✅ Token generated (expires at $expiry)");
    } catch (e) {
      AppLog.e("AuthService", "❌ Error generating token: $e");
    }
  }

  /// Store the session/profile locally from the login response directly —
  /// no extra network round trip needed since login already returns
  /// everything.
  Future<void> _storeSession(
      Map<String, dynamic> loginData, String username) async {
    try {
      final profile = _flattenProfile(loginData, username);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userKey, jsonEncode(profile));
      AppLog.i("AuthService", "✅ Session stored");
    } catch (e) {
      AppLog.w("AuthService", "⚠️ Session store error: $e");
    }
  }
}