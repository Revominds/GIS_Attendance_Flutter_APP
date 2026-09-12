class NotificationItem {
  final int id;
  final String title;
  final String message;
  final String category;
  final DateTime timestamp;
  bool isRead; // Added this

  NotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.category,
    required this.timestamp,
    this.isRead = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'message': message,
    'category': category,
    'timestamp': timestamp.toIso8601String(),
  };

  factory NotificationItem.fromJson(Map<String, dynamic> json, {String? forcedCategory}) {
    return NotificationItem(
      id: json['id'] ?? 0,
      title: json['title'] ?? 'No Title',
      message: json['message'] ?? '',
      category: forcedCategory ?? json['category'] ?? 'In-App Notification',
      // Parsing the API date format: "2025-12-29T10:16:06.000Z"
      timestamp: DateTime.parse(json['created_at'] ?? json['timestamp'] ?? DateTime.now().toIso8601String()),
    );
  }
}