// lib/app/common/utils/view_utils.dart
import 'package:flutter/material.dart';
import '../../core/utils/url_fix.dart'; // ✅ tambah: perbaiki URL gambar ke APP_URL/pub/...

String formatRupiah(num n) {
  final v = n.toDouble();
  // tanpa intl: pemisah ribuan titik
  final parts = v.toStringAsFixed(0).split('');
  final buf = StringBuffer();
  for (int i = 0; i < parts.length; i++) {
    buf.write(parts[i]);
    final left = parts.length - i - 1;
    if (left > 0 && left % 3 == 0) buf.write('.');
  }
  return 'Rp ${buf.toString()}';
}

Widget netImage(
  String? url, {
  double? w,
  double? h,
  BoxFit fit = BoxFit.cover,
}) {
  if (url == null || url.isEmpty) {
    return Container(
      width: w,
      height: h,
      color: Colors.grey.shade200,
      child: const Icon(Icons.image_not_supported),
    );
    // bisa juga pakai placeholder bawaan di fixImageUrl jika mau
  }

  return Image.network(
    fixImageUrl(url), // ✅ always fixed → aman jika backend kirim 'products/...'
    width: w,
    height: h,
    fit: fit,
    errorBuilder: (_, __, ___) => Container(
      width: w,
      height: h,
      color: Colors.grey.shade200,
      child: const Icon(Icons.broken_image),
    ),
  );
}
