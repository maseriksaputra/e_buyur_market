// lib/app/common/widgets/safe_network_image.dart
import 'package:flutter/material.dart';
import '../../core/utils/url_fix.dart'; // ✅ tambah: perbaiki URL (products→pub/products, storage→pub)

class SafeNetworkImage extends StatelessWidget {
  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const SafeNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: width,
      height: height,
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      child: const Icon(Icons.image_not_supported_outlined),
    );

    final String? u = url?.trim();
    final bool hasUrl = (u != null && u.isNotEmpty);

    final Widget img = hasUrl
        ? Image.network(
            fixImageUrl(u), // ✅ always fixed ke APP_URL/pub/...
            width: width,
            height: height,
            fit: fit,
            // bantu decoder biar ringan (jika ada ukuran)
            cacheWidth: width != null ? width!.toInt() : null,
            cacheHeight: height != null ? height!.toInt() : null,
            filterQuality: FilterQuality.low,
            headers: const {'Accept': 'image/*'},
            loadingBuilder: (ctx, child, progress) {
              if (progress == null) return child;
              return placeholder;
            },
            errorBuilder: (ctx, err, stack) => placeholder,
          )
        : placeholder;

    // --- FIX: promotion untuk field nullable ---
    final br = borderRadius; // simpan ke variabel lokal agar aman di Dart
    if (br != null) {
      return ClipRRect(borderRadius: br, child: img);
    }
    return img;
  }
}
