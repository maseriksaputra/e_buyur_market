// lib/app/core/api/api.dart
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// File ini dipakai beberapa service lama. Perbaiki join baseUrl + path.
/// Token di-set manual via API.setAuthToken / API.setBearer.
class API {
  // ===== Base & path =====
  static String _computeBase() {
    // API_BASE bisa berisi root termasuk '/api' atau '/api/v1'
    final raw = (dotenv.env['API_BASE'] ?? 'https://api.ebuyurmarket.com/api').trim();
    final cleaned = raw.replaceFirst(RegExp(r'/+$'), '');
    return '$cleaned/'; // pastikan diakhiri '/'
  }

  static String _normalizePath(String raw) {
    var p = raw.trim();
    if (p.isEmpty) return p;

    // Buang skema+host jika ada
    if (p.startsWith('http://') || p.startsWith('https://')) {
      try {
        final uri = Uri.parse(p);
        p = uri.path;
      } catch (_) {}
    }

    // Buang semua awalan '/api'
    if (!p.startsWith('/')) p = '/$p';
    p = p.replaceFirst(RegExp(r'^(/api)+'), '');
    if (p.startsWith('/')) p = p.substring(1);

    return p; // relatif
  }

  // ===== Auth bearer (manual) =====
  static String? _bearer;

  /// Set token Bearer secara manual (dipakai oleh provider/service).
  static Future<void> setAuthToken(String? token) async {
    _bearer = (token == null || token.isEmpty) ? null : token;
    if (_bearer == null) {
      dio.options.headers.remove('Authorization');
    } else {
      dio.options.headers['Authorization'] = 'Bearer $_bearer';
    }
  }

  /// Alias lama
  static Future<void> setBearer(String? token) => setAuthToken(token);

  // ===== Dio =====
  static final Dio dio = Dio(
    BaseOptions(
      baseUrl: _computeBase(),
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
      headers: const {'Accept': 'application/json'},
      // biarkan caller cek status code
      validateStatus: (_) => true,
    ),
  )..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // suntik Authorization dari _bearer (tanpa TokenStore)
          if (_bearer != null && _bearer!.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $_bearer';
          } else {
            options.headers.remove('Authorization');
          }
          handler.next(options);
        },
      ),
    );

  // ===== Convenience wrappers =====
  static Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? query,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return dio.get<T>(
      _normalizePath(path),
      queryParameters: query,
      options: options,
      cancelToken: cancelToken,
    );
  }

  static Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? query,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return dio.post<T>(
      _normalizePath(path),
      data: data,
      queryParameters: query,
      options: options,
      cancelToken: cancelToken,
    );
  }

  /// Versi JSON (Content-Type: application/json)
  static Future<Response<T>> postJson<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    Options? options,
    CancelToken? cancelToken,
  }) {
    final jsonOptions = (options ?? Options()).copyWith(
      headers: {
        ...?options?.headers,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    );
    return dio.post<T>(
      _normalizePath(path),
      data: data,
      queryParameters: query,
      options: jsonOptions,
      cancelToken: cancelToken,
    );
  }

  static Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? query,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return dio.put<T>(
      _normalizePath(path),
      data: data,
      queryParameters: query,
      options: options,
      cancelToken: cancelToken,
    );
  }

  static Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? query,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return dio.delete<T>(
      _normalizePath(path),
      data: data,
      queryParameters: query,
      options: options,
      cancelToken: cancelToken,
    );
  }

  /// Helper JSON seragam: kalau `data` String → decode, kalau Map/List → langsung.
  static dynamic decodeBody(dynamic data) {
    if (data is String) {
      try {
        return jsonDecode(data);
      } catch (_) {
        return data; // biarkan caller yang tangani
      }
    }
    return data;
  }
}
