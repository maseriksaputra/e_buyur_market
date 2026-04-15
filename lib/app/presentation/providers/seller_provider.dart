// lib/app/presentation/providers/seller_provider.dart
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import '../../core/network/api.dart'; // menyediakan API.dio
import '../../core/services/product_api_service.dart';
import '../../common/models/product_model.dart';

/// Provider untuk data produk milik seller.
/// - Request utama pakai API.dio (langsung ke endpoint backend).
/// - Delete menggunakan ProductApiService agar kompatibel dengan service lama.
/// - Endpoint DIASUMSIKAN sudah berada di bawah baseUrl API.dio (yang biasanya sdh /api).
class SellerProvider with ChangeNotifier {
  final ProductApiService _api;

  /// Tambahkan [baseUrl] opsional agar kompatibel dengan pemanggilan:
  /// `SellerProvider(baseUrl: ApiConfig.baseUrl)`
  ///
  /// Jika [ProductApiService] mendukung `setBaseUrl(String)` atau properti
  /// `baseUrl`, nilai akan disuntikkan. Jika tidak didukung, aman diabaikan.
  SellerProvider({ProductApiService? api, String? baseUrl})
      : _api = api ?? ProductApiService() {
    if (baseUrl != null && baseUrl.isNotEmpty) {
      try {
        // Coba method umum
        // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
        // (kalau tidak ada, akan masuk ke catch dan diabaikan)
        // Method 1: setBaseUrl(String)
        // @ts-ignore
        // dart dynamic call; ignore analyzer warnings in runtime.
        // we guard with try/catch anyway.
        // (Tidak mengubah signature ProductApiService kamu.)
        // If this throws, we try alternatives below.
        // -------------------------------------------------
        // ignore: unnecessary_cast
        ( _api as dynamic ).setBaseUrl(baseUrl);
      } catch (_) {
        try {
          // Method 2: assign langsung ke properti .baseUrl
          // ignore: unnecessary_cast
          ( _api as dynamic ).baseUrl = baseUrl;
        } catch (_) {
          // Tidak ada API untuk set baseUrl — aman diabaikan.
        }
      }
    }
  }

  // ---------- Auth ----------
  String? _token;

  /// Dipanggil dari AuthProvider untuk menyuntik token Bearer.
  void setAuthToken(String? token) {
    _token = token;
    _api.setAuthToken(token); // tetap set ke service bawaan
  }

  // ---------- State ----------
  bool _loading = false;
  String? _error;

  // Kompat: simpan dua bentuk model (berat & ringan)
  final List<Product> _items = <Product>[];
  final List<ProductModel> _products = <ProductModel>[];

  // Meta pagination (opsional)
  int? _currentPage;
  int? _lastPage;
  int? _total;

  bool get isLoading => _loading;
  String? get error => _error;

  /// Kompat lama (list lengkap)
  List<Product> get items => List.unmodifiable(_items);

  /// List ringan untuk UI grid/list
  List<ProductModel> get products => List.unmodifiable(_products);

  int? get currentPage => _currentPage;
  int? get lastPage => _lastPage;
  int? get total => _total;

  void _setLoading(bool v) {
    _loading = v;
    notifyListeners();
  }

  void _setError(String? e) {
    _error = e;
    notifyListeners();
  }

  // ---------- Actions ----------

  /// Ambil daftar produk milik seller (paginated).
  ///
  /// Catatan:
  /// - Path tanpa leading slash supaya tetap menempel ke baseUrl API.dio (yang sudah /api).
  /// - Tambahkan header Authorization jika token ada.
  Future<void> refreshProducts({
    int page = 1,
    int perPage = 12,
    Map<String, dynamic>? filter,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final qp = <String, dynamic>{'page': page, 'per_page': perPage};
      if (filter != null && filter.isNotEmpty) qp.addAll(filter);

      final res = await API.dio.get(
        'seller/products',
        queryParameters: qp,
        options: Options(
          headers: _token == null
              ? null
              : <String, dynamic>{'Authorization': 'Bearer $_token'},
        ),
      );

      final norm = _normalizeSellerProductsResponse(res.data);

      // Parse ringan → ProductModel
      final listMap = norm.list.whereType<Map<String, dynamic>>().toList();
      final pmList = listMap.map(ProductModel.fromJson).toList();

      // Sinkronkan state ringan
      _products
        ..clear()
        ..addAll(pmList);

      // Kompat: isi _items (Product) dari ProductModel → Product
      _items
        ..clear()
        ..addAll(pmList.map((e) => e.toProduct()));

      // Meta
      _currentPage =
          _asInt(norm.meta['current_page'] ?? norm.meta['currentPage']);
      _lastPage = _asInt(norm.meta['last_page'] ?? norm.meta['lastPage']);
      _total = _asInt(norm.meta['total']);

      _setError(null);
    } catch (e, st) {
      debugPrint('[SellerProvider] refreshProducts error: $e\n$st');
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  /// Hapus satu produk milik seller.
  Future<bool> deleteProduct(dynamic id) async {
    try {
      final intId = _safeInt(id);
      if (intId < 0) {
        _setError('ID produk tidak valid');
        return false;
      }

      await _api.deleteSellerProduct(intId);

      // Sinkronkan state lokal
      _items.removeWhere((p) => p.id == intId);
      _products.removeWhere((p) => p.id == intId);
      notifyListeners();
      return true;
    } catch (e, st) {
      debugPrint('[SellerProvider] deleteProduct error: $e\n$st');
      _setError(e.toString());
      return false;
    }
  }

  // ---------- Helpers ----------

  int _safeInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? -1;
    return -1;
  }

  int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  /// Normalisasi berbagai bentuk respons menjadi list & meta uniform.
  _ParsedNormalized _normalizeSellerProductsResponse(dynamic data) {
    // 1) List langsung
    if (data is List) {
      return _ParsedNormalized(list: data, meta: <String, dynamic>{});
    }

    if (data is Map) {
      // 2) { data: { data:[...], current_page:..., ... } }
      final d = data['data'];
      if (d is Map && d['data'] is List) {
        final meta = Map<String, dynamic>.from(d)..remove('data');
        return _ParsedNormalized(list: d['data'] as List, meta: meta);
      }

      // 3) { data:[...], meta:{...} }
      if (data['data'] is List) {
        return _ParsedNormalized(
          list: data['data'] as List,
          meta: (data['meta'] is Map)
              ? Map<String, dynamic>.from(data['meta'] as Map)
              : <String, dynamic>{},
        );
      }

      // 4) { items:[...], meta:{...} }
      if (data['items'] is List) {
        return _ParsedNormalized(
          list: data['items'] as List,
          meta: (data['meta'] is Map)
              ? Map<String, dynamic>.from(data['meta'] as Map)
              : <String, dynamic>{},
        );
      }
    }

    // Bentuk lain → aman (kosong)
    return const _ParsedNormalized(list: <dynamic>[], meta: <String, dynamic>{});
  }
}

/// Struct kecil normalisasi respons
class _ParsedNormalized {
  final List<dynamic> list;
  final Map<String, dynamic> meta;
  const _ParsedNormalized({required this.list, required this.meta});
}
