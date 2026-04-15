// lib/data/services/api.dart
import 'dart:convert';
import 'package:dio/dio.dart';

class API {
  /// Pola anti double-slash:
  /// - baseUrl sudah mengandung '/api' dan TIDAK diakhiri slash
  /// - setiap pemanggilan pakai path TANPA leading slash, mis. 'buyer/cart'
  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.ebuyurmarket.com/api', // ✅ TANPA '/' di akhir
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ),
  );

  /// 👉 Pakai ini di seluruh app agar header/baseUrl/interceptor seragam:
  /// final dio = API.dio;
  static Dio get dio => _dio;

  static void setToken(String token) {
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  /// Normalisasi path agar selalu 'segment/segment' (tanpa slash di depan)
  static String _path(String p) {
    final s = (p).trim();
    if (s.isEmpty) return '';
    return s.startsWith('/') ? s.substring(1) : s;
    // NB: Jangan kirim path berawalan '/', agar base '/api' tidak terpotong.
  }

  static Map<String, dynamic> _parse(Response res) {
    final d = res.data;
    if (d is Map) return Map<String, dynamic>.from(d as Map);
    return Map<String, dynamic>.from(jsonDecode(d as String));
  }

  // ===== Low-level helpers =====
  static Future<Response> _get(String p, {Map<String, dynamic>? query}) =>
      _dio.get(_path(p), queryParameters: query);

  static Future<Response> _post(String p, dynamic data) =>
      _dio.post(_path(p), data: data);

  static Future<dynamic> get(String p, {Map<String, dynamic>? query}) async {
    final res = await _get(p, query: query);
    return res.data;
  }

  static Future<dynamic> post(String p, dynamic data) async {
    final res = await _post(p, data);
    return res.data;
  }

  // ===== Business endpoints =====

  /// Preview checkout: **selalu** coba POST /checkout/preview { order_code }
  /// dengan fallback aman jika route dipindah.
  static Future<Map<String, dynamic>> checkoutPreview(String orderCode) async {
    // 1) jalur utama (umum)
    try {
      final res = await _post('checkout/preview', {'order_code': orderCode});
      return _parse(res);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code != 404 && code != 405) rethrow;
    }

    // 2) fallback: namespace buyer
    try {
      final res =
          await _post('buyer/checkout/preview', {'order_code': orderCode});
      return _parse(res);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code != 404 && code != 405) rethrow;
    }

    // 3) fallback terakhir: path param
    final res = await _post('checkout/preview/$orderCode', null);
    return _parse(res);
  }

  /// Snap token Midtrans (advance): POST /payments/midtrans/token
  /// body: { order_code, courier_code?, service_code?, shipping_cost? }
  static Future<Map<String, dynamic>> createSnapTokenAdvanced({
    required String orderCode,
    String? courierCode,
    String? serviceCode,
    int? shippingCost,
  }) async {
    final res = await _post('payments/midtrans/token', {
      'order_code': orderCode,
      if (courierCode != null) 'courier_code': courierCode,
      if (serviceCode != null) 'service_code': serviceCode,
      if (shippingCost != null) 'shipping_cost': shippingCost,
    });
    return _parse(res);
  }

  /// Status order: GET /orders/{code}
  static Future<Map<String, dynamic>> fetchOrder(String code) async {
    final res = await _get('orders/$code');
    return _parse(res);
  }

  /// Direct buy (opsional): POST /buyer/orders
  static Future<dynamic> createOrderDirect({
    required int productId,
    required int qty,
    required int addressId,
    String? courierCode,
  }) {
    return post('buyer/orders', {
      'items': [
        {'product_id': productId, 'qty': qty}
      ],
      'address_id': addressId,
      if (courierCode != null) 'courier_code': courierCode,
    });
  }

  // ===== Cart convenience =====

  /// GET /buyer/cart
  static Future<dynamic> fetchCart() => get('buyer/cart');

  /// POST /buyer/cart/add
  /// body: { product_id, qty }
  static Future<dynamic> addToCart({
    required int productId,
    required int qty,
  }) {
    return post('buyer/cart/add', {
      'product_id': productId,
      'qty': qty, // ✅ selaras dengan controller (bukan "quantity")
    });
  }
}
