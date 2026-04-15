// lib/app/common/helpers/freshness_helper.dart
import 'package:flutter/material.dart';

class FreshnessHelper {
  // Mendapatkan label berdasarkan persentase kesegaran
  static String getFreshnessLabel(double percentage) {
    if (percentage >= 90) {
      return 'Sangat Layak';
    } else if (percentage >= 75) {
      return 'Layak';
    } else if (percentage >= 60) {
      return 'Cukup Layak';
    } else if (percentage >= 40) {
      return 'Kurang Layak';
    } else if (percentage >= 20) {
      return 'Tidak Layak';
    } else {
      return 'Sangat Tidak Layak';
    }
  }

  // Mendapatkan warna berdasarkan persentase kesegaran
  static Color getFreshnessColor(double percentage) {
    if (percentage >= 90) {
      return const Color(0xFF4CAF50); // Hijau tua
    } else if (percentage >= 75) {
      return const Color(0xFF8BC34A); // Hijau muda
    } else if (percentage >= 60) {
      return const Color(0xFFCDDC39); // Hijau kekuningan
    } else if (percentage >= 40) {
      return const Color(0xFFFFC107); // Kuning orange
    } else if (percentage >= 20) {
      return const Color(0xFFFF9800); // Orange
    } else {
      return const Color(0xFFFF5722); // Orange kemerahan
    }
  }

  // Mendapatkan warna background yang lebih terang untuk card/container
  static Color getFreshnessBackgroundColor(double percentage) {
    if (percentage >= 90) {
      return const Color(0xFFE8F5E9); // Hijau tua sangat muda
    } else if (percentage >= 75) {
      return const Color(0xFFF1F8E9); // Hijau muda sangat muda
    } else if (percentage >= 60) {
      return const Color(0xFFF9FBE7); // Hijau kekuningan sangat muda
    } else if (percentage >= 40) {
      return const Color(0xFFFFF8E1); // Kuning orange sangat muda
    } else if (percentage >= 20) {
      return const Color(0xFFFFF3E0); // Orange sangat muda
    } else {
      return const Color(0xFFFBE9E7); // Orange kemerahan sangat muda
    }
  }

  // Mendapatkan icon berdasarkan persentase kesegaran
  static IconData getFreshnessIcon(double percentage) {
    if (percentage >= 90) {
      return Icons.verified; // Verified checkmark
    } else if (percentage >= 75) {
      return Icons.check_circle; // Check circle
    } else if (percentage >= 60) {
      return Icons.info; // Info
    } else if (percentage >= 40) {
      return Icons.warning_amber; // Warning
    } else if (percentage >= 20) {
      return Icons.error_outline; // Error outline
    } else {
      return Icons.dangerous; // Dangerous
    }
  }

  // Mendapatkan deskripsi detail berdasarkan persentase
  static String getFreshnessDescription(double percentage) {
    if (percentage >= 90) {
      return 'Produk dalam kondisi sangat segar dan sangat layak dikonsumsi';
    } else if (percentage >= 75) {
      return 'Produk dalam kondisi segar dan layak dikonsumsi';
    } else if (percentage >= 60) {
      return 'Produk masih cukup segar dan cukup layak dikonsumsi';
    } else if (percentage >= 40) {
      return 'Produk kurang segar, segera konsumsi';
    } else if (percentage >= 20) {
      return 'Produk tidak segar, tidak disarankan untuk dikonsumsi';
    } else {
      return 'Produk sangat tidak layak konsumsi';
    }
  }

  // Widget untuk menampilkan badge kesegaran
  static Widget getFreshnessBadge(double percentage, {double fontSize = 12}) {
    final label = getFreshnessLabel(percentage);
    final color = getFreshnessColor(percentage);
    final bgColor = getFreshnessBackgroundColor(percentage);
    final icon = getFreshnessIcon(percentage);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: fontSize + 4,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // Widget untuk menampilkan progress bar kesegaran
  static Widget getFreshnessProgressBar(double percentage,
      {double height = 8}) {
    final color = getFreshnessColor(percentage);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              getFreshnessLabel(percentage),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            Text(
              '${percentage.toStringAsFixed(1)}%',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: LinearProgressIndicator(
            value: percentage / 100,
            minHeight: height,
            backgroundColor: Colors.grey[300],
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  // Widget untuk card produk dengan indikator kesegaran
  static Widget getFreshnessCard({
    required double percentage,
    required Widget child,
  }) {
    final color = getFreshnessColor(percentage);
    final bgColor = getFreshnessBackgroundColor(percentage);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: Center(
              child: getFreshnessBadge(percentage),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
