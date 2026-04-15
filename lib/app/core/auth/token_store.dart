// lib/app/core/auth/token_store.dart
import '../network/api.dart';

class TokenStore {
  static Future<void> write(String token) async {
    API.setBearer(token);
    // ... simpan juga ke secure storage kalau memang digunakan
  }

  static Future<void> clear() async {
    API.setBearer(null);
    // ... hapus dari storage jika ada
  }
}
