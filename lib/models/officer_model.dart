class OfficerModel {
  final String id;
  final String officerId;
  final String fullName;
  final String email;
  final String? department;
  final String? position;
  final String? phoneNumber;
  final bool isActive;

  OfficerModel({
    required this.id,
    required this.officerId,
    required this.fullName,
    required this.email,
    this.department,
    this.position,
    this.phoneNumber,
    this.isActive = true,
  });

  factory OfficerModel.fromJson(Map<String, dynamic> json) {
    return OfficerModel(
      id: json['id'] ?? '',
      officerId: json['officer_id'] ?? '',
      fullName: json['full_name'] ?? '',
      email: json['email'] ?? '',
      department: json['department'],
      position: json['position'],
      phoneNumber: json['phone_number'],
      isActive: json['is_active'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'officer_id': officerId,
      'full_name': fullName,
      'email': email,
      'department': department,
      'position': position,
      'phone_number': phoneNumber,
      'is_active': isActive,
    };
  }
}