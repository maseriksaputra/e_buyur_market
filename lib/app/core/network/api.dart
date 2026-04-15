// lib/app/core/network/api.dart
//
// HTTP helper pusat berbasis Dio (simple & robust)
// - Base URL WAJIB berakhiran '/api/'
// - Header JSON default (hindari HTML/redirect)
// - Tidak ada fallback Sanctum (/sanctum/token /sanctum/csrf-cookie) — backend pakai /api/auth/*
// - Tetap sediakan helper setBearer(), get/postJson/putJson/patchJson/delete()
// - Jangan pakai leading slash saat memanggil endpoint (contoh: 'auth/login', bukan '/auth/login').

import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

class API {
  API._();

  static bool _inited = false;
  static late final Dio dio;

  /// Panggil sekali saat app start (mis. di main())
  static void init({String baseUrl = 'https://api.ebuyurmarket.com/api/'}) {
    if (_inited) return;

    // Pastikan trailing slash
    if (!baseUrl.endsWith('/')) baseUrl = '$baseUrl/';

    final options = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30), // was 20
      sendTimeout: const Duration(seconds: 20),
      // Jangan throw untuk 4xx agar body JSON bisa dibaca caller
      validateStatus: (s) => s != null && s < 500,
      responseType: ResponseType.json,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      followRedirects: false,
      receiveDataWhenStatusError: true,
    );

    final d = Dio(options);

    // Adapter IO: stabilkan koneksi di sebagian server/gateway
    d.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final c = HttpClient()
          ..idleTimeout = const Duration(seconds: 20)        // was 15
          ..connectionTimeout = const Duration(seconds: 20)  // was 15
          ..maxConnectionsPerHost = 8;
        c.userAgent = 'EbuyurMarket/1.0 (Flutter)';
        return c;
      },
    );

    // (Opsional) aktifkan logging saat debug:
    // d.interceptors.add(LogInterceptor(requestBody: true, responseBody: true));

    dio = d;
    _inited = true;
  }

  /// Set/Clear Authorization: Bearer <token>
  static void setBearer(String? token) {
    _ensureInit();
    if (token != null && token.isNotEmpty) {
      dio.options.headers['Authorization'] = 'Bearer $token';
    } else {
      dio.options.headers.remove('Authorization');
    }
  }

  /// Alias kompatibel
  static void setToken(String? token) => setBearer(token);

  static String get currentBaseUrl {
    _ensureInit();
    return dio.options.baseUrl;
  }

  // ---------- Request helpers ----------
  static Future<Response> get(
    String path, {
    Map<String, dynamic>? query,
    Options? options,
    CancelToken? cancelToken,
  }) {
    _ensureInit();
    return dio.get(path, queryParameters: query, options: options, cancelToken: cancelToken);
  }

  static Future<Response> postJson(
    String path, {
    dynamic data,
    Map<String, dynamic>? query,
    Options? options,
    CancelToken? cancelToken,
  }) {
    _ensureInit();
    return dio.post(
      path,
      data: data,
      queryParameters: query,
      options: _mergeJsonOptions(options),
      cancelToken: cancelToken,
    );
  }

  static Future<Response> putJson(
    String path, {
    dynamic data,
    Map<String, dynamic>? query,
    Options? options,
    CancelToken? cancelToken,
  }) {
    _ensureInit();
    return dio.put(
      path,
      data: data,
      queryParameters: query,
      options: _mergeJsonOptions(options),
      cancelToken: cancelToken,
    );
  }

  static Future<Response> patchJson(
    String path, {
    dynamic data,
    Map<String, dynamic>? query,
    Options? options,
    CancelToken? cancelToken,
  }) {
    _ensureInit();
    return dio.patch(
      path,
      data: data,
      queryParameters: query,
      options: _mergeJsonOptions(options),
      cancelToken: cancelToken,
    );
  }

  static Future<Response> delete(
    String path, {
    Map<String, dynamic>? query,
    dynamic data,
    Options? options,
    CancelToken? cancelToken,
  }) {
    _ensureInit();
    return dio.delete(
      path,
      data: data,
      queryParameters: query,
      options: _mergeJsonOptions(options),
      cancelToken: cancelToken,
    );
  }

  // ----- JSON Options merge -----
  static Options _mergeJsonOptions(Options? options) {
    final base = Options(headers: <String, dynamic>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    });

    if (options == null) return base;

    final mergedHeaders = {
      ...?base.headers,
      ...?options.headers,
    };

    return base.copyWith(
      headers: mergedHeaders,
      followRedirects: options.followRedirects ?? false,
      validateStatus: options.validateStatus ?? (s) => s != null && s < 500,
      receiveDataWhenStatusError: options.receiveDataWhenStatusError,
      responseType: options.responseType,
      listFormat: options.listFormat,
      sendTimeout: options.sendTimeout,
      receiveTimeout: options.receiveTimeout,
      extra: options.extra,
      contentType: options.contentType,
    );
  }

  /// Decode aman: kalau String JSON → Map/List, kalau bukan biarkan apa adanya.
  static dynamic decodeBody(dynamic payload) {
    if (payload is String) {
      try {
        return jsonDecode(payload);
      } catch (_) {
        return payload;
      }
    }
    return payload;
  }

  static void _ensureInit() {
    if (!_inited) {
      // Default init bila developer lupa memanggil API.init() di main()
      init();
    }
  }
}
