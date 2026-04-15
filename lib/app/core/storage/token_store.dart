// lib/app/core/storage/token_store.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStore {
  static const _k = 'auth_token';
  static const _storage = FlutterSecureStorage();

  static Future<String?> read() => _storage.read(key: _k);
  static Future<void> write(String token) =>
      _storage.write(key: _k, value: token);
  static Future<void> clear() => _storage.delete(key: _k);
}
