// lib/app/common/widgets/product_card.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/utils/product_read.dart';
import '../../core/utils/url_fix.dart';
import 'app_colors.dart'; // ✅ path benar

import 'package:e_buyur_market_flutter_5/app/common/models/product_category.dart'
    show ProductCategoryX;

final _currency =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

// ---------- Helpers ----------
num _toNum(dynamic v) {
  if (v is num) return v;
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

String _nonEmptyStr(dynamic v) {
  final s = (v ?? '').toString().trim();
  return s.toLowerCase() == 'null' ? '' : s;
}

String _categoryLabelOf(dynamic product) {
  // 1) field langsung (categoryLabel)
  try {
    final label = _nonEmptyStr((product as dynamic).categoryLabel);
    if (label.isNotEmpty) return label;
  } catch (_) {}

  // 2) object category (label/name/slug)
  try {
    final c = (product as dynamic).category;
    final parsed = ProductCategoryX.fromAny(c);
    if (parsed != null) return parsed.label;
  } catch (_) {}

  // 3) variasi map
  try {
    final m = (product as dynamic) as Map;
    final raw = m['category'] ??
        m['kategori'] ??
        m['product_category'] ??
        m['category_name'] ??
        m['categoryLabel'] ??
        m['category_slug'];
    final parsed = ProductCategoryX.fromAny(raw);
    if (parsed != null) return parsed.label;

    final s = _nonEmptyStr(raw);
    if (s.isNotEmpty) return s;
  } catch (_) {}

  return '';
}

double? _suitabilityOf(dynamic product) {
  // prefer explicit suitability
  try {
    final v = (product as dynamic).suitabilityPercent;
    if (v is num) return v.toDouble().clamp(0.0, 100.0);
    if (v is String) {
      final d = double.tryParse(v);
      if (d != null) return d.clamp(0.0, 100.0);
    }
  } catch (_) {}

  // common API field
  try {
    final m = (product as dynamic) as Map;
    final raw = m['suitability_percent'] ?? m['freshness_score'];
    if (raw is num) return raw.toDouble().clamp(0.0, 100.0);
    if (raw is String) {
      final d = double.tryParse(raw);
      if (d != null) return d.clamp(0.0, 100.0);
    }
  } catch (_) {}

  // fallback last-resort
  try {
    final v = (product as dynamic).freshnessScore;
    if (v is num) return v.toDouble().clamp(0.0, 100.0);
    if (v is String) {
      final d = double.tryParse(v);
      if (d != null) return d.clamp(0.0, 100.0);
    }
  } catch (_) {}

  return null;
}

int _stockOf(dynamic product) {
  try {
    final pr = Pread.from(product);
    final s = pr.stock;
    if (s is int) return s;
    // ✅ fix: cast eksplisit agar analyzer tidak protes
    if (s is String) return int.tryParse(s as String) ?? 0;
  } catch (_) {}
  try {
    final m = (product as dynamic) as Map;
    final raw = m['stock'] ?? m['qty'] ?? m['quantity'];
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw) ?? 0;
  } catch (_) {}
  return 0;
}

String _imageUrlOf(Pread p) {
  final primary = _nonEmptyStr(p.imageUrl);
  final alt = (p.images.isNotEmpty) ? _nonEmptyStr(p.images.first) : '';
  return fixImageUrl(primary.isNotEmpty ? primary : (alt.isNotEmpty ? alt : null));
}

String _unitOf(Pread p) {
  final u = _nonEmptyStr(p.unit);
  return u.isNotEmpty ? u : 'kg';
}

// ====== Warna & util berbasis AppColors ======
Color _categoryColor(String label) {
  final l = label.toLowerCase();
  if (l.contains('sayur') || l.contains('vegetable')) {
    return AppColors.primaryGreen;      // hijau untuk Sayur
  }
  if (l.contains('buah') || l.contains('fruit')) {
    return AppColors.secondaryOrange;   // oranye untuk Buah
  }
  return AppColors.textGrey;            // netral
}

Color _percentColor(double p) {
  // 0..100 → palet kesegaran AppColors
  return AppColors.freshnessColor(p);
}

Color _tint(Color c, [double a = .10]) => c.withOpacity(a);

// ====== Badge modern ======
class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  final EdgeInsets padding;
  final bool solid; // persentase: solid; kategori: tinted

  const _Badge(
    this.text,
    this.color, {
    Key? key, // ✅ kompatibel semua versi
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    this.solid = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bg = solid ? color : _tint(color);
    final fg = solid ? Colors.white : color;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        gradient: solid
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color, Color.lerp(color, Colors.black, .12)!],
              )
            : null,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          height: 1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ====== Kartu Produk Modern ======
class ProductCard extends StatelessWidget {
  final dynamic product;
  final VoidCallback? onTap;

  /// Opsi tampil ringkas (padding lebih kecil)
  final bool dense;

  /// Tampilkan kategori & persentase (badge)
  final bool showCategory;
  final bool showPercent;

  const ProductCard({
    Key? key,
    required this.product,
    this.onTap,
    this.dense = false,
    this.showCategory = true,
    this.showPercent = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final pr = Pread.from(product);

    final String name = _nonEmptyStr(pr.name).isEmpty ? '-' : pr.name;
    final String priceFmt = _currency.format(_toNum(pr.price));
    final String unit = _unitOf(pr);
    final String imgUrl = _imageUrlOf(pr);

    final String categoryLabel = _categoryLabelOf(product);
    final double? suitability = _suitabilityOf(product);

    final Color catColor = _categoryColor(categoryLabel);
    final Color suitColor = _percentColor((suitability ?? 0).toDouble());
    final String? suitText =
        (suitability != null) ? '${suitability.round()}%' : null;

    final int stock = _stockOf(product);
    final bool outOfStock = stock <= 0;

    final BorderRadius radius = BorderRadius.circular(14);
    final EdgeInsets contentPad =
        dense ? const EdgeInsets.fromLTRB(10, 8, 10, 10)
              : const EdgeInsets.fromLTRB(12, 10, 12, 12);

    return Semantics(
      button: true,
      label: 'Produk $name, harga $priceFmt per $unit',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          splashColor: AppColors.primaryGreen.withOpacity(.08),
          highlightColor: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: radius,
              border: Border.all(color: const Color(0xFFE8E8E8)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ===== Gambar =====
                ClipRRect(
                  borderRadius: BorderRadius.vertical(top: radius.topLeft),
                  child: Stack(
                    children: [
                      AspectRatio(
                        aspectRatio: 1, // kotak
                        child: (imgUrl.isNotEmpty)
                            ? Image.network(
                                imgUrl,
                                fit: BoxFit.cover,
                                gaplessPlayback: true, // ↓ kurangi blink saat rebuild
                                loadingBuilder: (c, child, progress) =>
                                    progress == null ? child : const SizedBox(),
                                errorBuilder: (_, __, ___) =>
                                    const Center(child: Icon(Icons.broken_image)),
                                filterQuality: FilterQuality.medium, // tetap seperti punyamu
                              )
                            : const ColoredBox(color: Color(0xFFF5F5F5)),
                      ),
                      // gradient lembut agar badge/teks kebaca
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withOpacity(.08),
                                Colors.transparent
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Badge kategori (kiri atas) + persentase (kanan atas)
                      if (showCategory || (showPercent && suitText != null))
                        Positioned(
                          left: 8,
                          right: 8,
                          top: 8,
                          child: Row(
                            children: [
                              // Kiri: kategori (fleksibel agar tak overflow)
                              if (showCategory && categoryLabel.isNotEmpty)
                                Flexible(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: _Badge(categoryLabel, _categoryColor(categoryLabel)),
                                  ),
                                ),
                              const Spacer(),
                              // Kanan: persentase (solid)
                              if (showPercent && suitText != null)
                                _Badge(suitText, suitColor, solid: true),
                            ],
                          ),
                        ),

                      // Overlay "Habis" kalau stok 0
                      if (outOfStock)
                        Positioned.fill(
                          child: Container(
                            color: Colors.white.withOpacity(.55),
                            alignment: Alignment.center,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.error.withOpacity(.90),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'Stok Habis',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // ===== Info =====
                Padding(
                  padding: contentPad,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textDark,
                              fontWeight: FontWeight.w700,
                              fontSize: dense ? 13 : 14,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$priceFmt / $unit',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.primaryGreenDark,
                              fontWeight: FontWeight.w700,
                              fontSize: dense ? 12.5 : 13.5,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
