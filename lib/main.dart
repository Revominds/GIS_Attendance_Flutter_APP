import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gis_attendance/http_overrides.dart';
import 'package:flutter/material.dart';
import 'package:gis_attendance/screens/login_screen.dart';
import 'package:gis_attendance/screens/home_screen.dart';
import 'package:gis_attendance/services/auth_service.dart';
import 'package:gis_attendance/services/config_service.dart';
import 'package:gis_attendance/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:gis_attendance/widgets/inactivity_detector.dart';
import 'package:gis_attendance/utils/app_log.dart';
import 'package:gis_attendance/theme/app_theme.dart';


Future<void> main() async {

  WidgetsFlutterBinding.ensureInitialized();
  await AppLog.init();
  await dotenv.load(fileName: ".env");

  if (kDebugMode) {
    HttpOverrides.global = MyHttpOverrides();
  }

  await SharedPreferences.getInstance();
  try {
    // Best-effort: the app must start even if notifications can't init
    // (e.g. web, missing permissions).
    await NotificationService.initialize();
  } catch (_) {
    // ignore — in-app history still works without system banners
  }
  runApp(
      const MyApp()
  );
}



class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final AuthService _authService = AuthService();
  bool _loading = true;
  bool _loggedIn = false;
  bool _justLoggedOut = false;
  Duration _inactivityTimeout = const Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final loggedIn = await _authService.hasValidToken();
    final inactivityMinutes = await ConfigService.inactivityMinutes();

    if (!mounted) return;
    setState(() {
      _loggedIn = loggedIn;
      _inactivityTimeout = Duration(minutes: inactivityMinutes);
      _loading = false;
    });
  }

  void _handleLogout() async {
    await _authService.logout();
    if (!mounted) return;
    setState(() {
      _loggedIn = false;
      // Inactivity / session logout lands on sign-in with the
      // "Close app" option, matching the manual logout flow.
      _justLoggedOut = true;
    });
  }

  // Reusable builder to override bold text
  Widget _buildWithBoldTextOverride(Widget child) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        boldText: false, // Force disable bold text
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildApp();
  }

  Widget _buildApp() {
    if (_loading) {
      return MaterialApp(
        theme: AppTheme.light(),
        themeMode: ThemeMode.light,
        home: _buildWithBoldTextOverride(
          const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
        ),
      );
    }


    if (!_loggedIn) {
      return MaterialApp(
        title: 'GIS Attendance',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        themeMode: ThemeMode.light,
        builder: (context, child) {
          return _buildWithBoldTextOverride(child!);
        },
        home: LoginScreen(fromLogout: _justLoggedOut),
      );
    }

    // 🏠 STEP 3: HOME
    return InactivityDetector(
      onInactive: _handleLogout,
      timeout: _inactivityTimeout,
      child: MaterialApp(
        title: 'GIS Attendance',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        themeMode: ThemeMode.light,
        builder: (context, child) {
          return _buildWithBoldTextOverride(child!);
        },
        home: const HomeScreen(),
      ),
    );
  }
}