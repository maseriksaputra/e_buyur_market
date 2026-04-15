// lib/app/presentation/auth/token_store.dart
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class TokenStore {
  static final _storage = const FlutterSecureStorage();
  static const _key = 'auth_token';

  // Dio singleton untuk seluruh app
  static final Dio dio = Dio(BaseOptions(
    baseUrl: dotenv.env['API_BASE_URL'] ?? 'https://api.ebuyurmarket.com',
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 20),
    headers: {'Accept': 'application/json'},
  ));

  static Future<void> bootstrap() async {
    final t = await read();
    if (t != null && t.isNotEmpty) {
      dio.options.headers['Authorization'] = 'Bearer $t';
    }
  }

  static Future<void> save(String token) async {
    await _storage.write(key: _key, value: token);
    dio.options.headers['Authorization'] = 'Bearer $token';
  }

  static Future<String?> read() => _storage.read(key: _key);

  static Future<void> clear() async {
    await _storage.delete(key: _key);
    dio.options.headers.remove('Authorization');
  }
}
