import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/notification_model.dart';
import '../services/notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  // GIS theme — matches the home screen's palette for a consistent brand feel.
  final Color gisDeepOlive = const Color(0xFF2E4D2A);
  final Color gisDarkBackground = const Color(0xFF142412);
  final Color ghanaGold = const Color(0xFFE1B12C);
  final Color goldText = const Color(0xFF8A6D1D);
  final Color darkCharcoal = const Color(0xFF1A2519);
  final Color lightGrayBg = const Color(0xFFF5F6F5);
  final Color mutedText = const Color(0xFF6E7A6C);
  final Color hairline = const Color(0xFFE7E9E4);
  final Color goldTint = const Color(0xFFFBF1D8);
  final Color oliveTint = const Color(0xFFE3EAE1);

  @override
  void initState() {
    super.initState();
    NotificationService.refreshNotifications();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightGrayBg,
      body: Column(
        children: [
          _buildModernHeader(),
          Expanded(
            child: ValueListenableBuilder<List<NotificationItem>>(
              valueListenable: NotificationService.notificationsNotifier,
              builder: (context, notifications, _) {
                if (notifications.isEmpty) {
                  return _buildEmptyState();
                }

                return RefreshIndicator(
                  onRefresh: () => NotificationService.refreshNotifications(),
                  color: gisDeepOlive,
                  child: ListView.builder(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    itemCount: notifications.length,
                    itemBuilder: (context, index) {
                      return GestureDetector(
                        onTap: () => _showNotificationDetails(
                            context, notifications[index]),
                        child: _buildNotificationCard(notifications[index]),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // NOTIFICATION DETAILS MODAL
  // ============================================================================

  void _showNotificationDetails(BuildContext context, NotificationItem item) {
    final bool isStaff = item.category == "Staff Announcement";
    final dateStr =
    DateFormat('MMMM d, yyyy • hh:mm a').format(item.timestamp);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(24),
                      children: [
                        _buildBadge(item, isStaff),
                        const SizedBox(height: 20),
                        Text(
                          item.title,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: darkCharcoal,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(Icons.access_time,
                                size: 14, color: mutedText),
                            const SizedBox(width: 6),
                            Text(dateStr,
                                style: TextStyle(
                                    color: mutedText, fontSize: 13)),
                          ],
                        ),
                        Divider(height: 40, color: hairline),
                        Text(
                          item.message,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.6,
                            color: Colors.grey.shade800,
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ============================================================================
  // HEADER WITH BUTTONS
  // ============================================================================

  Widget _buildModernHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 50, 20, 30),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [gisDarkBackground, gisDeepOlive],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: gisDeepOlive.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.arrow_back_ios_new,
                      color: ghanaGold, size: 18),
                ),
              ),
              Expanded(
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.notifications_rounded, color: ghanaGold, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        "Notifications",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              // ========== TEST BUTTON ==========
              // IconButton(
              //   tooltip: 'Send Test Notification',
              //   icon: const Icon(Icons.notification_add, color: Colors.white),
              //   onPressed: () async {
              //     debugPrint(
              //         '👆 [UI] User tapped Test Notification button');
              //     _showTestNotificationDialog();
              //   },
              // ),
              // ========== CLEAR ALL BUTTON ==========
              IconButton(
                tooltip: 'Clear All Notifications',
                icon: Icon(Icons.delete_sweep, color: ghanaGold),
                onPressed: () async {
                  debugPrint('👆 [UI] User tapped Clear All button');
                  bool? confirm = await showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      title: const Text("Clear History", style: TextStyle(fontWeight: FontWeight.w700)),
                      content: const Text(
                          "Are you sure you want to delete all notifications?"),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text("Cancel", style: TextStyle(color: Colors.grey.shade600)),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text("Delete", style: TextStyle(color: Color(0xFFD63031), fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    debugPrint(
                        '👆 [UI] User confirmed clear all, calling clearNotifications()');
                    await NotificationService.clearNotifications();
                  }
                },
              ),
              // ========== REFRESH BUTTON ==========
              IconButton(
                tooltip: 'Refresh Notifications',
                icon: Icon(Icons.refresh, color: ghanaGold),
                onPressed: () async {
                  debugPrint('👆 [UI] User tapped Refresh button');
                  await NotificationService.refreshNotifications();
                },
              ),
              const SizedBox(width: 1),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            "Stay updated with ADB staff news and your app activity",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // TEST NOTIFICATION DIALOG
  // ============================================================================

  void _showTestNotificationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Send Test Notification", style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text(
          "This will send a test notification to your device.\n\n"
              "🔍 Check the console logs for detailed debugging information.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel", style: TextStyle(color: Colors.grey.shade600)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              debugPrint(
                  '✅ [Dialog] User confirmed test, calling TestNotification()');
              await NotificationService.TestNotification();
            },
            child: Text("Send Test", style: TextStyle(color: gisDeepOlive, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // NOTIFICATION CARD
  // ============================================================================

  Widget _buildNotificationCard(NotificationItem item) {
    final bool isStaff = item.category == "Staff Announcement";
    final dateStr =
    DateFormat('MMM d, yyyy • hh:mm a').format(item.timestamp);
    final Color accent = isStaff ? gisDeepOlive : ghanaGold;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: hairline),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                width: 5,
                color: accent,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: isStaff ? oliveTint : goldTint,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isStaff
                                  ? Icons.campaign_rounded
                                  : Icons.sensors_rounded,
                              size: 13,
                              color: isStaff ? gisDeepOlive : goldText,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            item.category.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                              color: isStaff ? gisDeepOlive : goldText,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            dateStr,
                            style: TextStyle(
                                fontSize: 10, color: mutedText),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: darkCharcoal),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: Colors.grey.shade700),
                      ),
                      if (!item.isRead) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: ghanaGold,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'New',
                              style: TextStyle(
                                fontSize: 11,
                                color: goldText,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // EMPTY STATE
  // ============================================================================

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: oliveTint,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.notifications_none_outlined,
                size: 44, color: gisDeepOlive),
          ),
          const SizedBox(height: 20),
          Text("No notifications yet",
              style: TextStyle(
                  color: darkCharcoal,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text("When you have updates, they'll appear here",
              style: TextStyle(color: mutedText, fontSize: 13)),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () {
              debugPrint(
                  '👆 [Empty State] User tapped send test from empty state');
              _showTestNotificationDialog();
            },
            icon: const Icon(Icons.notification_add),
            label: const Text('Send Test Notification'),
            style: ElevatedButton.styleFrom(
              backgroundColor: gisDeepOlive,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // BADGE WIDGET
  // ============================================================================

  Widget _buildBadge(NotificationItem item, bool isStaff) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isStaff ? oliveTint : goldTint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        item.category,
        style: TextStyle(
          color: isStaff ? gisDeepOlive : goldText,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}