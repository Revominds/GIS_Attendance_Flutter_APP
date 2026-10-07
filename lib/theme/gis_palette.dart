// GIS palette — light theme only (dark theme removed).
// Kept as a central place for brand colours so screens don't hardcode
// custom palettes. `isDark` is always false.
//
// Usage inside any widget with a BuildContext in scope:
//   GisPalette.of(context).primary
import 'package:flutter/material.dart';

class GisPalette {
  final Brightness brightness;
  const GisPalette._(this.brightness);

  factory GisPalette.of(BuildContext context) =>
      // ignore: deprecated_member_use — forced light, ignore system dark
      const GisPalette._(Brightness.light);

  bool get isDark => false;

  /// Brand olive.
  Color get primary => const Color(0xFF2E4D2A);

  /// Deep olive for gradients/headers.
  Color get darkBg => const Color(0xFF142412);

  Color get gold => const Color(0xFFE1B12C);

  Color get goldText => const Color(0xFF8A6D1D);

  Color get goldDark => const Color(0xFF9A7B0A);

  Color get danger => const Color(0xFFD63031);

  Color get success => const Color(0xFF2ED573);

  /// Primary text ink.
  Color get ink => const Color(0xFF1A2519);

  /// Page background.
  Color get bg => const Color(0xFFF5F6F5);

  /// Card surface.
  Color get card => Colors.white;

  /// Secondary text.
  Color get muted => const Color(0xFF6E7A6C);

  /// Dividers / borders.
  Color get hairline => const Color(0xFFE7E9E4);

  Color get goldTint => const Color(0xFFFBF1D8);

  Color get oliveTint => const Color(0xFFE3EAE1);

  Color get greenTint => const Color(0xFFE1F9EC);

  Color get redTint => const Color(0xFFFBE6E6);
}
