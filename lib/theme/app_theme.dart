// Premium GIS design system — single source of truth for colours,
// typography, spacing and component styles. Light theme only.
// Import AppTheme.light() from MaterialApp.theme with
// ThemeMode.light.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const olive = Color(0xFF2E4D2A);
  static const oliveDark = Color(0xFF142412);
  static const oliveSoft = Color(0xFFE8EFE6);
  static const gold = Color(0xFFE1B12C);
  static const goldSoft = Color(0xFFFFF3D6);
  static const bg = Color(0xFFF4F6F3);
  static const card = Colors.white;
  static const muted = Color(0xFF6E7A6C);
  static const success = Color(0xFF1FAA53);
  static const danger = Color(0xFFD63031);
  static const ink = Color(0xFF1B241A);
}

class AppTheme {
  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    final textTheme = GoogleFonts.interTextTheme(base.textTheme);
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.olive,
      primary: AppColors.olive,
      secondary: AppColors.gold,
      surface: AppColors.bg,
      error: AppColors.danger,
    );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.olive,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        hintStyle: const TextStyle(color: AppColors.muted),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.olive, width: 1.4),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.olive,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.olive,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      tabBarTheme: const TabBarThemeData(
        indicatorColor: AppColors.gold,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
      ),
    );
  }

  /// Kept for backwards compatibility — returns the light theme so any
  /// leftover `darkTheme:` reference still renders light.
  static ThemeData dark() => light();
  }

/// Premium gradient header card used on dashboards.
class PremiumHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;
  const PremiumHeader(
      {super.key, required this.title, required this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [AppColors.olive, AppColors.oliveDark],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [
          BoxShadow(
            color: AppColors.olive.withValues(alpha: 0.25),
            blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: Row(children: [
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(subtitle,
                style: GoogleFonts.inter(
                    color: Colors.white70, fontSize: 12.5)),
          ]),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// Stat tile with soft tint.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const StatTile({super.key, required this.label, required this.value,
    this.color = AppColors.olive, this.icon = Icons.insights});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06))),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 10),
          Text(value,
              style: TextStyle(
                  fontSize: 21, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
        ]),
      ),
    );
  }
}
