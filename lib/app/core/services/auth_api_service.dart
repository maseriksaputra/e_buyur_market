// lib/app/core/services/auth_api_service.dart
import 'dart:convert';
import 'package:dio/dio.dart';
import '../network/api.dart';

class AuthApiService {
  // Reuse single Dio instance dari API.init()
  final Dio _dio = API.dio;

  // -------------------- LOGIN --------------------
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    required String role, // "buyer" | "seller"
  }) async {
    try {
      final res = await _dio.post(
        'auth/login',
        data: {
          'email': email.trim(),
          'password': password,
          'role': role,             // 'buyer' / 'seller'
          'device_name': 'mobile',  // ✅ konsisten dengan server
        },
        options: Options(headers: const {'Accept': 'application/json'}),
      );

      final code = res.statusCode ?? 0;
      final body = _normalizeBody(res.data);

      if (code == 200 || code == 201) {
        final token = _extractToken(body);
        final user  = _extractUser(body);
        if (token == null || token.isEmpty) {
          throw Exception('Login gagal: token tidak ditemukan.');
        }
        // Pasang Authorization global agar request berikutnya aman
        API.setBearer(token);
        return {'token': token, if (user != null) 'user': user};
      }

      final msg = _extractMessage(body) ?? 'Login gagal';
      throw Exception(msg);
    } on DioError catch (e) {
      // ✅ Handler 4xx: ambil pesan server kalau tersedia
      final data = e.response?.data;
      final body = data == null ? null : _normalizeBody(data);
      final msg = (body is Map)
          ? (_extractMessage(body) ?? 'Gagal login')
          : 'Gagal login';
      throw Exception(msg);
    }
  }

  // ------------------ REGISTER -------------------
  Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    required String role, // "buyer" | "seller"
    String? phone,
    String? storeName, // opsional untuk seller
  }) async {
    final payload = <String, dynamic>{
      'name': name.trim(),
      'email': email.trim(),
      'password': password,
      'role': role,
      if (phone != null && phone.isNotEmpty) 'phone': phone.trim(),
      if (role == 'seller' && storeName != null && storeName.isNotEmpty)
        'store_name': storeName.trim(),
    };

    final res = await _dio.post(
      'auth/register',
      data: payload,
      options: Options(headers: const {'Accept': 'application/json'}),
    );

    final code = res.statusCode ?? 0;
    final body = _normalizeBody(res.data);

    if (code == 200 || code == 201) {
      // Kembalikan body apa adanya (biasanya berisi token+user)
      return Map<String, dynamic>.from(body);
    }

    final msg = _extractMessage(body) ?? 'Registrasi gagal';
    throw Exception(msg);
  }

  // ---------------------- ME ---------------------
  /// ✅ Baru: panggil /auth/me tanpa perlu token argumen
  Future<Map<String, dynamic>> me() async {
    final res = await _dio.get(
      'auth/me',
      options: Options(headers: const {'Accept': 'application/json'}),
    );
    return (res.data as Map).cast<String, dynamic>();
  }

  // ------------------- LOGOUT --------------------
  Future<void> logout(String token) async {
    await _dio.post(
      'auth/logout',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }

  // =========================================================
  // Helpers
  // =========================================================
  dynamic _normalizeBody(dynamic data) {
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        return decoded;
      } catch (_) {
        return {'message': data};
      }
    }
    return data ?? {};
  }

  String? _extractToken(dynamic body) {
    if (body is! Map) return null;
    final Map b = body;

    // berbagai kemungkinan struktur dari backend
    final direct   = b['token'] ?? b['access_token'];
    final inData   = (b['data'] is Map) ? (b['data']['token'] ?? b['data']['access_token']) : null;
    final inResult = (b['result'] is Map) ? (b['result']['token'] ?? b['result']['access_token']) : null;

    final tok = (direct ?? inData ?? inResult);
    return (tok is String && tok.isNotEmpty) ? tok : null;
  }

  Map<String, dynamic>? _extractUser(dynamic body) {
    if (body is! Map) return null;
    final Map b = body;
    if (b['user'] is Map) return Map<String, dynamic>.from(b['user']);
    if (b['data'] is Map && (b['data']['user'] is Map)) {
      return Map<String, dynamic>.from(b['data']['user']);
    }
    return null;
  }

  String? _extractMessage(dynamic body) {
    if (body is! Map) return null;
    final Map b = body;
    // coba ambil dari beberapa field umum
    if (b['error'] is Map && (b['error']['message'] is String)) {
      return b['error']['message'] as String;
    }
    if (b['message'] is String) return b['message'] as String;
    if (b['errors'] is Map && (b['errors'] as Map).isNotEmpty) {
      final first = (b['errors'] as Map).values.first;
      if (first is List && first.isNotEmpty) return first.first.toString();
      return first.toString();
    }
    return null;
  }
}
