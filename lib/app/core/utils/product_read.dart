// lib/app/core/utils/product_read.dart
import 'dart:convert';
import 'url_fix.dart';

num _toNum(dynamic v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? 0;
  return 0;
}

int? _toIntOrNull(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

int _toInt(dynamic v) => _toIntOrNull(v) ?? 0;

Map<String, dynamic> _asMap(dynamic p) {
  if (p is Map<String, dynamic>) return p;

  // coba toJson()
  try {
    final m = (p as dynamic).toJson() as Map<String, dynamic>;
    if (m.isNotEmpty) return m;
  } catch (_) {}

  // fallback ambil getter umum (camelCase)
  final m = <String, dynamic>{};
  try {
    m['id'] = (p as dynamic).id;
  } catch (_) {}
  try {
    m['name'] = (p as dynamic).name;
  } catch (_) {}
  try {
    m['price'] = (p as dynamic).price;
  } catch (_) {}
  try {
    m['unit'] = (p as dynamic).unit;
  } catch (_) {}
  try {
    m['image_url'] = (p as dynamic).imageUrl;
  } catch (_) {}
  try {
    m['images_urls'] = (p as dynamic).imagesUrls;
  } catch (_) {}
  try {
    m['store_name'] = (p as dynamic).storeName;
  } catch (_) {}
  try {
    m['freshness_score'] = (p as dynamic).freshnessScore;
  } catch (_) {}
  try {
    m['freshness_label'] = (p as dynamic).freshnessLabel;
  } catch (_) {}
  try {
    m['description'] = (p as dynamic).description;
  } catch (_) {}
  try {
    m['nutrition'] = (p as dynamic).nutrition;
  } catch (_) {}
  try {
    m['calories_kcal'] = (p as dynamic).caloriesKcal;
  } catch (_) {}
  try {
    m['protein_g'] = (p as dynamic).proteinG;
  } catch (_) {}
  try {
    m['fiber_g'] = (p as dynamic).fiberG;
  } catch (_) {}
  try {
    m['vitamin_c_mg'] = (p as dynamic).vitaminCMg;
  } catch (_) {}
  try {
    m['storage_method'] = (p as dynamic).storageMethod;
  } catch (_) {}
  try {
    m['storage_notes'] = (p as dynamic).storageNotes;
  } catch (_) {}
  try {
    m['storage_tips'] = (p as dynamic).storageTips;
  } catch (_) {}
  try {
    m['seller_id'] = (p as dynamic).sellerId;
  } catch (_) {}
  try {
    m['stock'] = (p as dynamic).stock;
  } catch (_) {}
  try {
    m['category'] = (p as dynamic).category;
  } catch (_) {}
  try {
    m['category_name'] = (p as dynamic).categoryName;
  } catch (_) {}
  return m;
}

class Pread {
  final Map<String, dynamic> m;
  Pread._(this.m);
  factory Pread.from(dynamic product) => Pread._(_asMap(product));

  // basic
  String get id => (m['id'] ?? '').toString();
  String get name => (m['name'] ?? '').toString();
  num get price => _toNum(m['price']);
  String get unit => (m['unit'] ?? 'kg').toString();

  // toko/penjual
  String get store => (m['store_name'] ??
          m['seller_name'] ??
          m['storeName'] ??
          m['seller'] ??
          '')
      .toString();
  int? get sellerId {
    final v = m['seller_id'] ?? m['sellerId'] ?? m['user_id'] ?? m['owner_id'];
    return _toIntOrNull(v);
  }

  // kategori & stok
  String get category {
    final c = m['category'];
    if (c is Map) {
      return (c['name'] ?? c['title'] ?? c['label'] ?? '').toString();
    }
    return (m['category_name'] ?? m['categoryName'] ?? (c ?? '')).toString();
  }

  int get stock => _toInt(m['stock']);

  // freshness
  int get freshnessScore {
    final v = m['freshness_score'];
    if (v is int) return v.clamp(0, 100);
    if (v is num) return v.round().clamp(0, 100);
    return 0;
  }

  String get freshnessLabel => (m['freshness_label'] ?? '').toString();

  // deskripsi
  String get description =>
      (m['description'] ?? m['desc'] ?? 'Tidak ada deskripsi.').toString();

  // ===================== Gambar =====================
  String get imageUrl {
    // dukung beragam nama field dari API / model
    final candidates = [
      m['image_url'],
      m['primary_image_url'],
      m['image_full_url'],
      m['image_url_full'],
      m['image'],
      m['photo'],
      m['thumbnail'],
      m['imageUrl'],
      m['imageURL'],
      m['image_path'],
    ].where((e) => e != null && e.toString().trim().isNotEmpty).toList();

    String raw = candidates.isNotEmpty ? candidates.first.toString() : '';

    // fallback: pakai elemen pertama dari daftar images jika ada
    if (raw.isEmpty) {
      final imgs = images; // sudah difix lewat fixImageUrl di bawah
      if (imgs.isNotEmpty) return imgs.first;
    }
    return fixImageUrl(raw);
  }

  List<String> get images {
    final raw =
        (m['images_urls'] ?? m['image_urls'] ?? m['images'] ?? const []) as Object;

    List list;
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        list = (decoded is List) ? decoded : const [];
      } catch (_) {
        list = const [];
      }
    } else if (raw is List) {
      list = raw;
    } else {
      list = const [];
    }

    return list
        .map((e) => fixImageUrl(e.toString()))
        .where((e) => e.isNotEmpty)
        .toList();
  }

  // nutrisi: Map aman + note jika sumber berupa String/List
  Map<String, dynamic> get nutrition {
    final raw = m['nutrition'];
    Map<String, dynamic> map = const {};
    if (raw is Map) {
      map = Map<String, dynamic>.from(raw);
    }
    // pick juga dari top-level bila ada
    map = {
      'calories_kcal': map['calories_kcal'] ?? m['calories_kcal'],
      'protein_g': map['protein_g'] ?? m['protein_g'],
      'fiber_g': map['fiber_g'] ?? m['fiber_g'],
      'vitamin_c_mg': map['vitamin_c_mg'] ?? m['vitamin_c_mg'],
    }..removeWhere((_, v) => v == null);
    return map;
  }

  String get nutritionNote {
    final raw = m['nutrition'];
    if (raw is String) return raw.trim();
    if (raw is List) return raw.map((e) => e.toString()).join(', ');
    return '';
  }

  // penyimpanan
  String get storageMethod =>
      (m['storage_method'] ?? m['storageMethod'] ?? '').toString();
  String get storageNotes =>
      (m['storage_notes'] ?? m['storage_tips'] ?? '').toString();

  // ===== ALIAS KOMPAT =====
  // Beberapa tempat memakai p.storageTips → arahkan ke storageNotes
  String get storageTips => storageNotes;
}
