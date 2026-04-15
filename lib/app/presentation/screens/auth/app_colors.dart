// lib/app/core/theme/app_colors.dart
import 'package:flutter/material.dart';

class AppColors {
  // Backward compatible alias
  static const Color primary = primaryGreen;

  // Primary
  static const Color primaryGreen = Color(0xFF4CAF50);
  static const Color primaryGreenDark = Color(0xFF388E3C);
  static const Color primaryGreenLight = Color(0xFF81C784);

  // Secondary
  static const Color secondaryOrange = Color(0xFFFF9800);
  static const Color secondaryYellow = Color(0xFFFFC107);

  // Text
  static const Color textDark = Color(0xFF1A1A1A);
  static const Color textGrey = Color(0xFF8E8E93); // ✅ diminta user
  static const Color textLight = Color(0xFF9E9E9E);

  // Background
  static const Color backgroundWhite = Color(0xFFFFFFFF);
  static const Color backgroundGrey = Color(0xFFF8F9FA);
  static const Color lightGrey = Color(0xFFE0E0E0);

  // Status
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFFC107);
  static const Color error = Color(0xFFF44336);
  static const Color info = Color(0xFF2196F3);

  // Freshness (produk)
  static const Color freshnessVeryGood = Color(0xFF4CAF50); // ≥90
  static const Color freshnessGood = Color(0xFF8BC34A); // 80–89
  static const Color freshnessMedium = Color(0xFFCDDC39); // 70–79
  static const Color freshnessLow = Color(0xFFFFC107); // 60–69
  static const Color freshnessVeryLow = Color(0xFFFF9800); // 40–59
  static const Color freshnessBad = Color(0xFFFF5722); // <40

  // MaterialColor
  static const MaterialColor primarySwatch = MaterialColor(
    0xFF4CAF50,
    <int, Color>{
      50: Color(0xFFE8F5E9),
      100: Color(0xFFC8E6C9),
      200: Color(0xFFA5D6A7),
      300: Color(0xFF81C784),
      400: Color(0xFF66BB6A),
      500: Color(0xFF4CAF50),
      600: Color(0xFF43A047),
      700: Color(0xFF388E3C),
      800: Color(0xFF2E7D32),
      900: Color(0xFF1B5E20),
    },
  );

  // Brand gradient
  static const LinearGradient brandGradient = LinearGradient(
    colors: [primaryGreen, primaryGreenDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Helper: pilih warna kesegaran dari persentase
  static Color freshnessColor(double pct) {
    if (pct >= 90) return freshnessVeryGood;
    if (pct >= 80) return freshnessGood;
    if (pct >= 70) return freshnessMedium;
    if (pct >= 60) return freshnessLow;
    if (pct >= 40) return freshnessVeryLow;
    return freshnessBad;
  }
}
