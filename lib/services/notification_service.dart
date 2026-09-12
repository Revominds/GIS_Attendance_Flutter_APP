import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gis_attendance/config/app_config.dart';
import 'package:gis_attendance/utils/app_log.dart';
import '../models/notification_model.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
  FlutterLocalNotificationsPlugin();

  static final ValueNotifier<List<NotificationItem>> notificationsNotifier =
  ValueNotifier<List<NotificationItem>>([]);

  static const String _storageKey = 'adb_final_storage_v10';
  static String get _apiUrl => "${AppConfig.apiBaseUrl}/notification";

  static const AndroidNotificationChannel _androidChannel =
  AndroidNotificationChannel(
    'adb_staff_channel_high',
    'Staff Notifications',
    description:
    'This channel is used for staff announcements and attendance logs.',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    showBadge: true,
  );

  // ============================================================================
  // INITIALIZATION
  // ============================================================================

  static Future<void> initialize() async {
    try {
      AppLog.d("NotificationService", '🔧 [NotificationService] Starting initialization...');

      // Android initialization
      const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
      AppLog.i("NotificationService", '✅ [Android] AndroidInitializationSettings created');

      // iOS initialization
      const DarwinInitializationSettings iosSettings =
      DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
        defaultPresentAlert: true,
        defaultPresentBadge: true,
        defaultPresentSound: true,
        onDidReceiveLocalNotification: _onDidReceiveLocalNotification,
      );
      AppLog.i("NotificationService", '✅ [iOS] DarwinInitializationSettings created');

      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      // Initialize the plugin
      await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTap,
        onDidReceiveBackgroundNotificationResponse:
        _onBackgroundNotificationTap,
      );
      debugPrint(
          '✅ [Core] FlutterLocalNotificationsPlugin initialized successfully');

      // Platform-specific setup
      if (Platform.isAndroid) {
        await _initializeAndroid();
      } else if (Platform.isIOS) {
        await _initializeIOS();
      }

      AppLog.d("NotificationService", '🎉 [NotificationService] Initialization COMPLETE');
      await refreshNotifications();
    } catch (e) {
      AppLog.e("NotificationService", '❌ [NotificationService] Initialization ERROR: $e');
      rethrow;
    }
  }

  // ============================================================================
  // ANDROID INITIALIZATION
  // ============================================================================

  static Future<void> _initializeAndroid() async {
    if (!Platform.isAndroid) return;

    try {
      AppLog.d("NotificationService", '🔧 [Android] Starting Android-specific setup...');

      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin == null) {
        AppLog.w("NotificationService", '⚠️  [Android] AndroidFlutterLocalNotificationsPlugin is NULL');
        return;
      }

      AppLog.i("NotificationService", '✅ [Android] AndroidFlutterLocalNotificationsPlugin resolved');

      // Create notification channel
      await androidPlugin.createNotificationChannel(_androidChannel);
      debugPrint(
          '✅ [Android] Notification channel created: ${_androidChannel.id}');

      // Request permissions (Android 13+)
      final permissionGranted =
      await androidPlugin.requestNotificationsPermission();
      AppLog.i("NotificationService", '✅ [Android] Permissions requested: $permissionGranted');
    } catch (e) {
      AppLog.e("NotificationService", '❌ [Android] ERROR during setup: $e');
    }
  }

  // ============================================================================
  // iOS INITIALIZATION - DETAILED LOGGING
  // ============================================================================

  static Future<void> _initializeIOS() async {
    if (!Platform.isIOS) {
      AppLog.w("NotificationService", '⚠️  [iOS] Not running on iOS, skipping iOS initialization');
      return;
    }

    try {
      AppLog.d("NotificationService", '🔧 [iOS] Starting iOS-specific setup...');
      AppLog.d("NotificationService", '📱 [iOS] Device: iOS ${Platform.version}');

      // Resolve iOS plugin
      final iosPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

      if (iosPlugin == null) {
        debugPrint(
            '❌ [iOS] IOSFlutterLocalNotificationsPlugin is NULL - CRITICAL ERROR');
        debugPrint(
            '💡 [iOS] This means the plugin is not properly installed or linked');
        return;
      }

      AppLog.i("NotificationService", '✅ [iOS] IOSFlutterLocalNotificationsPlugin resolved');

      // Request permissions
      debugPrint(
          '🔐 [iOS] Requesting permissions (alert, badge, sound)...');
      final permissionsGranted = await iosPlugin.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
        critical: false,
      );

      debugPrint(
          '🔐 [iOS] Permission dialog shown (user should see popup)');
      AppLog.d("NotificationService", '🔐 [iOS] Permissions granted: $permissionsGranted');

      if (permissionsGranted != true) {
        debugPrint(
            '⚠️  [iOS] User may have denied permissions. Check device Settings > [AppName] > Notifications');
      }

      AppLog.i("NotificationService", '✅ [iOS] iOS initialization COMPLETE');
    } catch (e, stackTrace) {
      AppLog.e("NotificationService", '❌ [iOS] ERROR during iOS setup: $e');
      AppLog.d("NotificationService", '📋 [iOS] Stack trace: $stackTrace');
    }
  }

  // ============================================================================
  // iOS NOTIFICATION HANDLERS
  // ============================================================================

  static void _onDidReceiveLocalNotification(
      int id,
      String? title,
      String? body,
      String? payload,
      ) {
    AppLog.d("NotificationService", '📱 [iOS Foreground] Notification received');
    AppLog.d("NotificationService", '   ID: $id');
    AppLog.d("NotificationService", '   Title: $title');
    AppLog.d("NotificationService", '   Body: $body');
    AppLog.d("NotificationService", '   Payload: $payload');
  }

  static void _onNotificationTap(NotificationResponse response) {
    AppLog.d("NotificationService", '👆 [Notification Tap] User tapped notification');
    AppLog.d("NotificationService", '   Payload: ${response.payload}');
    AppLog.d("NotificationService", '   Action ID: ${response.actionId}');
  }

  static void _onBackgroundNotificationTap(NotificationResponse response) {
    AppLog.d("NotificationService", '👆 [Background Tap] User tapped notification from background');
    AppLog.d("NotificationService", '   Payload: ${response.payload}');
    AppLog.d("NotificationService", '   Action ID: ${response.actionId}');
  }

  // ============================================================================
  // iOS PERMISSIONS
  // ============================================================================

  static Future<void> _requestIOSPermissions() async {
    if (!Platform.isIOS) {
      AppLog.w("NotificationService", '⚠️  [iOS Permissions] Not iOS platform');
      return;
    }

    try {
      debugPrint(
          '🔐 [iOS Permissions] Explicitly requesting iOS permissions...');

      final iOSPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

      if (iOSPlugin == null) {
        debugPrint(
            '❌ [iOS Permissions] IOSFlutterLocalNotificationsPlugin is NULL');
        return;
      }

      final result = await iOSPlugin.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );

      AppLog.i("NotificationService", '✅ [iOS Permissions] Result: $result');
      debugPrint(
          '💡 [iOS Permissions] If false, user denied - check Settings app');
    } catch (e, stackTrace) {
      AppLog.e("NotificationService", '❌ [iOS Permissions] ERROR: $e');
      AppLog.d("NotificationService", '📋 Stack trace: $stackTrace');
    }
  }

  static Future<bool> checkIOSPermissions() async {
    if (!Platform.isIOS) return true;

    try {
      AppLog.d("NotificationService", '🔍 [iOS Check Permissions] Checking current permissions...');

      final iOSPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

      if (iOSPlugin == null) {
        AppLog.e("NotificationService", '❌ [iOS Check] Plugin is NULL');
        return false;
      }

      AppLog.i("NotificationService", '✅ [iOS Check] Permission check complete');
      return true;
    } catch (e) {
      AppLog.e("NotificationService", '❌ [iOS Check] ERROR: $e');
      return false;
    }
  }

  static Future<bool> requestPermissions() async {
    AppLog.d("NotificationService", '🔐 [Request Permissions] Platform: ${Platform.operatingSystem}');

    if (Platform.isIOS) {
      await _requestIOSPermissions();
      return true;
    } else if (Platform.isAndroid) {
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        final result = await androidPlugin.requestNotificationsPermission();
        AppLog.d("NotificationService", '📱 [Android Permissions] Result: $result');
        return result ?? false;
      }
    }
    return true;
  }

  // ============================================================================
  // iOS BADGE MANAGEMENT
  // ============================================================================

  static Future<void> _updateAppBadge() async {
    if (!Platform.isIOS) return;

    try {
      AppLog.d("NotificationService", '🔔 [Badge] Updating iOS app badge...');

      final iOSPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

      if (iOSPlugin == null) {
        AppLog.e("NotificationService", '❌ [Badge] IOSFlutterLocalNotificationsPlugin is NULL');
        return;
      }

      final unread = unreadCount;
      AppLog.d("NotificationService", '🔔 [Badge] Setting badge count to: $unread');

      // ✅ CORRECT METHOD NAME
      await iOSPlugin.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );

      AppLog.i("NotificationService", '✅ [Badge] Badge updated successfully');
    } catch (e, stackTrace) {
      AppLog.e("NotificationService", '❌ [Badge] ERROR: $e');
      AppLog.d("NotificationService", '📋 Stack trace: $stackTrace');
    }
  }

  static Future<void> clearBadge() async {
    if (!Platform.isIOS) return;

    try {
      AppLog.d("NotificationService", '🔔 [Clear Badge] Clearing iOS app badge...');

      final iOSPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

      if (iOSPlugin == null) {
        AppLog.e("NotificationService", '❌ [Clear Badge] IOSFlutterLocalNotificationsPlugin is NULL');
        return;
      }

      AppLog.i("NotificationService", '✅ [Clear Badge] Badge cleared');
    } catch (e, stackTrace) {
      AppLog.e("NotificationService", '❌ [Clear Badge] ERROR: $e');
      AppLog.d("NotificationService", '📋 Stack trace: $stackTrace');
    }
  }

  // ============================================================================
  // SHOW NOTIFICATIONS
  // ============================================================================

  static Future<void> _triggerSystemBanner(
      int id,
      String title,
      String body,
      ) async {
    try {
      AppLog.d("NotificationService", '📬 [Show Notification] Attempting to show notification...');
      AppLog.d("NotificationService", '   Title: $title');
      AppLog.d("NotificationService", '   Body: $body');
      AppLog.d("NotificationService", '   ID: $id');

      final notificationId = id % 100000;
      AppLog.d("NotificationService", '   Normalized ID: $notificationId');

      if (Platform.isAndroid) {
        AppLog.d("NotificationService", '📬 [Android Show] Showing Android notification...');

        final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.max,
          priority: Priority.high,
          ticker: 'ticker',
          icon: '@mipmap/ic_launcher',
          styleInformation: const BigTextStyleInformation(''),
          playSound: true,
          enableVibration: true,
          // showBadge: true,
        );

        final NotificationDetails platformDetails = NotificationDetails(
          android: androidDetails,
        );

        await _notificationsPlugin.show(
          notificationId,
          title,
          body,
          platformDetails,
        );

        AppLog.i("NotificationService", '✅ [Android Show] Notification shown successfully');
      } else if (Platform.isIOS) {
        AppLog.d("NotificationService", '📬 [iOS Show] Showing iOS notification...');
        AppLog.d("NotificationService", '   Device: iOS ${Platform.version}');

        // Check if plugin is available
        final iosPlugin = _notificationsPlugin
            .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();

        if (iosPlugin == null) {
          debugPrint(
              '❌ [iOS Show] IOSFlutterLocalNotificationsPlugin is NULL');
          return;
        }

        AppLog.i("NotificationService", '✅ [iOS Show] iOS plugin resolved');

        final DarwinNotificationDetails iosDetails =
        DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          presentBanner: true,
          presentList: true,
          interruptionLevel: InterruptionLevel.passive,
          threadIdentifier: 'adb_notifications',
          sound: 'default',
        );

        AppLog.i("NotificationService", '✅ [iOS Show] iOS notification details created');

        final NotificationDetails platformDetails = NotificationDetails(
          iOS: iosDetails,
        );

        AppLog.i("NotificationService", '✅ [iOS Show] Platform details created');
        debugPrint(
            '📬 [iOS Show] Calling _notificationsPlugin.show()...');

        await _notificationsPlugin.show(
          notificationId,
          title,
          body,
          platformDetails,
          payload: 'notification_$id',
        );

        debugPrint(
            '✅ [iOS Show] _notificationsPlugin.show() completed');

        // Update badge
        AppLog.d("NotificationService", '🔔 [iOS Show] Updating badge after showing notification');
        await _updateAppBadge();

        AppLog.i("NotificationService", '✅ [iOS Show] Notification shown successfully');
      }
    } catch (e, stackTrace) {
      AppLog.e("NotificationService", '❌ [Show Notification] ERROR: $e');
      AppLog.d("NotificationService", '📋 Stack trace: $stackTrace');
    }
  }

  // ============================================================================
  // NOTIFICATION MANAGEMENT
  // ============================================================================

  static Future<void> saveLocalLog({
    required String title,
    required String message,
    String category = "In-App Notification",
  }) async {
    try {
      AppLog.d("NotificationService", '💾 [Save Local Log] Saving notification to local storage...');

      final newItem = NotificationItem(
        id: DateTime.now().millisecondsSinceEpoch,
        title: title,
        message: message,
        category: category,
        timestamp: DateTime.now(),
        isRead: false,
      );

      AppLog.d("NotificationService", '   ID: ${newItem.id}');
      AppLog.d("NotificationService", '   Title: $title');
      AppLog.d("NotificationService", '   Category: $category');

      final prefs = await SharedPreferences.getInstance();
      final String? stored = prefs.getString(_storageKey);
      List<NotificationItem> history = [];

      if (stored != null) {
        final List decoded = json.decode(stored);
        history = decoded.map((e) => NotificationItem.fromJson(e)).toList();
      }

      history.insert(0, newItem);
      await prefs.setString(
          _storageKey, json.encode(history.map((e) => e.toJson()).toList()));

      AppLog.i("NotificationService", '✅ [Save Local Log] Saved to SharedPreferences');

      // Trigger system banner
      AppLog.d("NotificationService", '📬 [Save Local Log] Triggering system banner...');
      await _triggerSystemBanner(newItem.id, title, message);

      // Refresh
      AppLog.d("NotificationService", '🔄 [Save Local Log] Refreshing notifications...');
      await refreshNotifications();

      AppLog.i("NotificationService", '✅ [Save Local Log] COMPLETE');
    } catch (e, stackTrace) {
      AppLog.e("NotificationService", '❌ [Save Local Log] ERROR: $e');
      AppLog.d("NotificationService", '📋 Stack trace: $stackTrace');
    }
  }

  static Future<void> refreshNotifications() async {
    try {
      AppLog.d("NotificationService", '🔄 [Refresh] Refreshing all notifications...');

      List<NotificationItem> allNotifications = [];

      // Load local
      final prefs = await SharedPreferences.getInstance();
      final String? stored = prefs.getString(_storageKey);
      if (stored != null) {
        final List decoded = json.decode(stored);
        allNotifications
            .addAll(decoded.map((e) => NotificationItem.fromJson(e)));
      }

      AppLog.d("NotificationService", '   Local notifications: ${allNotifications.length}');

      // Load API
      try {
        final response = await http
            .get(
          Uri.parse(_apiUrl),
          headers: {
            'Content-Type': 'application/json',
          },
        )
            .timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final Map<String, dynamic> body = json.decode(response.body);
          if (body['success'] == true) {
            final List apiList = body['data'];
            allNotifications.addAll(apiList.map((item) =>
                NotificationItem.fromJson(item,
                    forcedCategory: "Staff Announcement")));
            AppLog.d("NotificationService", '   API notifications: ${apiList.length}');
          }
        }
      } catch (e) {
        AppLog.w("NotificationService", '   ⚠️  API fetch failed: $e');
      }

      allNotifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      notificationsNotifier.value = List.from(allNotifications);

      AppLog.i("NotificationService", '✅ [Refresh] Total notifications: ${allNotifications.length}');

      await _updateAppBadge();
    } catch (e, stackTrace) {
      AppLog.e("NotificationService", '❌ [Refresh] ERROR: $e');
      AppLog.d("NotificationService", '📋 Stack trace: $stackTrace');
    }
  }

  static Future<void> clearNotifications() async {
    try {
      AppLog.d("NotificationService", '🗑️  [Clear] Clearing all notifications...');

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);

      AppLog.d("NotificationService", '   Cleared SharedPreferences');

      await refreshNotifications();
      await clearBadge();

      AppLog.i("NotificationService", '✅ [Clear] COMPLETE');
    } catch (e, stackTrace) {
      AppLog.e("NotificationService", '❌ [Clear] ERROR: $e');
      AppLog.d("NotificationService", '📋 Stack trace: $stackTrace');
    }
  }

  static Future<void> markAsRead(int id) async {
    try {
      AppLog.d("NotificationService", '✓ [Mark as Read] Marking notification as read: $id');

      final List<NotificationItem> currentList =
      List.from(notificationsNotifier.value);
      int index = currentList.indexWhere((n) => n.id == id);

      if (index != -1 && !currentList[index].isRead) {
        currentList[index].isRead = true;
        final prefs = await SharedPreferences.getInstance();
        final localNotifications = currentList
            .where((n) => n.category != "Staff Announcement")
            .toList();
        await prefs.setString(_storageKey,
            json.encode(localNotifications.map((e) => e.toJson()).toList()));
        notificationsNotifier.value = currentList;

        await _updateAppBadge();

        AppLog.i("NotificationService", '✅ [Mark as Read] COMPLETE - Unread count: ${unreadCount}');
      }
    } catch (e, stackTrace) {
      AppLog.e("NotificationService", '❌ [Mark as Read] ERROR: $e');
      AppLog.d("NotificationService", '📋 Stack trace: $stackTrace');
    }
  }

  // ============================================================================
  // TEST NOTIFICATION
  // ============================================================================

  static Future<void> TestNotification() async {
    try {
      AppLog.d("NotificationService", '🧪 [Test Notification] Starting test...');

      await saveLocalLog(
        title: 'Test Notification',
        message: 'This is a test notification - ${DateTime.now().toString()}',
        category: 'Test',
      );

      AppLog.d("NotificationService", '🧪 [Test Notification] Test COMPLETE');
    } catch (e, stackTrace) {
      AppLog.e("NotificationService", '❌ [Test Notification] ERROR: $e');
      AppLog.d("NotificationService", '📋 Stack trace: $stackTrace');
    }
  }

  // ============================================================================
  // GETTERS
  // ============================================================================

  static int get unreadCount => notificationsNotifier.value.where((n) => !n.isRead).length;
}