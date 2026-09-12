import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:gis_attendance/config/app_config.dart';
import 'package:gis_attendance/services/api_result.dart';
import 'package:gis_attendance/services/auth_service.dart';
import 'package:gis_attendance/utils/app_log.dart';

/// Admin-only operations: officer management, registration approvals,
/// password resets and attendance oversight. Every call attaches the
/// admin bearer token from [AuthService.getAdminToken]; if there isn't a
/// valid one the call fails fast with a clear message instead of a 401.
class AdminService {
  static String get _base => AppConfig.apiBaseUrl;
  final AuthService _auth = AuthService();

  static const Duration _timeout = Duration(seconds: 20);

  Future<Map<String, String>?> _authHeaders() async {
    final token = await _auth.getAdminToken();
    if (token == null) return null;
    return {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    };
  }

  ApiResult<T> _noToken<T>() => ApiResult.failure(
        "Your admin session has expired. Log out and sign in again.",
      );

  /// Runs [send], turning transport exceptions and non-2xx responses into
  /// an [ApiResult] via the shared mappers. [parse] pulls the payload out
  /// of a success body.
  Future<ApiResult<T>> _run<T>(
    String tag,
    Future<http.Response> Function() send,
    T Function(dynamic body) parse,
  ) async {
    http.Response resp;
    try {
      resp = await send().timeout(_timeout);
    } catch (e, st) {
      AppLog.e("AdminService", "$tag failed", e, st);
      return ApiResult.failure(describeNetworkError(e));
    }

    dynamic body;
    try {
      body = resp.body.isEmpty ? null : jsonDecode(resp.body);
    } catch (_) {
      body = null;
    }

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return ApiResult.success(parse(body),
          message: serverMessageOf(body) ?? "Success");
    }

    AppLog.w("AdminService", "$tag HTTP ${resp.statusCode}: ${resp.body}");
    return ApiResult.failure(
      describeHttpError(resp.statusCode, serverMessageOf(body)),
      statusCode: resp.statusCode,
    );
  }

  List<Map<String, dynamic>> _asList(dynamic body) {
    final data = (body is Map) ? body['data'] : body;
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  // ---------------------------------------------------------------- officers

  /// All officers, newest-looking first is not guaranteed by the API, so
  /// callers sort as they see fit. GET /api/officers is not token-gated
  /// but we keep it here for a single admin surface.
  Future<ApiResult<List<Map<String, dynamic>>>> listOfficers() {
    return _run(
      "listOfficers",
      () => http.get(Uri.parse("$_base/officers")),
      _asList,
    );
  }

  Future<ApiResult<void>> createOfficer({
    required String officerId,
    required String fullName,
    required String email,
    String? department,
    String? position,
    String? phoneNumber,
    bool isActive = true,
  }) async {
    final headers = await _authHeaders();
    if (headers == null) return _noToken();
    return _run(
      "createOfficer",
      () => http.post(
        Uri.parse("$_base/officers"),
        headers: headers,
        body: jsonEncode({
          "officer_id": officerId,
          "full_name": fullName,
          "email": email,
          "is_active": isActive,
          if (department != null && department.isNotEmpty) "department": department,
          if (position != null && position.isNotEmpty) "position": position,
          if (phoneNumber != null && phoneNumber.isNotEmpty)
            "phone_number": phoneNumber,
        }),
      ),
      (_) {},
    );
  }

  Future<ApiResult<void>> updateOfficer({
    required String officerId,
    String? fullName,
    String? email,
    String? department,
    String? position,
    String? phoneNumber,
  }) async {
    final headers = await _authHeaders();
    if (headers == null) return _noToken();
    return _run(
      "updateOfficer",
      () => http.patch(
        Uri.parse("$_base/officers"),
        headers: headers,
        body: jsonEncode({
          "officer_id": officerId,
          if (fullName != null) "full_name": fullName,
          if (email != null) "email": email,
          if (department != null) "department": department,
          if (position != null) "position": position,
          if (phoneNumber != null) "phone_number": phoneNumber,
        }),
      ),
      (_) {},
    );
  }

  Future<ApiResult<void>> setOfficerActive(String officerId, bool active) async {
    final headers = await _authHeaders();
    if (headers == null) return _noToken();
    return _run(
      "setOfficerActive",
      () => http.patch(
        Uri.parse("$_base/officers"),
        headers: headers,
        body: jsonEncode({"officer_id": officerId, "is_active": active}),
      ),
      (_) {},
    );
  }

  Future<ApiResult<void>> deleteOfficer(String officerId) async {
    final headers = await _authHeaders();
    if (headers == null) return _noToken();
    return _run(
      "deleteOfficer",
      () => http.delete(
        Uri.parse(
            "$_base/officers?officer_id=${Uri.encodeQueryComponent(officerId)}"),
        headers: headers,
      ),
      (_) {},
    );
  }

  Future<ApiResult<void>> resetPassword(
      String officerId, String newPassword) async {
    final headers = await _authHeaders();
    if (headers == null) return _noToken();
    return _run(
      "resetPassword",
      () => http.post(
        Uri.parse("$_base/auth/forgot-password"),
        headers: headers,
        body: jsonEncode({
          "officer_id": officerId,
          "new_password": newPassword,
        }),
      ),
      (_) {},
    );
  }

  // ------------------------------------------------------------- attendance

  /// Every attendance row for today, across officers (admin-gated).
  Future<ApiResult<List<Map<String, dynamic>>>> todayAttendance() async {
    final headers = await _authHeaders();
    if (headers == null) return _noToken();
    return _run(
      "todayAttendance",
      () => http.get(Uri.parse("$_base/attendance/today"), headers: headers),
      _asList,
    );
  }

  /// All officers' attendance history from attendance_summary, newest
  /// first (admin-gated). Optional filters: one officer, one date, or a
  /// date range; paginated.
  Future<ApiResult<List<Map<String, dynamic>>>> allAttendance({
    String? officerId,
    String? date,
    String? from,
    String? to,
    int limit = 100,
    int offset = 0,
  }) async {
    final headers = await _authHeaders();
    if (headers == null) return _noToken();
    final q = <String, String>{
      "limit": "$limit",
      "offset": "$offset",
      if (officerId != null && officerId.isNotEmpty) "officer_id": officerId,
      if (date != null && date.isNotEmpty) "date": date,
      if (from != null && from.isNotEmpty) "from": from,
      if (to != null && to.isNotEmpty) "to": to,
    };
    final uri = Uri.parse("$_base/attendance/summary").replace(queryParameters: q);
    return _run("allAttendance", () => http.get(uri, headers: headers), _asList);
  }

  /// One officer's full attendance history (raw rows, newest first).
  Future<ApiResult<List<Map<String, dynamic>>>> officerAttendance(
      String officerId) {
    return _run(
      "officerAttendance",
      () => http.get(Uri.parse(
          "$_base/attendance/history/${Uri.encodeComponent(officerId)}")),
      (body) {
        // 404 "no history" comes back as an error result already; here we
        // only handle the success shape.
        return _asList(body);
      },
    );
  }

  /// Close an open attendance row (admin correction).
  Future<ApiResult<void>> forceClockOut(String attendanceId) async {
    final headers = await _authHeaders();
    if (headers == null) return _noToken();
    return _run(
      "forceClockOut",
      () => http.patch(
        Uri.parse("$_base/attendance/history/$attendanceId"),
        headers: headers,
        body: jsonEncode({"attendance_id": attendanceId}),
      ),
      (_) {},
    );
  }

  Future<ApiResult<void>> deleteAttendance(String attendanceId) async {
    final headers = await _authHeaders();
    if (headers == null) return _noToken();
    return _run(
      "deleteAttendance",
      () => http.delete(
        Uri.parse(
            "$_base/attendance/history/$attendanceId?id=${Uri.encodeQueryComponent(attendanceId)}"),
        headers: headers,
      ),
      (_) {},
    );
  }
}
