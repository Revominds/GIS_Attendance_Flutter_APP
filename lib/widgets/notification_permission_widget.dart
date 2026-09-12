import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gis_attendance/services/notification_service.dart';

class NotificationPermissionChecker extends StatefulWidget {
  final Widget child;

  const NotificationPermissionChecker({super.key, required this.child});

  @override
  State<NotificationPermissionChecker> createState() => _NotificationPermissionCheckerState();
}

class _NotificationPermissionCheckerState extends State<NotificationPermissionChecker> {
  bool _hasPermission = true;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    if (Platform.isIOS) {
      setState(() => _isChecking = true);
      final hasPermission = await NotificationService.checkIOSPermissions();
      setState(() {
        _hasPermission = hasPermission;
        _isChecking = false;
      });

      // Show dialog if no permission
      if (!_hasPermission && mounted) {
        _showPermissionDialog();
      }
    }
  }

  void _showPermissionDialog() {
    Future.delayed(Duration.zero, () {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Enable Notifications'),
          content: const Text(
            'Please enable notifications to receive important updates about your attendance, '
                'clock-in/out confirmations, and staff announcements.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Later'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                final granted = await NotificationService.requestPermissions();
                if (!granted && mounted) {
                  // Show iOS settings guide
                  _showSettingsGuide();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
              ),
              child: const Text('Enable'),
            ),
          ],
        ),
      );
    });
  }

  void _showSettingsGuide() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enable Notifications in Settings'),
        content: const Text(
          'To enable notifications:\n\n'
              '1. Open iOS Settings\n'
              '2. Scroll to find your app\n'
              '3. Tap on "Notifications"\n'
              '4. Enable "Allow Notifications"',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return widget.child;
  }
}