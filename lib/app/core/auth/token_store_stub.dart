// lib/app/core/auth/token_store_stub.dart
class TokenStore {
  static String? _mem;

  static Future<void> save(String token) async {
    _mem = token;
  }

  static Future<String?> read() async => _mem;

  static Future<void> clear() async {
    _mem = null;
  }
}
