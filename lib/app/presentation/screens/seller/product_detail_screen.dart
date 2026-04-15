// lib/app/presentation/screens/seller/product_detail_screen.dart
import 'package:flutter/material.dart' hide CarouselController; // hindari bentrok nama
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:intl/intl.dart';

import 'package:provider/provider.dart';
import 'package:e_buyur_market_flutter_5/app/presentation/providers/cart_provider.dart';

// carousel_slider v5.x
import 'package:carousel_slider/carousel_slider.dart';
import 'package:carousel_slider/carousel_controller.dart' show CarouselSliderController;

import 'package:e_buyur_market_flutter_5/app/presentation/providers/product_provider.dart';
import 'package:e_buyur_market_flutter_5/app/common/models/product_model.dart';
import 'package:e_buyur_market_flutter_5/app/core/utils/product_read.dart';
import 'package:e_buyur_market_flutter_5/app/core/utils/url_fix.dart';
import 'package:e_buyur_market_flutter_5/app/routes/checkout_args.dart' show CheckoutArgs;

class SellerProductDetailScreen extends StatefulWidget {
  // dibuat optional agar bisa dipanggil tanpa argumen dari main.dart
  final dynamic product;
  const SellerProductDetailScreen({super.key, this.product = const <String, dynamic>{}});

  @override
  State<SellerProductDetailScreen> createState() => _SellerProductDetailScreenState();
}

class _SellerProductDetailScreenState extends State<SellerProductDetailScreen> {
  // controller yang benar untuk carousel_slider v5
  late final CarouselSliderController _carouselController = CarouselSliderController();

  int _currentIndex = 0;
  int _quantity = 1;

  int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  num _toNum(dynamic v) {
    if (v is num) return v;
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    try {
      final m = (v as dynamic).toJson();
      if (m is Map) return Map<String, dynamic>.from(m as Map);
    } catch (_) {}
    return null;
  }

  int _extractCartItemId(dynamic it) {
    if (it == null) return 0;
    if (it is Map) {
      final m = Map<String, dynamic>.from(it);
      final raw = m['id'] ?? m['cart_item_id'] ?? m['cartItemId'];
      return raw is int ? raw : int.tryParse('$raw') ?? 0;
    }
    try {
      final v = (it as dynamic).id;
      if (v is int) return v;
      return int.tryParse('$v') ?? 0;
    } catch (_) {}
    try {
      final v = (it as dynamic).cartItemId;
      if (v is int) return v;
      return int.tryParse('$v') ?? 0;
    } catch (_) {}
    return 0;
  }

  int _extractCartProductId(dynamic it) {
    if (it == null) return 0;
    if (it is Map) {
      final m = Map<String, dynamic>.from(it);
      final raw = m['product_id'] ?? m['productId'] ?? m['product']?['id'];
      return raw is int ? raw : int.tryParse('$raw') ?? 0;
    }
    try {
      final v = (it as dynamic).productId ?? (it as dynamic).product?.id;
      if (v is int) return v;
      return int.tryParse('$v') ?? 0;
    } catch (_) {}
    return 0;
  }

  /// Tambah ke cart (mencoba semua signature yang umum)
  Future<bool> _cartAddCompat(int productId, int qty) async {
    final c = context.read<CartProvider>() as dynamic;
    try { final r = c.add(productId, qty); if (r is Future) await r; return true; } catch (_) {}
    try { final r = c.add(productId: productId, qty: qty); if (r is Future) await r; return true; } catch (_) {}
    try { final r = c.add(product_id: productId, quantity: qty); if (r is Future) await r; return true; } catch (_) {}
    try { final r = c.addToCart(productId: productId, qty: qty); if (r is Future) await r; return true; } catch (_) {}
    return false;
  }

  /// Tambah + kembalikan cartItemId yang baru dibuat
  Future<int> _addToCartAndGetId(int productId, int qty) async {
    final cart = context.read<CartProvider>() as dynamic;
    dynamic created;
    try {
      created = await cart.add(productId, qty);
    } catch (_) {
      try {
        created = await cart.add(productId: productId, qty: qty);
      } catch (_) {
        try {
          created = await cart.add(product_id: productId, quantity: qty);
        } catch (_) {
          try {
            created = await cart.addToCart(productId: productId, qty: qty);
          } catch (e) {
            debugPrint('[SellerProductDetail] addToCart failed: $e');
            created = null;
          }
        }
      }
    }

    final idDirect = _extractCartItemId(created);
    if (idDirect > 0) return idDirect;

    try {
      await cart.fetch();
      final items = (cart.items as List?) ?? const [];
      int foundId = 0;
      for (final it in items) {
        if (_extractCartProductId(it) == productId) {
          final cid = _extractCartItemId(it);
          if (cid > foundId) foundId = cid;
        }
      }
      return foundId;
    } catch (e) {
      debugPrint('[SellerProductDetail] fetch/scan failed: $e');
    }
    return 0;
  }

  List<String> _extractImageUrls(dynamic product) {
    final p = Pread.from(product);
    final List<String> urls = [];
    final m = _asMap(product);
    if (m != null) {
      for (final k in const ['imageUrls', 'images', 'photos', 'gallery']) {
        final v = m[k];
        if (v is List) {
          for (final e in v) {
            final s = fixImageUrl('$e');
            if (s.isNotEmpty) urls.add(s);
          }
        } else if (v is String && v.contains(',')) {
          for (final e in v.split(',')) {
            final s = fixImageUrl(e.trim());
            if (s.isNotEmpty) urls.add(s);
          }
        }
      }
    }
    final primary = fixImageUrl(p.imageUrl);
    if (primary.isNotEmpty && !urls.contains(primary)) urls.insert(0, primary);
    if (urls.isEmpty) urls.add(primary.isNotEmpty ? primary : '');
    return urls.where((e) => e.isNotEmpty).toSet().toList();
  }

  @override
  Widget build(BuildContext context) {
    final nf = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    final p = Pread.from(widget.product);
    final images = _extractImageUrls(widget.product);

    final name = p.name.isNotEmpty ? p.name : '-';
    final price = _toNum(p.price);
    final unit = (p.unit?.toString().trim().isNotEmpty == true) ? p.unit.toString() : 'unit';

    final stock = (() {
      final m = _asMap(widget.product);
      if (m != null) {
        for (final k in const ['stock', 'stok', 'qty', 'quantity']) {
          if (m[k] != null) return _asInt(m[k]);
        }
      }
      try { return _asInt((widget.product as dynamic).stock); } catch (_) {}
      return 0;
    })();

    final totalPrice = price * _quantity;

    return Scaffold(
      appBar: AppBar(title: const Text('Detail Produk (Seller)')),
      body: ListView(
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: images.isEmpty
                ? Container(
                    color: Colors.grey[300],
                    child: const Center(child: Icon(Icons.image_not_supported, size: 64, color: Colors.white)),
                  )
                : CarouselSlider(
                    items: images.map((url) {
                      final fixed = fixImageUrl(url);
                      if (fixed.isEmpty) {
                        return Container(
                          color: Colors.grey[300],
                          child: const Center(child: Icon(Icons.image_not_supported, size: 64, color: Colors.white)),
                        );
                      }
                      return Image.network(
                        fixed,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey.shade200,
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image, color: Colors.black45),
                        ),
                      );
                    }).toList(),
                    carouselController: _carouselController, // ✅ v5
                    options: CarouselOptions(
                      height: double.infinity,
                      viewportFraction: 1.0,
                      enableInfiniteScroll: images.length > 1,
                      onPageChanged: (i, _) => setState(() => _currentIndex = i),
                    ),
                  ),
          ),
          if (images.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: images.asMap().entries.map((e) {
                  final active = _currentIndex == e.key;
                  return Container(
                    width: active ? 22 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(active ? .8 : .25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  );
                }).toList(),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      nf.format(price),
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF2e7d32)),
                    ),
                    Text(' /$unit', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: stock > 10 ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Stok: $stock $unit',
                        style: TextStyle(
                          fontSize: 12,
                          color: stock > 10 ? Colors.green : Colors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  (p.description ?? '').toString().trim().isEmpty ? 'Tidak ada deskripsi.' : p.description!.trim(),
                  style: TextStyle(fontSize: 14, color: Colors.grey[800]),
                ),
              ],
            ),
          ),
        ],
      ),

      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), offset: const Offset(0, -2), blurRadius: 10)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _qtyStepper(stock),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text(
                          nf.format(totalPrice),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2e7d32)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: (stock <= 0)
                          ? null
                          : () async {
                              final prodId = _asInt(Pread.from(widget.product).id);
                              if (prodId <= 0) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Produk tidak valid.'), behavior: SnackBarBehavior.floating),
                                );
                                return;
                              }
                              final ok = await _cartAddCompat(prodId, _quantity);
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(ok ? 'Berhasil ditambahkan' : 'Gagal menambahkan ke keranjang.'),
                                  behavior: SnackBarBehavior.floating,
                                  backgroundColor: ok ? null : Colors.redAccent,
                                ),
                              );
                            },
                      child: const Text('Tambah ke Keranjang'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: (stock <= 0)
                          ? null
                          : () async {
                              final prodId = _asInt(Pread.from(widget.product).id);
                              if (prodId <= 0) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Produk tidak valid.'), behavior: SnackBarBehavior.floating),
                                );
                                return;
                              }
                              try {
                                final newId = await _addToCartAndGetId(prodId, _quantity);
                                if (newId <= 0) throw Exception('Tidak mendapat ID item keranjang');
                                if (!mounted) return;
                                Navigator.pushNamed(
                                  context,
                                  '/checkout',
                                  arguments: CheckoutArgs.cart(cartItemIds: [newId]),
                                );
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Gagal Beli Sekarang: $e'), behavior: SnackBarBehavior.floating, backgroundColor: Colors.redAccent),
                                );
                              }
                            },
                      child: const Text('Beli Sekarang'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _qtyStepper(int stock) {
    final disabled = stock <= 0;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(14),
        color: Colors.white,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            splashRadius: 20,
            icon: const Icon(Icons.remove),
            onPressed: (disabled || _quantity <= 1) ? null : () => setState(() => _quantity--),
          ),
          const SizedBox(width: 2),
          Text('$_quantity', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(width: 2),
          IconButton(
            splashRadius: 20,
            icon: const Icon(Icons.add),
            onPressed: (disabled || _quantity >= (stock > 0 ? stock : 9999)) ? null : () => setState(() => _quantity++),
          ),
        ],
      ),
    );
  }
}
