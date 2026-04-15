// lib/app/common/models/product_model.dart
import 'dart:convert';
import 'product_category.dart';

/// =======================
/// Model lengkap: Product
/// =======================
class Product {
  // ==== ID & seller ====
  final int? id; // dibuat nullable (sesuai instruksi)
  final int? sellerId;

  // ==== Basic ====
  String? name;
  String? category; // string lama (dipertahankan)
  final ProductCategory? categoryEnum; // enum baru (opsional)
  double? price;
  String? unit;
  int? stock;
  String? description;

  // ==== Kelayakan ====
  double? freshnessScore; // 0..100
  String? freshnessLabel;

  // ==== Nutrisi ====
  /// Array JSON (baru) — sesuai schema server terkini.
  /// Contoh: ["Kalori","Protein","Vitamin C"]
  List<String>? nutrition;

  /// Kompat lama: jika UI lama masih butuh string, gunakan getter `nutritionString`.
  String get nutritionString =>
      (nutrition == null || nutrition!.isEmpty) ? '' : nutrition!.join(', ');

  // ==== Penyimpanan ====
  String? storageTips;

  // ==== Gambar ====
  /// URL gambar utama (absolut dari API)
  String? imageUrl;

  /// Daftar URL gambar tambahan
  final List<String> imagesUrls;

  // ==== Meta toko / status ====
  final String? storeName;
  final int? soldCount;
  final String? status;
  bool? isActive; // baru

  // ==== Waktu ====
  final DateTime? createdAt;

  Product({
    this.id,
    this.name,
    this.category,
    this.categoryEnum,
    this.price,
    this.unit,
    this.stock,
    this.description,
    this.freshnessScore,
    this.freshnessLabel,
    this.nutrition,
    this.storageTips,
    this.imageUrl,
    this.imagesUrls = const [],
    this.sellerId,
    this.storeName,
    this.soldCount,
    this.status,
    this.isActive,
    this.createdAt,
  });

  // ==== Helper nilai inventori ====
  double get inventoryValue => (price ?? 0) * (stock ?? 0);

  // ------------------------
  // Parsing helper functions
  // ------------------------
  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static bool? _toBool(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().trim().toLowerCase();
    if (s == 'true' || s == '1' || s == 'yes' || s == 'y') return true;
    if (s == 'false' || s == '0' || s == 'no' || s == 'n') return false;
    return null;
  }

  static String? _firstString(Map<String, dynamic> j, List<String> keys) {
    for (final k in keys) {
      final v = j[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  static dynamic _first(Map<String, dynamic> j, List<String> keys) {
    for (final k in keys) {
      if (j.containsKey(k) && j[k] != null) return j[k];
    }
    return null;
  }

  static List<String> _parseImages(dynamic raw) {
    // Terima:
    // - List<dynamic> → map ke List<String>
    // - String JSON list → parse
    // - String biasa → diabaikan (kecuali JSON list)
    if (raw == null) return const <String>[];

    if (raw is List) {
      return raw
          .map((e) => e?.toString() ?? '')
          .where((s) => s.trim().isNotEmpty)
          .cast<String>()
          .toList();
    }

    if (raw is String && raw.isNotEmpty) {
      try {
        final parsed = jsonDecode(raw);
        if (parsed is List) {
          return parsed
              .map((e) => e?.toString() ?? '')
              .where((s) => s.trim().isNotEmpty)
              .cast<String>()
              .toList();
        }
      } catch (_) {/* bukan JSON list */}
    }
    return const <String>[];
  }

  static List<String>? _parseNutrition(dynamic raw) {
    if (raw == null) return null;

    if (raw is List) {
      final out = raw
          .map((e) => e?.toString().trim() ?? '')
          .where((s) => s.isNotEmpty)
          .cast<String>()
          .toList();
      return out.isEmpty ? null : out;
    }

    if (raw is String) {
      final t = raw.trim();
      if (t.isEmpty) return null;
      // Jika string JSON array
      if (t.startsWith('[') && t.endsWith(']')) {
        try {
          final decoded = (jsonDecode(t) as List?)
                  ?.map((e) => e?.toString() ?? '')
                  .toList() ??
              <String>[];
          final out =
              decoded.map((e) => e.trim()).where((s) => s.isNotEmpty).toList();
          return out.isEmpty ? null : out;
        } catch (_) {
          // fallback: split comma
          final out = t
              .split(RegExp(r'[;,]'))
              .map((e) => e.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          return out.isEmpty ? null : out;
        }
      }
      // Bukan JSON array → split komponen
      final out = t
          .split(RegExp(r'[;,]'))
          .map((e) => e.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      return out.isEmpty ? null : out;
    }

    // Coba decode generik
    try {
      final parsed = jsonDecode(raw.toString());
      if (parsed is List) {
        final out = parsed
            .map((e) => e?.toString().trim() ?? '')
            .where((s) => s.isNotEmpty)
            .cast<String>()
            .toList();
        return out.isEmpty ? null : out;
      }
    } catch (_) {}

    return null;
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    // === Kumpulkan daftar gambar dari beragam kunci ===
    final List<String> images = [];
    void addImages(dynamic v) => images.addAll(_parseImages(v));

    addImages(_first(json, [
      'images_urls',
      'image_urls',
      'images',
      'photos',
      'gallery',
      'pictures',
      'imgs'
    ]));

    // === Tentukan primary image (fleksibel: camelCase & snake_case) ===
    final primary = _firstString(json, [
          'primaryImageUrl',
          'image_url',
          'primary_image_url',
          'image',
          'photo_url',
          'thumbnail',
          'thumb',
          'cover',
        ]) ??
        (images.isNotEmpty ? images.first : null);

    // === Category: dukung string / map / slug / alias kunci ===
    final dynamic catRaw = _first(json, [
      'category',
      'kategori',
      'product_category',
      'category_slug',
      'categoryName',
      'category_name',
    ]);
    final ProductCategory? catEnum = ProductCategoryX.fromAny(catRaw);
    String? catString() {
      if (catRaw == null) return null;
      if (catRaw is String && catRaw.trim().isNotEmpty) return catRaw.toString();
      if (catEnum != null) return catEnum.label;
      return null;
    }

    // === Nutrition fleksibel ===
    final nutritionList =
        _parseNutrition(_first(json, ['nutrition', 'nutrisi', 'nutrition_list']));

    // === Store name fleksibel (string / object) ===
    String? _extractStoreName(dynamic v) {
      if (v == null) return null;
      if (v is String && v.trim().isNotEmpty) return v.trim();
      if (v is Map<String, dynamic>) {
        return _firstString(v, ['name', 'store_name', 'nama', 'title']);
      }
      return v.toString().trim().isNotEmpty ? v.toString().trim() : null;
    }

    // === Build object ===
    return Product(
      id: _toInt(_first(json, ['id'])),
      sellerId: _toInt(_first(json, ['seller_id', 'sellerId', 'store_id'])),
      name: _firstString(json, ['name', 'product_name', 'title']),
      category: catString(),
      categoryEnum: catEnum,
      price: _toDouble(_first(json, ['price', 'harga'])),
      unit: _firstString(json, ['unit', 'satuan']),
      stock: _toInt(_first(json, ['stock', 'qty', 'quantity'])),
      description: _firstString(json, ['description', 'deskripsi', 'desc']),

      // Tambah alias suitability_percent untuk kompat server
      freshnessScore: _toDouble(_first(json, [
        'freshness_score',
        'freshnessScore',
        'suitability_percent',
        'suitabilityPercent',
      ])),
      freshnessLabel: _firstString(json, ['freshness_label', 'freshnessLabel']),

      nutrition: nutritionList,
      storageTips: _firstString(json, ['storage_tips', 'storageTips']),

      imageUrl: primary,
      imagesUrls: images,

      storeName: _extractStoreName(_first(json, [
        'store_name',
        'storeName',
        'store',
        'seller_name',
        'sellerName',
      ])),
      soldCount: _toInt(_first(json, ['sold_count', 'soldCount'])),
      status: _firstString(json, ['status']),
      isActive: _toBool(_first(json, ['is_active', 'isActive'])) ?? true,

      createdAt: () {
        final raw = _first(json, ['created_at', 'createdAt']);
        return raw != null ? DateTime.tryParse(raw.toString()) : null;
      }(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'seller_id': sellerId,
        'name': name,
        // kirim string category untuk kompat
        'category': category ?? categoryEnum?.label,
        // tambahan: slug kategori bila pakai enum
        'category_slug': categoryEnum?.slug,
        'price': price,
        'unit': unit,
        'stock': stock,
        'description': description,
        'freshness_score': freshnessScore,
        'freshness_label': freshnessLabel,
        // kirim sebagai array JSON (baru)
        'nutrition': nutrition,
        'storage_tips': storageTips,
        'image_url': imageUrl,
        // tetap pakai "images_urls" (sesuai server), bisa diduplikasi jadi "image_urls" bila perlu
        'images_urls': imagesUrls,
        'store_name': storeName,
        'sold_count': soldCount,
        'status': status,
        'is_active': isActive,
        'created_at': createdAt?.toIso8601String(),
        // Tambahan kompat: banyak endpoint baru pakai integer 0..100
        'suitability_percent':
            freshnessScore != null ? freshnessScore!.round() : null,
      };

  // ============================
  // 🔁 Backward-compat & helpers
  // ============================

  /// Alias agar kode lama `primaryImageUrl` tetap jalan.
  String? get primaryImageUrl => imageUrl;

  /// Banyak widget lama pakai `freshnessPercentage` → alias ke `freshnessScore`.
  double get freshnessPercentage => freshnessScore ?? 0.0;

  /// Alias untuk komponen yang mengakses `product.imageUrls`
  List<String> get imageUrls => imagesUrls;

  /// Nilai fallback aman untuk dipakai langsung di UI
  String get nameSafe => name ?? '-';
  double get priceSafe => price ?? 0.0;
  int get stockSafe => stock ?? 0;
  String get unitSafe => unit ?? '';
  String get categorySafe =>
      (category?.trim().isNotEmpty == true)
          ? category!.trim()
          : (categoryEnum?.label ?? '');
  String get storeNameSafe => storeName ?? '';
  String get imageUrlSafe => imageUrl ?? (imagesUrls.isNotEmpty ? imagesUrls.first : '');

  /// Alias praktis untuk UI baru (int 0..100)
  int get suitabilityPercent =>
      ((freshnessScore ?? 0).toDouble()).clamp(0.0, 100.0).round();

  /// Kompatibel dengan service lama
  factory Product.fromApi(Map<String, dynamic> json) => Product.fromJson(json);

  Product copyWith({
    int? id,
    int? sellerId,
    String? name,
    String? category,
    ProductCategory? categoryEnum,
    double? price,
    String? unit,
    int? stock,
    String? description,
    double? freshnessScore,
    String? freshnessLabel,
    List<String>? nutrition,
    String? storageTips,
    String? imageUrl,
    List<String>? imagesUrls,
    String? storeName,
    int? soldCount,
    String? status,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return Product(
      id: id ?? this.id,
      sellerId: sellerId ?? this.sellerId,
      name: name ?? this.name,
      category: category ?? this.category,
      categoryEnum: categoryEnum ?? this.categoryEnum,
      price: price ?? this.price,
      unit: unit ?? this.unit,
      stock: stock ?? this.stock,
      description: description ?? this.description,
      freshnessScore: freshnessScore ?? this.freshnessScore,
      freshnessLabel: freshnessLabel ?? this.freshnessLabel,
      nutrition: nutrition ?? this.nutrition,
      storageTips: storageTips ?? this.storageTips,
      imageUrl: imageUrl ?? this.imageUrl,
      imagesUrls: imagesUrls ?? this.imagesUrls,
      storeName: storeName ?? this.storeName,
      soldCount: soldCount ?? this.soldCount,
      status: status ?? this.status,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() => jsonEncode(toJson());
}

/// ====================================
/// Model ringkas untuk list/tiles: ProductModel
/// ====================================
class ProductModel {
  final int id;
  final String name;
  final String imageUrl;
  final int price;
  final int stock;
  final int suitabilityPercent;

  const ProductModel({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.price,
    required this.stock,
    required this.suitabilityPercent,
  });

  factory ProductModel.fromJson(Map<String, dynamic> j) {
    final img =
        (j['image_url'] ?? j['image'] ?? j['thumbnail'] ?? '') as String? ?? '';
    final s = (j['suitability_percent'] ?? j['freshness_score'] ?? 0) as num;
    return ProductModel(
      id: (j['id'] ?? 0) as int,
      name: (j['name'] ?? '-') as String,
      imageUrl: img,
      price: (j['price'] ?? 0) as int,
      stock: (j['stock'] ?? 0) as int,
      suitabilityPercent: s.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'image_url': imageUrl,
        'price': price,
        'stock': stock,
        'suitability_percent': suitabilityPercent,
      };
}

/// ======================================
/// Ekstensi konversi Product ↔ ProductModel
/// ======================================
extension ProductToModel on Product {
  ProductModel toModel() => ProductModel(
        id: id ?? 0,
        name: nameSafe,
        imageUrl: imageUrlSafe,
        price: priceSafe.toInt(),
        stock: stockSafe,
        suitabilityPercent: suitabilityPercent,
      );
}

extension ProductModelToProduct on ProductModel {
  /// Konversi minimal → cocok untuk list → detail dapat di-hydrate ulang.
  Product toProduct() => Product(
        id: id,
        name: name,
        imageUrl: imageUrl,
        price: price.toDouble(),
        stock: stock,
        freshnessScore: suitabilityPercent.toDouble(),
        // field lain bisa diisi saat fetch detail
      );
}
