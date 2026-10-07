import 'package:flutter/material.dart';

/// Shared presentation bits for notifications (used by the bell dropdown
/// and the notifications page so icons/colours stay consistent).
abstract class NotificationUi {
  static IconData iconFor(String category) {
    switch (category) {
      case 'Staff Announcement':
        return Icons.campaign_rounded;
      case 'Security':
        return Icons.shield_outlined;
      case 'Attendance':
        return Icons.timelapse_rounded;
      case 'Broadcast':
        return Icons.sms_outlined;
      case 'Roster':
        return Icons.picture_as_pdf_outlined;
      case 'Test':
        return Icons.science_outlined;
      case 'System':
        return Icons.settings_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  static Color colorFor(String category) {
    switch (category) {
      case 'Staff Announcement':
        return const Color(0xFF2E4D2A);
      case 'Security':
        return const Color(0xFFD63031);
      case 'Attendance':
        return const Color(0xFF1FAA53);
      case 'Broadcast':
        return const Color(0xFF9A7B0A);
      case 'Roster':
        return const Color(0xFF6C5CE7);
      case 'Test':
        return const Color(0xFF636E72);
      default:
        return const Color(0xFF2E4D2A);
    }
  }

  static Color tintFor(String category) {
    switch (category) {
      case 'Staff Announcement':
        return const Color(0xFFE3EAE1);
      case 'Security':
        return const Color(0xFFFBE6E6);
      case 'Attendance':
        return const Color(0xFFE1F9EC);
      case 'Broadcast':
        return const Color(0xFFFBF1D8);
      case 'Roster':
        return const Color(0xFFEDEBFF);
      case 'Test':
        return const Color(0xFFF1F2F4);
      default:
        return const Color(0xFFE3EAE1);
    }
  }

  /// "Just now", "5m ago", "3h ago", "Yesterday", "Mar 4".
  static String relativeTime(DateTime ts) {
    final now = DateTime.now();
    final diff = now.difference(ts);
    if (diff.isNegative) return 'Just now';
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final m = months[ts.month - 1];
    return now.year == ts.year ? '$m ${ts.day}' : '$m ${ts.day}, ${ts.year}';
  }
}
