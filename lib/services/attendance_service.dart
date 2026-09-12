import 'dart:convert';
import 'dart:io';
import 'dart:math' show sin, cos, sqrt, atan2;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:gis_attendance/config/app_config.dart';
import 'package:gis_attendance/services/auth_service.dart';
import 'package:gis_attendance/services/api_result.dart';
import 'package:gis_attendance/utils/app_log.dart';
// import '../models/AttendanceRequest.dart';

class AttendanceResult {
  final bool ok;
  final String message;
  final Map<String, dynamic>? data;
  AttendanceResult(this.ok, this.message, {this.data});
}

class RequestResult {
  final bool ok;
  final String message;
  final Map<String, dynamic>? data;
  RequestResult(this.ok, this.message, {this.data});
}

class LocationResponse {
  final Map<String, double>? location;
  final String message;
  final bool success;

  LocationResponse({this.location, required this.message, required this.success});
}

class AttendanceService {
  static String get _baseUrl => AppConfig.apiBaseUrl;
  final AuthService _authService = AuthService();

  Future<Map<String, dynamic>?> getMyProfile() async {
    final hasToken = await _authService.hasValidToken();
    if (!hasToken) {
      AppLog.d("AttendanceService", "getMyProfile: No valid token found");
      return null;
    }

    final profile = await _authService.fetchLatestProfile();
    if (profile == null) {
      AppLog.d("AttendanceService", "getMyProfile: No cached or fetched profile available");
    }
    return profile;
  }

  Future<LocationResponse> getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return LocationResponse(success: false, message: "Location services are disabled.");
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return LocationResponse(success: false, message: "Location permissions are denied.");
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return LocationResponse(success: false, message: "Location permissions are permanently denied.");
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      return LocationResponse(
        success: true,
        message: "Location fetched successfully.",
        location: {"lat": position.latitude, "lng": position.longitude},
      );

    } catch (e) {
      AppLog.d("AttendanceService", "🚨 Exception in getCurrentLocation: $e");
      return LocationResponse(success: false, message: "An error occurred while fetching location.");
    }
  }

  double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371000; // m
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) *
            cos(_deg2rad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _deg2rad(double deg) => deg * (3.141592653589793 / 180.0);

  Future<List<Map<String, dynamic>>> getBranchLocations() async {
    final url = Uri.parse('$_baseUrl/user/location');
    final profile = await getMyProfile();

    if (profile == null || profile['username'] == null) {
      AppLog.e("AttendanceService", "❌ getBranchLocations: Could not get user profile or username. Aborting.");
      return [];
    }

    final String username = profile['username'];
    AppLog.i("AttendanceService", "✅ getBranchLocations: Fetching locations for user: $username");

    try {
      final response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
        },
        body: jsonEncode({"username": username}),
      );

      AppLog.i("AttendanceService", "✅ getBranchLocations: API response code: ${response.statusCode}");
      AppLog.i("AttendanceService", "✅ getBranchLocations: API response body: ${response.body}");

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);

        // ✅ 1. Check if 'data' is a Map (an object), not a List.
        if (responseData['success'] == true && responseData['data'] is Map<String, dynamic>) {

          // ✅ 2. Extract the single location object.
          final Map<String, dynamic> locationData = responseData['data'];
          AppLog.i("AttendanceService", "✅ getBranchLocations: Successfully found a single location object.");

          // ✅ 3. Create the final object with the correct keys ('lat'/'lng').
          final branch = {
            // The API doesn't provide id or name for the single location, so we can omit or add defaults.
            'id': locationData['id'] ?? 0,
            'name': locationData['name'] ?? 'User Location',
            'latitude': double.tryParse(locationData['latitude']?.toString() ?? '0.0'),
            'longitude': double.tryParse(locationData['longitude']?.toString() ?? '0.0'),
            'departments': locationData['departments'] ?? [],
          };

          // ✅ 4. Return the single branch wrapped in a List.
          return [branch];

        } else {
          AppLog.e("AttendanceService", "❌ getBranchLocations: Response was 200 OK, but 'success' was not true or 'data' was not a valid object.");
          return [];
        }
      } else {
        AppLog.e("AttendanceService", "❌ getBranchLocations: API request failed with status code ${response.statusCode}.");
        return [];
      }
    } catch (e) {
      AppLog.d("AttendanceService", "🚨 getBranchLocations: An exception occurred: $e");
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getAllBranchLocations() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/user/all-locations'),
        headers: {"Content-Type": "application/json"}
      );

      if (response.statusCode != 200) {
        return [];
      }

      final jsonBody = jsonDecode(response.body);

      if (jsonBody["success"] != true) {
        return [];
      }

      final List data = jsonBody["data"] ?? [];

      return data.map<Map<String, dynamic>>((b) {
        return {
          "id": b["id"],
          "name": b["name"],
          "lat": (b["lat"] as num).toDouble(),
          "lng": (b["lng"] as num).toDouble(),
        };
      }).toList();
    } catch (e) {
      AppLog.d("AttendanceService", "Error fetching branch locations: $e");
      return [];
    }
  }


  // Updated Attendance Service to match refactored backend

Future<AttendanceResult> clockIn({
  required String userId,
  String? comment,
}) async {
  try {
    final resp = await http.post(
      Uri.parse("$_baseUrl/attendance/clock-in"),
      headers: {
        "Content-Type": "application/json",
      },
      body: jsonEncode({
        "id": userId,  // ✅ Backend expects "id" not "userId"
        "comment": comment,
      }),
    );

    final body = resp.body.isEmpty ? null : jsonDecode(resp.body);
    AppLog.d("AttendanceService", "clockIn -> ${resp.statusCode} ${resp.body}");

    // ✅ Handle different response codes
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      Map<String, dynamic>? payload;
      if (body is Map<String, dynamic>) {
        payload = body["data"] ?? body;  // Extract data field if present
      }
      return AttendanceResult(true, "Clock-in successful", data: payload);
    }

    // ✅ Handle specific error cases
    if (resp.statusCode == 409) {
      // Already clocked in
      final err = (body is Map && body["message"] != null)
          ? body["message"].toString()
          : "You are already clocked in. Please clock out first.";
      return AttendanceResult(false, err, data: body is Map<String, dynamic> ? body : null);
    }

    if (resp.statusCode == 400) {
      final err = (body is Map && body["message"] != null)
          ? body["message"].toString()
          : "Invalid request. Officer ID is required.";
      return AttendanceResult(false, err, data: body is Map<String, dynamic> ? body : null);
    }

    // Generic error
    final err = (body is Map && body["message"] != null)
        ? body["message"].toString()
        : "Failed to clock in";
    return AttendanceResult(false, err, data: body is Map<String, dynamic> ? body : null);
  } catch (e, st) {
    AppLog.e("AttendanceService", "clockIn failed", e, st);
    return AttendanceResult(false, describeNetworkError(e));
  }
}

Future<AttendanceResult> clockOut({
  required String userId,  // ✅ Changed from attendanceId
  String? comment,
}) async {
  final token = await _authService.getToken();

  try {
    final resp = await http.post(
      Uri.parse("$_baseUrl/attendance/clock-out"),
      headers: {
        "Content-Type": "application/json",
        if (token != null) "Authorization": "Bearer $token",
      },
      body: jsonEncode({
        "id": userId,  // ✅ Backend finds open attendance by officer_id + date
        "comment": comment,
      }),
    );

    final body = resp.body.isEmpty ? null : jsonDecode(resp.body);
    AppLog.d("AttendanceService", "clockOut -> ${resp.statusCode} ${resp.body}");

    // ✅ Handle different response codes
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      Map<String, dynamic>? payload;
      if (body is Map<String, dynamic>) {
        payload = body["data"] ?? body;  // Extract data field if present
      }
      return AttendanceResult(true, "Clock-out successful", data: payload);
    }

    // ✅ Handle specific error cases
    if (resp.statusCode == 400) {
      final err = (body is Map && body["message"] != null)
          ? body["message"].toString()
          : "No open attendance found. Please clock in first.";
      return AttendanceResult(false, err, data: body is Map<String, dynamic> ? body : null);
    }

    if (resp.statusCode == 401 || resp.statusCode == 403) {
      return AttendanceResult(false, "Unauthorized. Please log in again.");
    }

    // Generic error
    final err = (body is Map && body["message"] != null)
        ? body["message"].toString()
        : "Failed to clock out";
    return AttendanceResult(false, err, data: body is Map<String, dynamic> ? body : null);
  } catch (e, st) {
    AppLog.e("AttendanceService", "clockOut failed", e, st);
    return AttendanceResult(false, describeNetworkError(e));
  }
}

Future<List<Map<String, dynamic>>> getHistory({
  required String userId,
}) async {
  final token = await _authService.getToken();
  try {
    // officer_id contains "/" (e.g. "P/012/2025") — encode it so it stays
    // one path segment instead of being routed as /history/P/012/2025 (404).
    final uri = Uri.parse(
        "$_baseUrl/attendance/history/${Uri.encodeComponent(userId)}");

    final resp = await http.get(
      uri,
      headers: {
        "Content-Type": "application/json",
        if (token != null) "Authorization": "Bearer $token",
      },
    );

    AppLog.d("AttendanceService", "history GET -> ${resp.statusCode}, historyData: ${resp.body}");

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final body = resp.body.isEmpty ? null : jsonDecode(resp.body);

      // Case 1: bare array response
      if (body is List) {
        return body
            .cast<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }

      // Case 2: wrapped response { "code": "...", "data": ... }
      if (body is Map) {
        final data = body["data"];

        // data is a list of records
        if (data is List) {
          return data
              .cast<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }

        // data is a single record object (your current backend response)
        if (data is Map) {
          return [Map<String, dynamic>.from(data)];
        }

        // fallback: "records" field instead of "data"
        if (body["records"] is List) {
          return (body["records"] as List)
              .cast<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }

      AppLog.d("AttendanceService", "history: unrecognized response shape, returning empty list");
    } else if (resp.statusCode == 401 || resp.statusCode == 403) {
      AppLog.d("AttendanceService", "Unauthorized: Token may be expired");
    } else if (resp.statusCode == 404) {
      AppLog.d("AttendanceService", "No attendance history found for user");
    }
  } catch (e) {
    AppLog.d("AttendanceService", "history error: $e");
  }
  return <Map<String, dynamic>>[];
}

/// 1:1 face verification — checks the captured frame against THIS
/// officer's own registered face via POST /api/verify { id, imageBase64 }.
/// Does not touch attendance: on a match the caller runs the normal
/// clockIn()/clockOut(). `ok` is true only when the face matched.
Future<AttendanceResult> verifyFace({
  required String officerId,
  required File imageFile,
}) async {
  try {
    final bytes = await imageFile.readAsBytes();
    final imageBase64 = "data:image/jpeg;base64,${base64Encode(bytes)}";

    final resp = await http
        .post(
          Uri.parse("$_baseUrl/verify"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"id": officerId, "imageBase64": imageBase64}),
        )
        .timeout(const Duration(seconds: 30));

    AppLog.d("AttendanceService", "verifyFace -> ${resp.statusCode} ${resp.body}");

    final body = resp.body.isEmpty
        ? <String, dynamic>{}
        : (jsonDecode(resp.body) as Map<String, dynamic>);

    if (resp.statusCode == 200 && body["success"] == true) {
      final isMatch = body["is_match"] == true;
      final conf = body["confidence"];
      return AttendanceResult(
        isMatch,
        isMatch
            ? "Identity verified"
            : "Face doesn't match your profile"
                "${conf != null ? " (confidence: $conf)" : ""}. Try again.",
        data: body,
      );
    }

    // No face detected, no registered face, server error, etc.
    final msg = (body["details"] ?? body["error"] ?? body["message"] ??
            "Verification failed (${resp.statusCode})")
        .toString();
    return AttendanceResult(false, msg, data: body);
  } catch (e, st) {
    AppLog.e("AttendanceService", "verifyFace failed", e, st);
    return AttendanceResult(false, describeNetworkError(e));
  }
}

// Face-based clock in/out — POST /api/attendance/check (1:N faceset
// search). Superseded by verifyFace() (1:1) for the attendance flow; kept
// for any caller that still needs identify-then-record in one call.
Future<AttendanceResult> checkFace({
  required File imageFile,
  required String action, // 'clock_in' or 'clock_out'
  String? location,
}) async {
  try {
    final request = http.MultipartRequest(
      "POST",
      Uri.parse("$_baseUrl/attendance/check"),
    )
      ..fields["action"] = action
      ..files.add(await http.MultipartFile.fromPath("image", imageFile.path));

    if (location != null && location.isNotEmpty) {
      request.fields["location"] = location;
    }

    final streamedResponse = await request.send();
    final resp = await http.Response.fromStream(streamedResponse);

    AppLog.d("AttendanceService", "checkFace -> ${resp.statusCode} ${resp.body}");

    final body = resp.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(resp.body) as Map<String, dynamic>;

    final ok = resp.statusCode >= 200 &&
        resp.statusCode < 300 &&
        body["success"] == true;

    final message = body["message"]?.toString() ??
        (ok ? "Face verified" : "Face verification failed");

    return AttendanceResult(ok, message, data: body);
  } catch (e, st) {
    AppLog.e("AttendanceService", "checkFace failed", e, st);
    return AttendanceResult(false, describeNetworkError(e));
  }
}

  Future<bool> SendEmail(String to, String subject, String message) async{
    final url = Uri.parse("$_baseUrl/notification/send-email");

    try{
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "to": to,
          "subject": subject,
          "message": message
        }),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return body['ok'] == true;
      } else {
        AppLog.d("AttendanceService", "Send Mail failed: ${response.statusCode}");
        return false;
      }
    } catch (e) {
      AppLog.d("AttendanceService", "Exception during phone verification: $e");
      return false;
    }
  }

  // Note: there is no /api/auth/admin-email route on the backend (see
  // docs/API.md) — a GetAdminEmail() here calling it always 404'd and was
  // unused. Removed rather than kept as dead/broken code; re-add once the
  // backend actually exposes an endpoint for this.

  Future<num> GetAllowedDistance() async{
    final url = Uri.parse('$_baseUrl/user/allowed-distance');

    try {
      final response = await http.get(
        url,
        headers: {"Content-Type": "application/json"},
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        AppLog.d("AttendanceService", "Attendance Body: ${response.body}");
        return body['allowedDistance'];

      } else {
        AppLog.d("AttendanceService", "Failed to get Allowed Distance: ${response.statusCode}");
        return 50;
      }
    } catch (e) {
      AppLog.d("AttendanceService", "Exception getting Allowed Distance: $e");
      return 50;
    }
  }
}