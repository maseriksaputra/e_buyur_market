// lib/app/presentation/providers/seller_dashboard_provider.dart
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import '../../core/services/product_api_service.dart';

class SellerDashboardProvider extends ChangeNotifier {
  SellerDashboardProvider(this.api);

  final ProductApiService api;

  // Opsional: jika service butuh token manual
  String? _token;
  void setAuthToken(String? t) => _token = t;

  // ====== Loading & coalescing ======
  bool _loading = false;
  Future<void>? _inflight;
  DateTime? _lastAt;

  bool get isLoading => _loading;

  // Error state
  String? error;

  // Data untuk UI
  List<Map<String, dynamic>> myProducts = <Map<String, dynamic>>[];
  int productCount = 0;
  int stockUnits = 0;
  int stockValueTotal = 0;
  double freshnessAvg = 0;

  /// Muat data dashboard seller (produk + metrik) — non-kedip:
  /// - Tidak mengosongkan list di awal
  /// - Koalesir request berjalan
  /// - Throttle 2 detik
  /// - Rollback bila error
  Future<void> loadDashboard() {
    // 1) Koalesir request yang sedang berjalan
    if (_inflight != null) return _inflight!;

    // 2) Throttle ringan 2 detik
    final now = DateTime.now();
    if (_lastAt != null && now.difference(_lastAt!) < const Duration(seconds: 2)) {
      return Future.value();
    }
    _lastAt = now;

    // 3) Snapshot untuk rollback bila gagal
    final oldProducts = List<Map<String, dynamic>>.from(myProducts);
    final oldProductCount = productCount;
    final oldStockUnits = stockUnits;
    final oldStockValueTotal = stockValueTotal;
    final oldFreshnessAvg = freshnessAvg;

    // 4) Hanya tampilkan spinner jika benar-benar initial load
    final showSpinner = myProducts.isEmpty;
    if (showSpinner) {
      _loading = true;
      error = null;
      notifyListeners();
    } else {
      // bila sudah ada data, jangan blok UI
      error = null;
    }

    _inflight = () async {
      try {
        // 5) Ambil daftar produk seller
        final list = await _getSellerProductsCompat();
        myProducts = list;
        _recalc(); // hitung metrik dasar dari list

        // 6) (opsional) merge summary bila backend menyediakan endpoint ringkas
        try {
          final s = await _getSellerSummaryCompat();
          if (s.isNotEmpty) {
            productCount = (s['product_count'] as int?) ?? productCount;
            stockUnits = (s['stock_units'] as int?) ?? stockUnits;
            stockValueTotal = (s['stock_value_total'] as int?) ?? stockValueTotal;
            final f = s['freshness_avg'];
            if (f is num) freshnessAvg = f.toDouble();
          }
        } on DioException catch (e) {
          // 404 boleh diabaikan (endpoint belum tersedia)
          if (e.response?.statusCode != 404) rethrow;
        }

        error = null;
      } catch (e, st) {
        // 7) Rollback semua state penting
        error = e.toString();
        myProducts = oldProducts;
        productCount = oldProductCount;
        stockUnits = oldStockUnits;
        stockValueTotal = oldStockValueTotal;
        freshnessAvg = oldFreshnessAvg;
        log('SellerDashboardProvider.loadDashboard error: $e\n$st');
      } finally {
        _loading = false;
        _inflight = null;
        notifyListeners();
      }
    }();

    return _inflight!;
  }

  /// === NEW: hapus produk by id (optimistic UI) ===
  Future<bool> deleteProductById(dynamic id) async {
    final intId = _asInt(id);
    if (intId == 0) return false;

    // Optimistic remove + backup untuk rollback
    final idx = myProducts.indexWhere((p) => _asInt(p['id']) == intId);
    Map<String, dynamic>? backup;
    if (idx != -1) {
      backup = myProducts[idx];
      myProducts.removeAt(idx);
      _recalc();
      notifyListeners();
    }

    try {
      // Coba berbagai kemungkinan nama method di service (kompat)
      final s = api as dynamic;

      // 1) deleteSellerProduct(int id [, token?])
      try {
        // named token
        await s.deleteSellerProduct(intId, authToken: _token);
      } catch (_) {
        try {
          // positional token
          await s.deleteSellerProduct(intId, _token);
        } catch (_) {
          // tanpa token
          await s.deleteSellerProduct(intId);
        }
      }
      return true;
    } catch (_) {
      try {
        // 2) deleteProduct
        final s = api as dynamic;
        try {
          await s.deleteProduct(intId, authToken: _token);
        } catch (_) {
          try {
            await s.deleteProduct(intId, _token);
          } catch (_) {
            await s.deleteProduct(intId);
          }
        }
        return true;
      } catch (_) {
        try {
          // 3) removeProduct
          final s = api as dynamic;
          try {
            await s.removeProduct(intId, authToken: _token);
          } catch (_) {
            try {
              await s.removeProduct(intId, _token);
            } catch (_) {
              await s.removeProduct(intId);
            }
          }
          return true;
        } catch (_) {
          try {
            // 4) deletePublicProduct (beberapa service pakai endpoint publik)
            final s = api as dynamic;
            await s.deletePublicProduct(intId);
            return true;
          } catch (e) {
            // Rollback jika semua gagal
            if (backup != null && idx >= 0 && idx <= myProducts.length) {
              myProducts.insert(idx, backup);
              _recalc();
              notifyListeners();
            }
            error = e.toString();
            return false;
          }
        }
      }
    }
  }

  /// === NEW: ambil satu produk dari cache dashboard ===
  Map<String, dynamic>? productById(dynamic id) {
    final intId = _asInt(id);
    try {
      return myProducts.firstWhere((p) => _asInt(p['id']) == intId);
    } catch (_) {
      return null;
    }
  }

  // =======================
  // Kompat panggilan service
  // =======================

  Future<List<Map<String, dynamic>>> _getSellerProductsCompat() async {
    final s = api as dynamic;
    dynamic res;

    // Urutan: named -> positional -> no arg
    try {
      res = await s.getSellerProducts(authToken: _token);
    } catch (_) {
      try {
        res = await s.getSellerProducts(_token);
      } catch (_) {
        res = await s.getSellerProducts();
      }
    }

    return _normalizeProducts(res);
  }

  Future<Map<String, dynamic>> _getSellerSummaryCompat() async {
    final s = api as dynamic;
    dynamic res;

    try {
      res = await s.getSellerSummary(authToken: _token);
    } catch (_) {
      try {
        res = await s.getSellerSummary(_token);
      } catch (_) {
        res = await s.getSellerSummary(); // boleh 404
      }
    }

    if (res is Map<String, dynamic>) return res;
    if (res is Map && res['data'] is Map) {
      return Map<String, dynamic>.from(res['data'] as Map);
    }
    return <String, dynamic>{};
  }

  // ========= utils parsing =========
  List<Map<String, dynamic>> _normalizeProducts(dynamic raw) {
    if (raw == null) return <Map<String, dynamic>>[];

    // Jika service sudah mengembalikan List<Map>
    if (raw is List) {
      return raw.map<Map<String, dynamic>>(_toMapSafe).toList();
    }

    // Map dengan berbagai kemungkinan kunci list
    if (raw is Map) {
      for (final key in const ['data', 'items', 'products', 'result']) {
        final v = raw[key];
        if (v is List) {
          return v.map<Map<String, dynamic>>(_toMapSafe).toList();
        }
        // nested: { data: { data: [...] } }
        if (v is Map && v['data'] is List) {
          return (v['data'] as List)
              .map<Map<String, dynamic>>(_toMapSafe)
              .toList();
        }
      }
    }

    return <Map<String, dynamic>>[];
  }

  Map<String, dynamic> _toMapSafe(dynamic e) {
    if (e is Map<String, dynamic>) return Map<String, dynamic>.from(e);
    try {
      final j = (e as dynamic).toJson();
      if (j is Map) return Map<String, dynamic>.from(j);
    } catch (_) {}
    return <String, dynamic>{};
  }

  void _recalc() {
    productCount = myProducts.length;

    int units = 0;
    int value = 0;
    double fsum = 0;
    int fn = 0;

    for (final p in myProducts) {
      final price = _asInt(p['price']);
      final stock = _asInt(p['stock']);
      units += stock;
      value += price * stock;

      final f = _asDouble(p['freshness_score'] ?? p['suitability_percent']);
      if (f != null) {
        fsum += f;
        fn++;
      }
    }

    stockUnits = units;
    stockValueTotal = value;
    freshnessAvg = fn == 0 ? 0 : (fsum / fn);
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}
