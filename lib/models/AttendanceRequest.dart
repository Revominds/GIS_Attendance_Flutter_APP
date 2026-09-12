enum RequestStatus { pending, approved, rejected }

class AttendanceRequest {
  final String id;
  final dynamic userId;
  final dynamic username;
  final String requestDatetime;
  final String requestType;
  final String? location;
  final String reason;
  final RequestStatus status;
  final dynamic approved_by;
  final dynamic approved_at;
  final dynamic created_at;

  AttendanceRequest({
  required this.id,
  this.userId,
  this.username,
  required this.requestDatetime,
  required this.requestType,
  this.location,
  required this.reason,
  required this.status,
  this.approved_by,
  this.approved_at,
  this.created_at,
  });

  factory AttendanceRequest.fromJson(Map<String, dynamic> json) {
    try {
      // Print the JSON so you can see what is null
      print("Parsing JSON: $json");
      return AttendanceRequest(
        id: json['id']?.toString() ?? '',
        userId:json['id'],
        username:json['username'],
        requestDatetime: json['request_datetime'] ?? DateTime.now().toIso8601String(),
        requestType: json['request_type']?? ' ',
        location: json['client_location'] as String? ?? json['branch_name'] as String,
        reason: json['reason'] as String? ?? ' ',
        status: _parseStatus(json['status']?.toString()),
        approved_by: json['approved_by'] ?? ' ',
        approved_at: json['approved_at'] ?? ' ',
        created_at: json['created_at']
      );
    } catch (e) {
      print("Error parsing this specific JSON: $e");
      rethrow;
    }
  }

  static RequestStatus _parseStatus(String? status) {
    switch (status?.toLowerCase()) {
      case 'approved': return RequestStatus.approved;
      case 'rejected': return RequestStatus.rejected;
      default: return RequestStatus.pending;
    }
  }
}