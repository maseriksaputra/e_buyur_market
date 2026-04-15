// lib/app/core/services/auth_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:e_buyur_market_flutter_5/app/common/models/user_model.dart';

class _LoginResult {
  final String token;
  final User user;
  _LoginResult({required this.token, required this.user});
}

/// Base URL dari --dart-define
/// Utamakan API_BASE; jika kosong, jatuh ke API_BASE_URL (kompat lama).
/// Contoh run:
///   flutter run -d chrome --dart-define=API_BASE=http://192.168.1.10:8000
class AuthService {
  static const String _baseFromApiBase =
      String.fromEnvironment('API_BASE', defaultValue: '');
  static const String _baseFromApiBaseUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8000');

  static String get baseUrl =>
      _baseFromApiBase.isNotEmpty ? _baseFromApiBase : _baseFromApiBaseUrl;

  Uri _u(String p) {
    final root = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final path = p.startsWith('/') ? p : '/$p';
    return Uri.parse('$root$path');
  }

  Map<String, String> _headers({String? token}) => {
        'Accept': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  Never _throw(http.Response r) {
    try {
      final m = jsonDecode(r.body);
      final msg = (m is Map && m['message'] is String)
          ? m['message'] as String
          : r.reasonPhrase ?? 'Error';
      throw Exception(msg);
    } catch (_) {
      throw Exception('${r.statusCode} ${r.reasonPhrase ?? 'Error'}');
    }
  }

  // --- helper kecil untuk normalize Map<dynamic,dynamic> -> Map<String,dynamic>
  Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  /// Parse user fleksibel dari response body (mendukung:
  /// - { user: {...} }
  /// - { data: { user: {...} } }
  /// - langsung objek user)
  User _mustParseUser(dynamic body) {
    final root = _asMap(body) ?? {};
    Map<String, dynamic>? userMap;

    // 1) body.user
    userMap = _asMap(root['user']);

    // 2) body.data.user
    if (userMap == null && root['data'] != null) {
      final data = _asMap(root['data']);
      userMap = _asMap(data?['user']);
    }

    // 3) fallback: root itu sendiri dianggap user object
    userMap ??= _asMap(root);

    if (userMap == null || userMap.isEmpty) {
      throw Exception('User tidak ditemukan pada response');
    }
    return User.fromJson(userMap);
  }

  // ---------- API CALLS ----------
  Future<_LoginResult> login({
    required String email,
    required String password,
    String? role,
  }) async {
    final r = await http.post(
      _u('/api/auth/login'),
      headers: _headers(),
      body: {
        'email': email,
        'password': password,
        if (role != null && role.isNotEmpty) 'role': role,
      },
    );
    if (r.statusCode != 200) _throw(r);

    final body = jsonDecode(r.body);
    final token = (body['token'] ?? '') as String;
    if (token.isEmpty) throw Exception('Token kosong dari server');

    final user = _mustParseUser(body);
    return _LoginResult(token: token, user: user);
  }

  Future<_LoginResult> registerBuyer({
    required String name,
    required String email,
    required String password,
    required String passwordConfirmation,
    String? phone,
    String? address,
    String? city,
    String? postalCode,
  }) async {
    final r = await http.post(
      _u('/api/auth/register/buyer'),
      headers: _headers(),
      body: {
        'name': name,
        'email': email,
        'password': password,
        'password_confirmation': passwordConfirmation,
        if (phone != null) 'phone': phone,
        if (address != null) 'address': address,
        if (city != null) 'city': city,
        if (postalCode != null) 'postal_code': postalCode,
      },
    );
    if (r.statusCode != 201) _throw(r);

    final body = jsonDecode(r.body);
    final token = (body['token'] ?? '') as String;
    if (token.isEmpty) throw Exception('Token kosong dari server');

    final user = _mustParseUser(body);
    return _LoginResult(token: token, user: user);
  }

  Future<_LoginResult> registerSeller({
    required String name,
    required String email,
    required String password,
    required String passwordConfirmation,
    required String storeName,
    String? storeDescription,
    String? phone,
    String? pickupAddress,
  }) async {
    final r = await http.post(
      _u('/api/auth/register/seller'),
      headers: _headers(),
      body: {
        'name': name,
        'email': email,
        'password': password,
        'password_confirmation': passwordConfirmation,
        'store_name': storeName,
        if (storeDescription != null) 'store_description': storeDescription,
        if (phone != null) 'phone': phone,
        if (pickupAddress != null) 'pickup_address': pickupAddress,
      },
    );
    if (r.statusCode != 201) _throw(r);

    final body = jsonDecode(r.body);
    final token = (body['token'] ?? '') as String;
    if (token.isEmpty) throw Exception('Token kosong dari server');

    final user = _mustParseUser(body);
    return _LoginResult(token: token, user: user);
  }

  Future<User> me(String token) async {
    final r =
        await http.get(_u('/api/auth/me'), headers: _headers(token: token));
    if (r.statusCode != 200) _throw(r);

    final body = jsonDecode(r.body);
    return _mustParseUser(body);
  }

  Future<void> logout(String token) async {
    final r = await http.post(_u('/api/auth/logout'),
        headers: _headers(token: token));
    if (r.statusCode != 200) _throw(r);
  }
}
