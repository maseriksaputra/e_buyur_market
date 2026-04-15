import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class FreshnessHelper {
  static Color getFreshnessColor(double pct) {
    if (pct >= 85) return AppColors.success;
    if (pct >= 65) return const Color(0xFF79C76A);
    if (pct >= 45) return const Color(0xFFF2B705);
    return const Color(0xFFE04848);
  }

  static String getFreshnessLabel(double pct) {
    if (pct >= 85) return 'Sangat Layak';
    if (pct >= 65) return 'Layak';
    if (pct >= 45) return 'Cukup';
    return 'Kurang';
  }
}
