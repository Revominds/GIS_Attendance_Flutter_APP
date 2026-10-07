// Broadcast messaging service — sends a message to many officers.
//
// NOTE (backend blocker, see doc/API.md): POST /api/notification/send-sms
// is currently non-functional server-side (ignores the request body and
// sends blanks). This client sends the CORRECT payload { to, message }
// per officer so it works the moment the backend is fixed, and returns a
// per-recipient result so the UI can show delivered vs failed.
// If you use an external gateway (Hubtel/Twilio/Africa's Talking), swap
// _sendOne() to hit that endpoint instead — the UI stays the same.
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:gis_attendance/config/app_config.dart';
import 'package:gis_attendance/utils/app_log.dart';

class BroadcastResult {
  final String officerId;
  final String phone;
  final bool ok;
  final String detail;
  BroadcastResult(this.officerId, this.phone, this.ok, this.detail);
}

class BroadcastSummary {
  final List<BroadcastResult> results;
  BroadcastSummary(this.results);
  int get sent => results.where((r) => r.ok).length;
  int get failed => results.where((r) => !r.ok).length;
}

class BroadcastService {
  static String get _base => AppConfig.apiBaseUrl;
  static const Duration _timeout = Duration(seconds: 15);

  static String _digits(String raw) =>
      raw.replaceAll(RegExp(r'[^0-9+]'), '');

  /// Resolve recipients from the officer list.
  /// [audience]: 'all' | 'active' | department name.
  static List<Map<String, dynamic>> resolveRecipients(
      List<Map<String, dynamic>> officers, String audience) {
    if (audience == 'active') {
      return officers
          .where((o) =>
              o['is_active'] == true ||
              '${o['is_active']}'.toLowerCase() == 'true' ||
              o['is_active'] == 1)
          .toList();
    }
    if (audience != 'all') {
      return officers
          .where((o) =>
              '${o['department'] ?? ''}'.toLowerCase() ==
              audience.toLowerCase())
          .toList();
    }
    return List.of(officers);
  }

  static List<String> distinctDepartments(
      List<Map<String, dynamic>> officers) {
    final set = <String>{};
    for (final o in officers) {
      final d = '${o['department'] ?? ''}'.trim();
      if (d.isNotEmpty) set.add(d);
    }
    return set.toList()..sort();
  }

  Future<BroadcastSummary> sendBroadcast({
    required List<Map<String, dynamic>> recipients,
    required String message,
    void Function(int done, int total)? onProgress,
  }) async {
    final out = <BroadcastResult>[];
    var done = 0;
    for (final r in recipients) {
      final id = '${r['officer_id'] ?? r['id'] ?? ''}';
      final phone = _digits('${r['phone_number'] ?? r['phone'] ?? ''}');
      if (phone.isEmpty) {
        out.add(BroadcastResult(id, '', false, 'No phone number'));
      } else {
        out.add(await _sendOne(id, phone, message));
      }
      done++;
      onProgress?.call(done, recipients.length);
    }
    return BroadcastSummary(out);
  }

  Future<BroadcastResult> _sendOne(
      String officerId, String phone, String message) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$_base/notification/send-sms'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'to': phone, 'message': message}),
          )
          .timeout(_timeout);
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return BroadcastResult(officerId, phone, true, 'Sent');
      }
      AppLog.w('BroadcastService',
          'SMS to $phone failed: ${resp.statusCode} ${resp.body}');
      return BroadcastResult(
          officerId, phone, false, 'Server ${resp.statusCode}');
    } catch (e, st) {
      AppLog.e('BroadcastService', 'SMS to $phone error', e, st);
      return BroadcastResult(officerId, phone, false, e.toString());
    }
  }
}
