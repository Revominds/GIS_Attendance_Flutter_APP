import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gis_attendance/http_overrides.dart';
import 'package:flutter/material.dart';
import 'package:gis_attendance/screens/login_screen.dart';
import 'package:gis_attendance/screens/home_screen.dart';
import 'package:gis_attendance/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:gis_attendance/widgets/inactivity_detector.dart';
import 'package:gis_attendance/utils/app_log.dart';


Future<void> main() async {

  WidgetsFlutterBinding.ensureInitialized();
  await AppLog.init();
  await dotenv.load(fileName: ".env");

  if (kDebugMode) {
    HttpOverrides.global = MyHttpOverrides();
  }

  await SharedPreferences.getInstance();
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

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final loggedIn = await _authService.hasValidToken();

    if (!mounted) return;
    setState(() {
      _loggedIn = loggedIn;
      _loading = false;
    });
  }

  void _handleLogout() async {
    await _authService.logout();
    setState(() {
      _loggedIn = false;
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
    if (_loading) {
      return MaterialApp(
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
        theme: ThemeData(primarySwatch: Colors.green),
        builder: (context, child) {
          return _buildWithBoldTextOverride(child!);
        },
        home: const LoginScreen(),
      );
    }

    // 🏠 STEP 3: HOME
    return InactivityDetector(
      onInactive: _handleLogout,
      child: MaterialApp(
        title: 'GIS Attendance',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(primarySwatch: Colors.green),
        builder: (context, child) {
          return _buildWithBoldTextOverride(child!);
        },
        home: const HomeScreen(),
      ),
    );
  }
}