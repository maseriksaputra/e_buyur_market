// lib/app/core/services/ai_service.dart
//
// AI stub yang cross-platform (Web/Mobile), tanpa import dart:io.
// Skor dibuat deterministik dari bytes gambar (jika ada) agar hasil konsisten
// untuk gambar yang sama. Kalau tidak ada bytes, fallback acak ringan.

import 'dart:math';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';

class AiService {
  Future<Map<String, dynamic>> analyzeProduct(dynamic input) async {
    // Simulasi proses singkat (optional)
    await Future.delayed(const Duration(milliseconds: 250));

    // Dapatkan seed dari input (bytes/name/path); fallback: waktu sekarang
    final seed = await _seedFromInput(input);
    final rng = Random(seed);

    // Skor 60.0—100.0 (kombinasi int + fraction biar terasa natural)
    final base = 60 + rng.nextInt(41); // 60..100 (int)
    final frac = rng.nextDouble(); // 0..1
    final score = (base + frac).clamp(0.0, 100.0);
    final rounded = double.parse(score.toStringAsFixed(1));

    return {
      'freshnessPercentage': rounded,
      'freshnessLabel': _labelFor(rounded),
    };
  }

  // ==== Helpers ====

  String _labelFor(double s) {
    if (s >= 90) return 'Sangat Layak';
    if (s >= 80) return 'Layak';
    if (s >= 70) return 'Cukup Layak';
    return 'Tidak Layak';
  }

  Future<int> _seedFromInput(dynamic input) async {
    try {
      if (input is Uint8List) {
        return _hashBytes(input);
      }
      if (input is XFile) {
        // Web/Mobile: coba ambil bytes agar deterministik
        final bytes = await input.readAsBytes();
        return _hashBytes(bytes);
      }
      if (input is String) {
        // Misal path/nama file sebagai basis
        return input.hashCode;
      }
    } catch (_) {
      // ignore dan fallback
    }
    // Fallback acak ringan (tidak deterministik)
    return DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
  }

  int _hashBytes(Uint8List bytes) {
    // Hash sederhana & cepat dari sebagian bytes (cukup untuk seed RNG)
    int h = 0;
    // sampling per ~64 byte agar cepat untuk file besar
    for (int i = 0; i < bytes.length; i += 64) {
      h = (h * 131) ^ bytes[i];
      h &= 0x7fffffff; // jaga tetap positif 31-bit
    }
    if (h == 0) h = 1; // hindari seed 0
    return h;
  }
}
