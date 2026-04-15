// lib/app/presentation/screens/buyer/product_detail_screen.dart
import 'dart:convert';

import 'package:flutter/material.dart' hide CarouselController; // hindari bentrok dg Flutter's CarouselController
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:intl/intl.dart';

// NEW: fetch detail produk dari API
import 'package:dio/dio.dart';
import 'package:e_buyur_market_flutter_5/app/core/network/api.dart';

// State mgmt
import 'package:provider/provider.dart';
import 'package:e_buyur_market_flutter_5/app/presentation/providers/cart_provider.dart';

// carousel_slider v5.x
import 'package:carousel_slider/carousel_slider.dart';
import 'package:carousel_slider/carousel_controller.dart' show CarouselSliderController;

// Providers
import 'package:e_buyur_market_flutter_5/app/presentation/providers/product_provider.dart';

// Models & Utils
import 'package:e_buyur_market_flutter_5/app/common/models/product_model.dart';
import 'package:e_buyur_market_flutter_5/app/core/utils/product_read.dart';
import 'package:e_buyur_market_flutter_5/app/core/utils/url_fix.dart';

// enum kategori (jika ada)
import 'package:e_buyur_market_flutter_5/app/common/models/product_category.dart';
// UI chip kategori
import 'package:e_buyur_market_flutter_5/app/common/ui/category_theme.dart';

// Theme (untuk _Section baru)
import 'package:e_buyur_market_flutter_5/app/core/theme/app_colors.dart';

// Section ulasan
import 'package:e_buyur_market_flutter_5/app/presentation/widgets/review/product_reviews_section.dart';

class BuyerProductDetailScreen extends StatefulWidget {
  final dynamic product; // Product / Map / dynamic
  const BuyerProductDetailScreen({super.key, required this.product});

  @override
  State<BuyerProductDetailScreen> createState() => _BuyerProductDetailScreenState();
}

class _BuyerProductDetailScreenState extends State<BuyerProductDetailScreen> {
  // carousel_slider v5.x
  late final CarouselSliderController _carouselController = CarouselSliderController();

  int _currentIndex = 0;
  bool _isFavorite = false;
  int _quantity = 1; // jumlah barang

  // === NEW: state detail produk dari API (untuk nutrisi & penyimpanan) ===
  bool _loadingDetail = true;
  String? _detailError;
  Map<String, dynamic>? _detail; // hasil normalisasi { ... } (bukan wrapper)

  @override
  void initState() {
    super.initState();
    // Muat detail produk dari backend untuk memastikan nutrisi & storage tampil
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pid = _asInt(Pread.from(widget.product).id);
      if (pid > 0) {
        _loadDetail(pid);
      } else {
        _loadingDetail = false;
        _detail = null;
        setState(() {});
      }
    });
  }

  Future<void> _loadDetail(int productId) async {
    setState(() {
      _loadingDetail = true;
      _detailError = null;
    });
    try {
      final candidates = <String>[
        'products/$productId',        // { data: {...} } atau langsung {...}
        'buyer/products/$productId',  // alternatif
      ];

      Map<String, dynamic>? prod;
      for (final ep in candidates) {
        try {
          final res = await API.dio.get(ep);
          final body = res.data;
          if (body is Map<String, dynamic>) {
            if (body['data'] is Map<String, dynamic>) {
              prod = Map<String, dynamic>.from(body['data'] as Map);
            } else {
              prod = Map<String, dynamic>.from(body);
            }
            if (prod != null) break;
          }
        } on DioException catch (e) {
          debugPrint('[DetailProduct] $ep -> DioException: ${e.message}');
          // coba endpoint lain
        } catch (e) {
          debugPrint('[DetailProduct] $ep -> error: $e');
        }
      }

      if (prod == null) throw Exception('Produk tidak ditemukan');

      setState(() {
        _detail = prod;
        _loadingDetail = false;
      });
    } catch (e) {
      setState(() {
        _detailError = '$e';
        _loadingDetail = false;
        // tetap lanjut dengan data Pread agar UI tidak blank
      });
    }
  }

  // ---------- Helpers defensif ----------
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

  double? _toD(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
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

  // === String-safe JSON helper (untuk parsing response API jika perlu) ===
  Map<String, dynamic> _jsonMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final d = jsonDecode(raw);
        if (d is Map) return Map<String, dynamic>.from(d);
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  // === Helpers cart-item (ambil id & product_id dari berbagai bentuk) ===
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

  /// Tambah ke cart, **usahakan** mengembalikan id cart item.
  Future<int> _addToCartAndGetIdCompat(int productId, int qty) async {
    final cart = context.read<CartProvider>() as dynamic;
    dynamic created;

    // 1) add(productId: , qty: )
    try {
      created = await cart.add(productId: productId, qty: qty);
    } catch (_) {
      // 2) add(product_id: , quantity: )
      try {
        created = await cart.add(product_id: productId, quantity: qty);
      } catch (_) {
        // 3) add positional
        try {
          created = await cart.add(productId, qty);
        } catch (_) {
          // 4) addToCart(...)
          try {
            created = await cart.addToCart(productId: productId, qty: qty);
          } catch (e) {
            debugPrint('[ProductDetail] addToCart failed: $e');
            created = null;
          }
        }
      }
    }

    // coba ambil id langsung
    int cid = _extractCartItemId(created);

    // fallback: fetch & cari id terbaru utk productId
    if (cid <= 0) {
      try {
        await cart.fetch();
      } catch (e) {
        debugPrint('[ProductDetail] cart.fetch() failed: $e');
      }
      try {
        final items = (cart.items as List?) ?? const [];
        int foundId = 0;
        for (final it in items) {
          if (_extractCartProductId(it) == productId) {
            final x = _extractCartItemId(it);
            if (x > foundId) foundId = x;
          }
        }
        cid = foundId;
      } catch (e) {
        debugPrint('[ProductDetail] scan items for id failed: $e');
      }
    }

    return cid;
  }

  // ---------- kategori & data lain ----------
  String _storageTipsOf(dynamic product) {
    String pick(dynamic x) => (x ?? '').toString().trim();
    try {
      final s = pick((product as dynamic).storageTips);
      if (s.isNotEmpty) return s;
    } catch (_) {}
    try {
      final s = pick((product as dynamic).storageNotes);
      if (s.isNotEmpty) return s;
    } catch (_) {}
    final m = _asMap(product) ?? {};
    for (final key in const [
      'storageTips',
      'storage_notes',
      'storageNotes',
      'storage_tips',
      'storage_tips_text'
    ]) {
      final s = pick(m[key]);
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  int _soldCountOf(dynamic product) {
    final m = _asMap(product);
    if (m != null) {
      for (final k in const [
        'sold_count',
        'soldCount',
        'sold',
        'terjual',
        'total_sold',
        'order_count',
        'orders',
        'totalOrders',
      ]) {
        if (m.containsKey(k)) return _asInt(m[k]);
      }
    }
    try {
      return _asInt((product as dynamic).soldCount);
    } catch (_) {}
    try {
      return _asInt((product as dynamic).sold);
    } catch (_) {}
    try {
      return _asInt((product as dynamic).totalSold);
    } catch (_) {}
    try {
      return _asInt((product as dynamic).orders);
    } catch (_) {}
    return 0;
  }

  int _stockOf(dynamic product) {
    final m = _asMap(product);
    if (m != null) {
      for (final k in const ['stock', 'stok', 'qty', 'quantity', 'jumlah']) {
        if (m.containsKey(k)) return _asInt(m[k]);
      }
    }
    try {
      return _asInt((product as dynamic).stock);
    } catch (_) {}
    try {
      return _asInt((product as dynamic).qty);
    } catch (_) {}
    return 0;
  }

  // ---------- kategori (string legacy) ----------
  String _categoryOf(dynamic product) {
    final m = _asMap(product);
    if (m != null) {
      if (m['category'] is Map && (m['category']['name'] != null)) {
        return '${m['category']['name']}';
      }
      for (final k in const ['category', 'kategori', 'cat_name', 'category_name']) {
        final v = m[k];
        if (v != null && v is! Map && v.toString().trim().isNotEmpty) {
          return v.toString();
        }
      }
    }
    try {
      return (product as dynamic).category?.name?.toString() ?? '';
    } catch (_) {}
    try {
      return (product as dynamic).category?.toString() ?? '';
    } catch (_) {}
    return '';
  }

  // kategori (enum ProductCategory jika tersedia)
  ProductCategory? _categoryEnumOf(dynamic product) {
    try {
      final c = (product as dynamic).category;
      final parsed = ProductCategoryX.fromAny(c);
      if (parsed != null) return parsed;
    } catch (_) {}
    final m = _asMap(product);
    if (m != null) {
      final raw = m['category'] ??
          m['kategori'] ??
          m['product_category'] ??
          m['category_slug'] ??
          m['category_name'];
      final parsed = ProductCategoryX.fromAny(raw);
      if (parsed != null) return parsed;
      if (m['category'] is Map) {
        final c = Map<String, dynamic>.from(m['category'] as Map);
        final parsed2 = ProductCategoryX.fromAny(c['slug'] ?? c['name']);
        if (parsed2 != null) return parsed2;
      }
    }
    return null;
  }

  List<String> _extractImageUrls(dynamic product) {
    final p = Pread.from(product);
    final List<String> urls = [];
    final m = _asMap(product);
    if (m != null) {
      for (final k in const ['imageUrls', 'images', 'photos', 'gallery', 'galleries']) {
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

  double _toPct(num? v) => (v ?? 0).toDouble().clamp(0.0, 100.0);
  Color _freshnessColor(double pct) {
    if (pct >= 80) return const Color(0xFF2e7d32);
    if (pct >= 60) return const Color(0xFF43a047);
    if (pct >= 40) return const Color(0xFFfb8c00);
    return const Color(0xFFe53935);
  }

  IconData _freshnessIcon(double pct) {
    if (pct >= 80) return Icons.sentiment_very_satisfied;
    if (pct >= 60) return Icons.sentiment_satisfied;
    if (pct >= 40) return Icons.sentiment_neutral;
    return Icons.sentiment_dissatisfied;
  }

  List<Product> get _relatedBySeller {
    final prov = context.read<ProductProvider>();
    final curr = Pread.from(widget.product);
    return prov.products
        .where((x) => x.id != curr.id && (x.sellerId ?? 0) == (curr.sellerId ?? 0))
        .take(6)
        .toList();
  }

  // ====== COMPAT HELPERS untuk CartProvider (dipakai tombol 'Tambah ke Keranjang') ======
  Future<bool> _cartAddCompat(int productId, int qty) async {
    final c = context.read<CartProvider>() as dynamic;
    // 1) add(productId, qty)
    try {
      final r = c.add(productId, qty);
      if (r is Future) await r;
      return true;
    } catch (_) {}
    // 2) addToCart(productId, qty: qty)
    try {
      final r = c.addToCart(productId: productId, qty: qty);
      if (r is Future) await r;
      return true;
    } catch (_) {}
    // 3) add(productId: , qty: )
    try {
      final r = c.add(productId: productId, qty: qty);
      if (r is Future) await r;
      return true;
    } catch (_) {}
    // 4) add(product_id: , quantity: )
    try {
      final r = c.add(product_id: productId, quantity: qty);
      if (r is Future) await r;
      return true;
    } catch (_) {}
    return false;
  }

  void _selectOnlyCompatByProduct(int productId) {
    final c = context.read<CartProvider>() as dynamic;
    try {
      c.selectOnlyByProductId(productId);
      return;
    } catch (_) {}
    try {
      c.selectOnly(productId);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final nf = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    // =========== Normalisasi produk ===========    // (data sinkron oleh caller)
    final p = Pread.from(widget.product);
    final images = _extractImageUrls(widget.product);

    final name = p.name;
    final price = _toNum(p.price);
    final unit = (p.unit?.toString().trim().isNotEmpty == true) ? p.unit.toString() : 'unit';
    final store = '${p.store}'.trim().toLowerCase() == 'null' ? '' : '${p.store}'.trim();
    final sold = _soldCountOf(widget.product);
    final stock = _stockOf(widget.product);

    // kategori
    final catEnum = _categoryEnumOf(widget.product);
    final catStr = _categoryOf(widget.product);
    final catLabel = catEnum?.label ?? (catStr.isNotEmpty ? catStr : '');

    // deskripsi
    final descRaw = (p.description ?? '').toString();

    // ✅ tips penyimpanan awal dari Pread (fallback)
    final tipsFallback = p.storageNotes;

    final pct = _toPct(p.freshnessScore);
    final label = p.freshnessLabel ?? _defaultFreshnessLabel(pct);

    // Total realtime (harga x qty)
    final totalPrice = price * _quantity;

    // ======== ambil storage field dari detail (jika ada) ========
    final d = _detail ?? const <String, dynamic>{};
    final storageMethod = (d['storage_method'] ?? '').toString();
    final storageTipsFromDetail = (d['storage_tips'] ?? '').toString();
    final storageMethodLabel = _storageMethodLabel(storageMethod);
    final storageTextMerged = (() {
      // Prioritas: detail tips -> fallback Pread
      if (storageTipsFromDetail.trim().isNotEmpty) {
        return storageTipsFromDetail.trim();
      }
      return tipsFallback.trim();
    })();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: CustomScrollView(
        slivers: [
            // ===== HEADER / GALLERY =====
            SliverAppBar(
              expandedHeight: 350,
              pinned: true,
              backgroundColor: const Color(0xFF2e7d32),
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                IconButton(
                  icon: Icon(_isFavorite ? Icons.favorite : Icons.favorite_border, color: Colors.white),
                  onPressed: () => setState(() => _isFavorite = !_isFavorite),
                ),
                IconButton(
                  icon: const Icon(Icons.share_outlined, color: Colors.white),
                  onPressed: () {},
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  children: [
                    ClipRRect(
                      child: images.isEmpty
                          ? Container(
                              color: Colors.grey[300],
                              child: const Center(
                                  child: Icon(Icons.image_not_supported, size: 64, color: Colors.white)),
                            )
                          : CarouselSlider(
                              items: images.map((url) {
                                final fixed = fixImageUrl(url);
                                if (fixed.isEmpty) {
                                  return Container(
                                    color: Colors.grey[300],
                                    child: const Center(
                                        child: Icon(Icons.image_not_supported, size: 64, color: Colors.white)),
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
                              carouselController: _carouselController,
                              options: CarouselOptions(
                                height: double.infinity,
                                viewportFraction: 1.0,
                                enableInfiniteScroll: images.length > 1,
                                onPageChanged: (i, _) => setState(() => _currentIndex = i),
                              ),
                            ),
                    ),
                    if (images.length > 1)
                      Positioned(
                        bottom: 20,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: images.asMap().entries.map((e) {
                            final active = _currentIndex == e.key;
                            return Container(
                              width: active ? 22 : 8,
                              height: 8,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(active ? 1 : .4),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ===== BODY =====
            SliverToBoxAdapter(
              child: Container(
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ---------- Main Info ----------
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Name + chips
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name.isNotEmpty ? name : '-',
                                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 6),

                                    // ✅ CategoryChip + fallback string
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        if (catEnum != null) CategoryChip(category: catEnum!),
                                        if (catEnum == null && catLabel.isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF2e7d32).withOpacity(0.10),
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: const Color(0xFF2e7d32).withOpacity(.35)),
                                            ),
                                            child: Text(
                                              catLabel,
                                              style: const TextStyle(
                                                  fontSize: 12, color: Color(0xFF2e7d32), fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                        if (store.isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration:
                                                BoxDecoration(color: Colors.blue.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.storefront, size: 14, color: Colors.blue),
                                                const SizedBox(width: 4),
                                                Text(
                                                  store,
                                                  style: const TextStyle(
                                                      fontSize: 12, color: Colors.blue, fontWeight: FontWeight.w600),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                ),
                              ),
                              if (store.isEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(color: Colors.blue.withOpacity(0.08), borderRadius: BorderRadius.circular(20)),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.storefront, size: 14, color: Colors.blue),
                                      const SizedBox(width: 4),
                                      Text((p.sellerId == null || p.sellerId == 0) ? 'Toko' : 'Seller #${p.sellerId}',
                                          style: const TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Price + Stock (FIX)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Kelompok harga + satuan dengan baseline alignment
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    nf.format(price),
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2e7d32),
                                    ),
                                  ),
                                  Text(
                                    ' /$unit',
                                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                                  ),
                                ],
                              ),

                              const Spacer(),

                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.shopping_bag_outlined, size: 14, color: Colors.grey[600]),
                              const SizedBox(width: 6),
                              Text('$sold terjual', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // ---------- AI Freshness ----------
                          Builder(
                            builder: (context) {
                              final c = _freshnessColor(pct);
                              return Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                      colors: [c.withOpacity(0.10), c.withOpacity(0.05)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: c.withOpacity(0.3)),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                          child: Icon(_freshnessIcon(pct), color: c, size: 28),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(children: const [
                                                Icon(Icons.auto_awesome, size: 16, color: Colors.amber),
                                                SizedBox(width: 4),
                                                Text('AI Freshness Analysis',
                                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                              ]),
                                              const SizedBox(height: 4),
                                              Text(label,
                                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c)),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          children: [
                                            Text('${pct.toStringAsFixed(0)}%',
                                                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: c)),
                                            Text('Kesegaran', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: LinearProgressIndicator(
                                        value: pct / 100,
                                        minHeight: 8,
                                        backgroundColor: Colors.grey[300],
                                        valueColor: AlwaysStoppedAnimation<Color>(c),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('Dipanen: -', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                                        Text('Exp: -', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 20),

                          // ---------- Store Info ----------
                          InkWell(
                            onTap: () {},
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey[200]!),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                        color: const Color(0xFF2e7d32).withOpacity(0.1), shape: BoxShape.circle),
                                    child: const Icon(Icons.store, color: Color(0xFF2e7d32)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          store.isNotEmpty
                                              ? store
                                              : ((p.sellerId == null || p.sellerId == 0) ? 'Toko' : 'Seller #${p.sellerId}'),
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            const Icon(Icons.star, size: 14, color: Colors.amber),
                                            const SizedBox(width: 4),
                                            Text('4.8',
                                                style: TextStyle(
                                                    fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
                                            const SizedBox(width: 8),
                                            const Text('• 500+ Terjual', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.chevron_right, color: Colors.grey[400]),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ---------- Deskripsi + Nutrisi + (baru) Tips Penyimpanan ----------
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Section(
                            title: 'Deskripsi',
                            child: Text(
                              descRaw.trim().isNotEmpty ? descRaw.trim() : '—',
                              style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.5),
                            ),
                            loading: false,
                            error: null,
                            emptyText: 'Tidak ada deskripsi.',
                          ),
                          const SizedBox(height: 16),

                          // === Informasi Nutrisi dari detail API ===
                          _Section(
                            title: 'Informasi Nutrisi',
                            child: _buildNutritionPanel(p, _detail),
                            loading: _loadingDetail,
                            error: null, // biarkan null agar tetap tampil fallback jika error
                            emptyText: 'Tidak ada data nutrisi.',
                          ),
                          const SizedBox(height: 12),

                          // === Saran Penyimpanan (method + tips) ===
                          _Section(
                            title: 'Saran Penyimpanan',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  storageMethodLabel,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  storageTextMerged.trim().isEmpty ? '—' : storageTextMerged.trim(),
                                  style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.5),
                                ),
                              ],
                            ),
                            loading: _loadingDetail,
                            error: null,
                            emptyText: 'Tidak ada saran penyimpanan.',
                          ),

                          // ====== ULASAN PRODUK ======
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Text(
                              'Ulasan Pembeli',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ProductReviewsSection(
                            productId: _asInt(p.id),
                          ),
                        ],
                      ),
                    ),

                    // ---------- Related ----------
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(20),
                      color: Colors.white,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Produk Serupa', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              TextButton(
                                onPressed: () {},
                                child: const Text('Lihat Semua', style: TextStyle(color: Color(0xFF2e7d32))),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 240,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _relatedBySeller.length,
                              itemBuilder: (context, index) {
                                final rp = _relatedBySeller[index];
                                final rpP = Pread.from(rp);
                                final rImages = _extractImageUrls(rp);
                                final rUrl = rImages.isNotEmpty ? fixImageUrl(rImages.first) : '';
                                final rPct = _toPct(rpP.freshnessScore);

                                return GestureDetector(
                                  onTap: () => Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(builder: (_) => BuyerProductDetailScreen(product: rp)),
                                  ),
                                  child: Container(
                                    width: 150,
                                    margin: const EdgeInsets.only(right: 16),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.grey[200]!),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.05),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        )
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        ClipRRect(
                                          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                          child: Stack(
                                            children: [
                                              rUrl.isEmpty
                                                  ? Container(
                                                      height: 120,
                                                      color: Colors.grey[300],
                                                      child: const Center(child: Icon(Icons.image_not_supported)),
                                                    )
                                                  : Image.network(
                                                      rUrl,
                                                      height: 120,
                                                      width: double.infinity,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (_, __, ___) => Container(
                                                        height: 120,
                                                        color: Colors.grey.shade200,
                                                        alignment: Alignment.center,
                                                        child: const Icon(Icons.broken_image, color: Colors.black45),
                                                      ),
                                                    ),
                                              Positioned(
                                                top: 8,
                                                right: 8,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: _freshnessColor(rPct),
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: Text(
                                                    '${rPct.toStringAsFixed(0)}%',
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.white,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                rpP.name.isNotEmpty ? rpP.name : '-',
                                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${rpP.unit}',
                                                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                nf.format(_toNum(rpP.price)),
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF2e7d32),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 100), // ruang bar bawah
                  ],
                ),
              ),
            ),
        ],
      ),

      // ===== Bottom Bar: Stepper + Total + CTA =====
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                offset: const Offset(0, -2),
                blurRadius: 10,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Row 1: Stepper Qty + Total
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _qtyStepper(stock),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text(
                          nf.format(totalPrice),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2e7d32),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Row 2: Dua tombol (Outlined + Elevated)
              Row(
                children: [
                  // ===== Tambah ke Keranjang =====
                  Expanded(
                    child: OutlinedButton(
                      onPressed: (stock <= 0)
                          ? null
                          : () async {
                              final prodId = _asInt(p.id);
                              if (prodId <= 0) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context)
                                  ..clearSnackBars()
                                  ..showSnackBar(const SnackBar(
                                    content: Text('Produk tidak valid.'),
                                    behavior: SnackBarBehavior.floating,
                                    margin: EdgeInsets.only(left: 16, right: 16, bottom: 80),
                                    backgroundColor: Colors.red,
                                  ));
                                return;
                              }

                              final ok = await _cartAddCompat(prodId, _quantity);

                              if (!mounted) return;
                              if (ok) {
                                ScaffoldMessenger.of(context)
                                  ..clearSnackBars()
                                  ..showSnackBar(const SnackBar(
                                    content: Text('Berhasil ditambahkan'),
                                    behavior: SnackBarBehavior.floating,
                                    margin: EdgeInsets.only(left: 16, right: 16, bottom: 80),
                                  ));
                              } else {
                                ScaffoldMessenger.of(context)
                                  ..clearSnackBars()
                                  ..showSnackBar(const SnackBar(
                                    content: Text('Gagal menambahkan ke keranjang.'),
                                    behavior: SnackBarBehavior.floating,
                                    margin: EdgeInsets.only(left: 16, right: 16, bottom: 80),
                                    backgroundColor: Colors.red,
                                  ));
                              }
                            },
                      child: const Text('Tambah ke Keranjang'),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // ===== Beli Sekarang → tambah & ambil cart_item_id → seleksi → Checkout =====
                  Expanded(
                    child: ElevatedButton(
                      onPressed: (stock <= 0)
                          ? null
                          : () async {
                              final prodId = _asInt(p.id);
                              if (prodId <= 0) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                  content: Text('Produk tidak valid.'),
                                  behavior: SnackBarBehavior.floating,
                                ));
                                return;
                              }

                              try {
                                // 1) Tambah ke cart & ambil ID item (kompat ke beberapa signature)
                                int cartItemId = await _addToCartAndGetIdCompat(prodId, _quantity);

                                if (cartItemId <= 0) {
                                  throw Exception('Tidak mendapat ID item keranjang');
                                }

                                // 2) Seleksi hanya item ini di provider
                                final cart = context.read<CartProvider>() as dynamic;
                                bool selected = false;
                                try {
                                  cart.selectOnly({cartItemId});
                                  selected = true;
                                } catch (_) {}
                                if (!selected) {
                                  try {
                                    cart.setSelectedIds({cartItemId});
                                    selected = true;
                                  } catch (_) {}
                                }
                                if (!selected) {
                                  try {
                                    cart.clearSelection();
                                  } catch (_) {}
                                  try {
                                    cart.toggleSelect(cartItemId, true);
                                    selected = true;
                                  } catch (_) {}
                                }

                                if (!mounted) return;
                                // 3) Arahkan ke Checkout dengan membawa cart_item_id
                                Navigator.pushNamed(
                                  context,
                                  '/checkout',
                                  arguments: {
                                    'cart_item_ids': [cartItemId],
                                    'source': 'buy_now',
                                  },
                                );
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text('Gagal Beli Sekarang: $e'),
                                  behavior: SnackBarBehavior.floating,
                                  backgroundColor: Colors.red,
                                ));
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

  // ===== widgets kecil =====
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

  // ========== NEW: Nutrisi & Penyimpanan dari DETAIL API ==========
  Widget _buildNutritionPanel(Pread p, Map<String, dynamic>? detail) {
    // Fallback deskriptif lama
    final noteFallback = p.nutritionNote.trim();

    // Jika detail belum ada, fallback ke daftar teks lama
    if (detail == null || detail.isEmpty) {
      if (noteFallback.isEmpty) return const Text('Tidak ada data nutrisi.');
      final sep = noteFallback.contains(';') ? ';' : ',';
      final items = noteFallback.split(sep).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      return _bulletedList(items);
    }

    // Ambil angka-angka dari detail (sesuai kolom DB/API)
    final calories = _toD(detail['calories_kcal']);
    final proteinG = _toD(detail['protein_g']);
    final vitaminC = _toD(detail['vitamin_c_mg']);
    final fiberG   = _toD(detail['fiber_g']);

    // Ambil deskriptif, kalau kosong fallback ke note lama
    final nutritionDesc = (detail['nutrition'] ?? '').toString().trim();
    final descList = (nutritionDesc.isNotEmpty ? nutritionDesc : noteFallback)
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final chips = <Widget>[];
    if (calories != null) chips.add(_metricChip('${calories.toStringAsFixed(0)} kkal'));
    if (proteinG != null) chips.add(_metricChip('${_trim0(proteinG)} g protein'));
    if (vitaminC != null) chips.add(_metricChip('${_trim0(vitaminC)} mg Vit C'));
    if (fiberG   != null) chips.add(_metricChip('${_trim0(fiberG)} g serat'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (chips.isNotEmpty) Wrap(spacing: 8, runSpacing: 6, children: chips),
        if (descList.isNotEmpty) ...[
          if (chips.isNotEmpty) const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: descList.map((t) => Chip(label: Text(t))).toList(),
          ),
        ],
        if (chips.isEmpty && descList.isEmpty) const Text('Tidak ada data nutrisi.'),
      ],
    );
  }

  Widget _bulletedList(List<String> items) {
    if (items.isEmpty) return const Text('Tidak ada data nutrisi.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items
          .map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Padding(padding: EdgeInsets.only(top: 7), child: Icon(Icons.circle, size: 6)),
                  SizedBox(width: 8),
                ],
              ),
            ),
          )
          .toList()
          .asMap()
          .entries
          .map((entry) {
            final e = items[entry.key];
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(padding: EdgeInsets.only(top: 7), child: Icon(Icons.circle, size: 6)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(e, style: const TextStyle(fontSize: 14))),
                ],
              ),
            );
          })
          .toList(),
    );
  }

  Widget _metricChip(String text) {
    return Chip(
      label: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: const Color(0xFF2e7d32).withOpacity(.08),
      side: BorderSide(color: const Color(0xFF2e7d32).withOpacity(.35)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }

  String _trim0(num n) {
    final s = n.toString();
    if (s.endsWith('.0')) return s.substring(0, s.length - 2);
    return s;
  }

  String _storageMethodLabel(String? m) {
    switch ((m ?? '').trim()) {
      case 'chiller':
        return 'Chiller / Lemari Pendingin';
      case 'freezer':
        return 'Freezer';
      case 'dry':
        return 'Kering / Kedap';
      case 'room':
        return 'Suhu Ruang';
      case 'other':
      case '':
      case null:
        return 'Metode penyimpanan tidak ditentukan';
      default:
        return m!;
    }
  }

  // ---------- Nutrisi berwarna + ikon berbeda (dipertahankan untuk kompat) ----------
  Widget _buildNutritionColored(dynamic nutrit) {
    // Jika String: tampilkan chip netral
    if (nutrit is String) {
      final s = nutrit.trim();
      if (s.isEmpty) return const Text('Tidak ada data nutrisi.');
      return Wrap(spacing: 8, runSpacing: 8, children: [
        _NutrChip(icon: Icons.info_outline, label: 'Nutrisi', value: s, color: Colors.grey),
      ]);
    }

    final src = _asMap(nutrit) ?? {};
    if (src.isEmpty) return const Text('Tidak ada data nutrisi.');

    // Alias -> label kanonik
    final Map<String, String> aliasToCanon = {
      'vitaminc': 'Vitamin C',
      'vitamin_c': 'Vitamin C',
      'vitc': 'Vitamin C',
      'vitamin_c_mg': 'Vitamin C',
      'vitamina': 'Vitamin A',
      'vitamin_a': 'Vitamin A',
      'vit_a': 'Vitamin A',
      'serat': 'Serat',
      'fiber': 'Serat',
      'fiber_g': 'Serat',
      'kalium': 'Kalium',
      'potassium': 'Kalium',
      'zatbesi': 'Zat Besi',
      'iron': 'Zat Besi',
      'ferum': 'Zat Besi',
      'antioksidan': 'Antioksidan',
      'antioxidant': 'Antioksidan',
      'antioxidants': 'Antioksidan',
      'kalsium': 'Kalsium',
      'calcium': 'Kalsium',
      'protein': 'Protein',
      'protein_g': 'Protein',
      'magnesium': 'Magnesium',
      'folat': 'Folat',
      'folate': 'Folat',
    };

    // Style per nutrisi
    const Map<String, _NutrStyle> styles = {
      'Vitamin C': _NutrStyle(icon: Icons.medication_liquid, color: Colors.orange),
      'Vitamin A': _NutrStyle(icon: Icons.visibility, color: Colors.amber),
      'Serat': _NutrStyle(icon: Icons.eco_rounded, color: Colors.green),
      'Kalium': _NutrStyle(icon: Icons.bolt, color: Colors.purple),
      'Zat Besi': _NutrStyle(icon: Icons.hardware, color: Colors.blueGrey),
      'Antioksidan': _NutrStyle(icon: Icons.shield, color: Colors.indigo),
      'Kalsium': _NutrStyle(icon: Icons.water_drop, color: Colors.cyan),
      'Protein': _NutrStyle(icon: Icons.egg_alt, color: Colors.blue),
      'Magnesium': _NutrStyle(icon: Icons.bubble_chart, color: Colors.teal),
      'Folat': _NutrStyle(icon: Icons.spa, color: Colors.lightGreen),
    };

    String norm(String k) => k.toString().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
    final Map<String, String> canonValues = {}; // label -> value

    src.forEach((k, v) {
      final key = norm(k);
      final canon = aliasToCanon[key];
      final value = (v ?? '').toString().trim();
      if (canon != null && value.isNotEmpty) {
        canonValues.putIfAbsent(canon, () => value);
      }
    });

    // Urutan tampil
    const order = [
      'Vitamin C',
      'Vitamin A',
      'Serat',
      'Kalium',
      'Zat Besi',
      'Antioksidan',
      'Kalsium',
      'Protein',
      'Magnesium',
      'Folat'
    ];

    final chips = <Widget>[];
    for (final label in order) {
      final val = canonValues[label];
      if (val == null || val.isEmpty) continue;
      final sty = styles[label]!;
      chips.add(_NutrChip(icon: sty.icon, label: label, value: val, color: sty.color));
    }

    // Sisanya yang tidak terpetakan -> chip netral
    src.forEach((k, v) {
      final key = norm(k);
      if (aliasToCanon.containsKey(key)) return;
      final value = (v ?? '').toString().trim();
      if (value.isEmpty) return;
      chips.add(_NutrChip(icon: Icons.info_outline, label: _labelizeKey(k), value: value, color: Colors.grey));
    });

    if (chips.isEmpty) return const Text('Tidak ada data nutrisi.');
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  String _labelizeKey(String key) {
    final s = key.replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.isEmpty) return 'Nutrisi';
    return s.split(' ').map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
  }

  String _defaultFreshnessLabel(double pct) {
    if (pct >= 80) return 'Sangat Layak';
    if (pct >= 60) return 'Layak';
    if (pct >= 40) return 'Meragukan';
    return 'Kurang Layak';
  }
}

class _Section extends StatelessWidget {
  const _Section({
    Key? key,
    required this.title,
    required this.child,
    required this.loading,
    required this.error,
    required this.emptyText,
  }) : super(key: key);

  final String title;
  final Widget child;
  final bool loading;
  final String? error;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = theme.cardColor;                  // pengganti AppColors.card
    final borderColor = theme.dividerColor;             // pengganti AppColors.cardBorder

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (loading) const _SkeletonLines(),
          if (!loading && (error != null)) Text(error!, style: const TextStyle(color: Colors.red)),
          if (!loading && error == null)
            Builder(
              builder: (context) {
                // Cek apakah konten kosong (misal hanya '—')
                final asText = (child is Text) ? (child as Text).data ?? '' : '';
                if (asText.trim().isEmpty || asText.trim() == '—') {
                  return Text(emptyText, style: const TextStyle(color: Colors.grey));
                }
                return child;
              },
            ),
        ],
      ),
    );
  }
}

class _SkeletonLines extends StatelessWidget {
  const _SkeletonLines({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final skeletonColor = Colors.grey.shade300; // pengganti AppColors.skeleton
    return Column(
      children: List.generate(
        3,
        (i) => Container(
          height: 12,
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: skeletonColor,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}

class _NutrChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _NutrChip({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: CircleAvatar(backgroundColor: color.withOpacity(.15), child: Icon(icon, color: color, size: 16)),
      label: Text('$label: $value', style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      backgroundColor: color.withOpacity(.08),
      side: BorderSide(color: color.withOpacity(.35)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }
}

class _NutrStyle {
  final IconData icon;
  final Color color;
  const _NutrStyle({required this.icon, required this.color});
}
