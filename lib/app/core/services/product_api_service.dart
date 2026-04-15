// lib/app/core/services/product_api_service.dart
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

import '../../common/models/product_category.dart';
import '../../common/models/product_model.dart';
import '../network/api.dart';

/// ========= DTO Tambahan =========
class InventorySummary {
  final int totalSkus;
  final int totalUnits;
  final double totalValue;
  final int lowStock;

  InventorySummary({
    required this.totalSkus,
    required this.totalUnits,
    required this.totalValue,
    required this.lowStock,
  });

  factory InventorySummary.fromJson(Map<String, dynamic> j) => InventorySummary(
        totalSkus: (j['total_skus'] as num?)?.toInt() ?? 0,
        totalUnits: (j['total_units'] as num?)?.toInt() ?? 0,
        totalValue: (j['total_value'] as num?)?.toDouble() ?? 0.0,
        lowStock: (j['low_stock'] as num?)?.toInt() ?? 0,
      );
}

class SellerProductFilter {
  String? search;
  int? categoryId;
  double? priceMin;
  double? priceMax;
  double? freshMin;
  double? freshMax;
  bool? inStockOnly;
  bool? isActive;
  String? sort; // name|price|stock|freshness_score|updated_at
  String? dir; // asc|desc
  int? page;
  int? perPage;

  Map<String, dynamic> toQuery() {
    final q = <String, dynamic>{};
    if (search?.isNotEmpty == true) q['search'] = search;
    if (categoryId != null) q['category_id'] = categoryId;
    if (priceMin != null) q['price_min'] = priceMin;
    if (priceMax != null) q['price_max'] = priceMax;
    if (freshMin != null) q['fresh_min'] = freshMin;
    if (freshMax != null) q['fresh_max'] = freshMax;
    if (inStockOnly == true) q['in_stock_only'] = true;
    if (isActive != null) q['is_active'] = isActive;
    if (sort != null) q['sort'] = sort;
    if (dir != null) q['dir'] = dir;
    if (page != null) q['page'] = page;
    if (perPage != null) q['per_page'] = perPage;
    return q;
  }
}

/// ========= Service API Produk =========
/// Seluruh request memakai `_dio`. Defaultnya mengambil dari `API.dio`
/// (yang sudah dikonfigurasi baseUrl, headers, interceptor, dsb).
class ProductApiService {
  /// Konstruktor instance (kompatibel dengan pemanggilan lama)
  ProductApiService({Dio? dio})
      : _dio = dio ?? API.dio ?? Dio(BaseOptions(baseUrl: 'https://api.ebuyurmarket.com/api'));

  final Dio _dio;
  CancelToken? _lastToken;

  /// Set token Bearer ke header global + dio lokal
  void setAuthToken(String? token) {
    API.setBearer(token);
    if (token == null || token.isEmpty) {
      _dio.options.headers.remove('Authorization');
    } else {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    }
  }

  // ---------- Helpers ----------
  static dynamic decodeBody(dynamic body) {
    if (body is String) {
      try {
        return jsonDecode(body);
      } catch (_) {
        return body;
      }
    }
    return body;
  }

  dynamic _decode(dynamic payload) => ProductApiService.decodeBody(payload);

  List _asList(dynamic body) {
    final j = _decode(body);
    if (j is List) return j;
    if (j is Map && j['data'] is List) return List.from(j['data'] as List);
    if (j is Map && j['products'] is List) {
      return List.from(j['products'] as List);
    }
    return const [];
  }

  Map<String, dynamic> _asMap(dynamic body) {
    final j = _decode(body);
    if (j is Map<String, dynamic>) return j;
    if (j is Map && j['data'] is Map) {
      return Map<String, dynamic>.from(j['data'] as Map);
    }
    return <String, dynamic>{};
  }

  Never _throwByResponse(Response r, {String? fallback}) {
    String? msg;
    final data = _decode(r.data);
    if (data is Map) {
      if (data['message'] is String) {
        msg = data['message'] as String;
      } else if (data['error'] is String) {
        msg = data['error'] as String;
      }
    }
    msg ??= r.statusMessage ?? fallback ?? 'Request gagal';
    throw DioException(
      requestOptions: r.requestOptions,
      response: r,
      type: DioExceptionType.badResponse,
      error: msg,
    );
  }

  Options _jsonOptions({Map<String, String>? extra}) => Options(
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          if (extra != null) ...extra,
        },
      );

  Map<String, String> _auth(String? t) => t == null ? {} : {'Authorization': 'Bearer $t'};

  // ---------- AUTH ----------
  Future<Response> login(Map<String, dynamic> body) =>
      _dio.post('auth/login', data: body, options: _jsonOptions());

  Future<Response> loginMe() => _dio.get('auth/me');

  Future<Response> logout() => _dio.post('auth/logout', data: const {}, options: _jsonOptions());

  // ===================================================================
  // ===============         ENDPOINTS UMUM            =================
  // ===================================================================

  /// List produk publik (dengan CancelToken)
  Future<Response> getProducts({int page = 1}) async {
    _lastToken?.cancel('cancel previous list');
    _lastToken = CancelToken();
    return _dio.get(
      'products',
      queryParameters: {'page': page},
      cancelToken: _lastToken,
    );
  }

  /// alias supaya pemanggil bisa pakai: final r = await _api.list(page: 1);
  Future<Response> list({int page = 1}) => getProducts(page: page);

  /// Pencarian (dipakai layar search)
  Future<Response> search(String q, {int limit = 30}) =>
      _dio.get('products/search', queryParameters: {'q': q, 'limit': limit});

  /// Versi lama yang mengembalikan `List<Product>`
  Future<List<Product>> fetchProducts({
    ProductCategory? category,
    String? q,
  }) async {
    _lastToken?.cancel('cancel previous list');
    _lastToken = CancelToken();

    final qp = <String, dynamic>{
      if (category != null) 'category': category.slug,
      if (q != null && q.isNotEmpty) 'q': q,
    };

    final r = await _dio.get(
      'products',
      queryParameters: qp,
      cancelToken: _lastToken,
    );
    if ((r.statusCode ?? 500) >= 400) {
      _throwByResponse(r, fallback: 'Gagal memuat produk');
    }
    final list = _asList(r.data);
    return list
        .map((e) => Product.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// ✅ Versi MAP murni (mempertahankan semua field seperti nutrition/storage)
  Future<Map<String, dynamic>> fetchProductDetailMap(int id) async {
    final r = await _dio.get('products/$id'); // → GET /api/products/{id}
    return _asMap(r.data);
  }

  /// Versi lama: mengubah ke model (berpotensi tidak memuat field custom)
  Future<Product> fetchProductDetail(int id) async {
    final m = await fetchProductDetailMap(id);
    return Product.fromJson(m);
  }

  /// Upload product via JSON (legacy)
  Future<Map<String, dynamic>> uploadProductJson({
    required Map<String, String> payload,
  }) async {
    final r = await _dio.post('products', data: payload, options: _jsonOptions());
    if ((r.statusCode ?? 500) >= 400) {
      _throwByResponse(r, fallback: 'Gagal upload produk');
    }
    final body = _decode(r.data);
    if (body is Map<String, dynamic>) return body;
    if (body is Map) return Map<String, dynamic>.from(body);
    return <String, dynamic>{'message': 'OK', 'data': body};
  }

  Future<Product> createProduct({
    required String name,
    required int price,
    required int stock,
    required List<String> imageUrls,
    required ProductCategory category,
  }) async {
    final payload = {
      'name': name,
      'price': price,
      'stock': stock,
      'image_urls': imageUrls,
      'category': category.slug,
    };
    final r = await _dio.post('products', data: payload, options: _jsonOptions());
    if (!{200, 201}.contains(r.statusCode)) {
      _throwByResponse(r, fallback: 'Gagal membuat produk');
    }
    final m = _asMap(r.data);
    return Product.fromJson(m);
  }

  Future<Product> updateProduct(
    int id, {
    String? name,
    int? price,
    int? stock,
    List<String>? imageUrls,
    ProductCategory? category,
  }) async {
    final payload = <String, dynamic>{
      if (name != null) 'name': name,
      if (price != null) 'price': price,
      if (stock != null) 'stock': stock,
      if (imageUrls != null) 'image_urls': imageUrls,
      if (category != null) 'category': category.slug,
    };

    Response r = await _dio.patch(
      'products/$id',
      data: jsonEncode(payload),
      options: _jsonOptions(),
    );

    if (r.statusCode == 405) {
      r = await _dio.put(
        'products/$id',
        data: jsonEncode(payload),
        options: _jsonOptions(),
      );
    }

    if ((r.statusCode ?? 500) >= 400) {
      _throwByResponse(r, fallback: 'Gagal memperbarui produk');
    }

    final m = _asMap(r.data);
    return Product.fromJson(m);
  }

  Future<void> deletePublicProduct(int id) async {
    final r = await _dio.delete('products/$id');
    if (!{200, 204}.contains(r.statusCode)) {
      _throwByResponse(r, fallback: 'Gagal menghapus produk');
    }
  }

  // ===================================================================
  // ===============        ENDPOINTS SELLER            =================
  // ===================================================================

  Future<Response> getSellerProductsLegacy({int page = 1}) {
    _lastToken?.cancel('cancel previous list');
    _lastToken = CancelToken();
    return _dio.get(
      'seller/products',
      queryParameters: {'page': page},
      cancelToken: _lastToken,
    );
  }

  /// Versi dengan pemetaan ke model + meta
  Future<Map<String, dynamic>> getSellerProducts({
    SellerProductFilter? filter,
    int? page,
    int? perPage,
  }) async {
    _lastToken?.cancel('cancel previous list');
    _lastToken = CancelToken();

    final qp = <String, dynamic>{};
    if (filter != null) qp.addAll(filter.toQuery());
    if (page != null) qp['page'] = page;
    if (perPage != null) qp['per_page'] = perPage;

    final res = await _dio.get(
      'seller/products',
      queryParameters: qp,
      cancelToken: _lastToken,
    );

    final data = _decode(res.data);
    final map = (data is Map<String, dynamic>)
        ? data
        : Map<String, dynamic>.from(data as Map);

    final items = (map['data'] as List)
        .map((e) => Product.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    return {
      'items': items,
      'meta': {
        'current_page': map['current_page'],
        'last_page': map['last_page'],
        'total': map['total'],
      }
    };
  }

  /// ✅ Raw list (tanpa mapping ke model)
  Future<List<Map<String, dynamic>>> getSellerProductsSimple({String? authToken}) async {
    final res = await _dio.get(
      'seller/products',
      options: Options(headers: _auth(authToken)),
    );
    final raw = res.data;
    final data = raw is Map<String, dynamic> ? (raw['data'] ?? raw) : raw;
    final list = (data as List).cast<dynamic>();
    return list
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Response> getSellerDashboard() => _dio.get('seller/dashboard');

  // ========= dashboard + latest =========
  Future<Map<String, dynamic>> fetchSellerDashboard() async {
    final res = await _dio.get('seller/dashboard');
    final bodyDyn = ProductApiService.decodeBody(res.data);
    final Map body = (bodyDyn is Map) ? bodyDyn : <String, dynamic>{};

    final latestRaw = body['latest'];
    final List latestList = (latestRaw is Map && latestRaw['data'] is List)
        ? (latestRaw['data'] as List)
        : (latestRaw as List? ?? const []);

    final Map stats = (body['stats'] is Map) ? (body['stats'] as Map) : const {};

    return {
      'inventory_value': (stats['inventory_value'] is num)
          ? (stats['inventory_value'] as num).toInt()
          : 0,
      'products_count': (stats['products_count'] is num)
          ? (stats['products_count'] as num).toInt()
          : 0,
      'stock_units':
          (stats['stock_units'] is num) ? (stats['stock_units'] as num).toInt() : 0,
      'avg_freshness':
          (stats['avg_freshness'] is num) ? (stats['avg_freshness'] as num).toInt() : 0,
      'latest': latestList
          .map<Product>((e) => Product.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    };
  }

  Future<Response> createProductFromScan(Map<String, dynamic> body) =>
      _dio.post('seller/products/from-scan', data: body, options: _jsonOptions());

  Future<Response> getSellerProduct(int id) => _dio.get('seller/products/$id');

  Future<Product> getSellerProductDetail(int id) async {
    final res = await _dio.get('seller/products/$id');
    final m = _asMap(res.data);
    return Product.fromJson(m);
  }

  Future<Response> uploadSellerProductMultipart({
    required Map<String, String> fields,
    required String imagePath,
    String? imageFieldName = 'image',
    String? filename,
  }) async {
    final form = FormData.fromMap({
      ...fields,
      imageFieldName ?? 'image': await MultipartFile.fromFile(
        imagePath,
        filename: filename,
      ),
    });
    final r = await _dio.post('seller/products', data: form);
    if ((r.statusCode ?? 500) >= 400) {
      _throwByResponse(r, fallback: 'Gagal upload produk (seller)');
    }
    return r;
  }

  Future<Response> updateSellerProductMultipart({
    required int id,
    required Map<String, String> fields,
    String? imagePath,
    String? imageFieldName = 'image',
    String? filename,
  }) async {
    final Map<String, dynamic> map = {
      '_method': 'PUT',
      ...fields,
    };
    if (imagePath != null && imagePath.isNotEmpty) {
      map[imageFieldName ?? 'image'] = await MultipartFile.fromFile(
        imagePath,
        filename: filename,
      );
    }
    final form = FormData.fromMap(map);
    final r = await _dio.post('seller/products/$id', data: form);
    if ((r.statusCode ?? 500) >= 400) {
      _throwByResponse(r, fallback: 'Gagal update produk (seller)');
    }
    return r;
  }

  Future<Product> updateSellerProduct({
    required int id,
    String? name,
    double? price,
    int? stock,
    int? categoryId,
    String? description,
    double? freshnessScore,
    List<String>? nutrition,
    bool? isActive,
    int? suitabilityPercent,
  }) async {
    final payload = <String, dynamic>{
      if (name != null) 'name': name,
      if (price != null) 'price': price,
      if (stock != null) 'stock': stock,
      if (categoryId != null) 'category_id': categoryId,
      if (description != null) 'description': description,
      if (freshnessScore != null) 'freshness_score': freshnessScore,
      if (nutrition != null) 'nutrition': nutrition,
      if (isActive != null) 'is_active': isActive,
      if (suitabilityPercent != null) 'suitability_percent': suitabilityPercent,
    };

    final res = await _dio.put('seller/products/$id', data: payload);
    final m = _asMap(res.data);
    return Product.fromJson(m);
  }

  Future<void> deleteSellerProduct(int id) async {
    final r = await _dio.delete('seller/products/$id');
    if (!{200, 204}.contains(r.statusCode)) {
      _throwByResponse(r, fallback: 'Gagal menghapus produk (seller)');
    }
  }

  /// Versi yang mengembalikan Response (kompat lama)
  Future<Response> deleteSellerProductResponse(int id) async {
    final r = await _dio.delete('seller/products/$id');
    if (!{200, 204}.contains(r.statusCode)) {
      _throwByResponse(r, fallback: 'Gagal menghapus produk (seller)');
    }
    return r;
  }

  /// Upload multipart manual via package:http (jika diperlukan)
  Future<http.StreamedResponse> uploadProduct({
    required Map<String, String> fields,
    required http.MultipartFile imageFile,
  }) async {
    final base = _dio.options.baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/seller/products');

    final req = http.MultipartRequest('POST', uri);
    req.fields.addAll(fields);
    req.files.add(imageFile);

    final auth = _dio.options.headers['Authorization'];
    if (auth != null) req.headers['Authorization'] = auth.toString();
    req.headers['Accept'] = 'application/json';

    return req.send();
  }

  /// Fallback ke /seller/dashboard kalau /seller/products/summary 404
  Future<InventorySummary> getSellerInventorySummary({bool onlyActive = false}) async {
    try {
      final res = await _dio.get(
        'seller/products/summary',
        queryParameters: {if (onlyActive) 'only_active': true},
      );
      final data = ProductApiService.decodeBody(res.data);
      if (data is Map<String, dynamic>) return InventorySummary.fromJson(data);
      if (data is Map) {
        return InventorySummary.fromJson(Map<String, dynamic>.from(data));
      }
      return InventorySummary(totalSkus: 0, totalUnits: 0, totalValue: 0.0, lowStock: 0);
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      if (status == 404) {
        final dash = await fetchSellerDashboard();
        return InventorySummary(
          totalSkus: (dash['products_count'] as num?)?.toInt() ?? 0,
          totalUnits: (dash['stock_units'] as num?)?.toInt() ?? 0,
          totalValue: (dash['inventory_value'] as num?)?.toDouble() ?? 0.0,
          lowStock: (dash['low_stock'] as num?)?.toInt() ?? 0,
        );
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getSellerInventorySummaryRaw({bool onlyActive = false}) async {
    final res = await _dio.get('seller/products/summary',
        queryParameters: {if (onlyActive) 'only_active': true});
    final data = _decode(res.data);
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {
      'total_skus': 0,
      'total_units': 0,
      'total_value': 0.0,
      'low_stock': 0,
    };
  }

  // ====== SELLER PRODUCTS ======
  Future<List<Product>> listSellerProducts({int page = 1, String? search}) async {
    final res = await _dio.get(
      'seller/products',
      queryParameters: {
        'page': page,
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      },
    );
    final body = ProductApiService.decodeBody(res.data);
    final list = (body is Map && body['data'] is List)
        ? body['data']
        : (body as List? ?? []);
    return list
        .map<Product>((e) => Product.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// ====== STATIC API: detail raw (JSON Map) ======
  static Future<Map<String, dynamic>> fetchById(int id) async {
    final Dio dio =
        API.dio ?? Dio(BaseOptions(baseUrl: 'https://api.ebuyurmarket.com/api'));
    final res = await dio.get('products/$id'); // → GET /api/products/{id}
    final data = res.data;
    if (data is Map<String, dynamic>) {
      if (data['data'] is Map<String, dynamic>) {
        return Map<String, dynamic>.from(data['data'] as Map);
        }
      return Map<String, dynamic>.from(data);
    }
    return <String, dynamic>{};
  }
}
