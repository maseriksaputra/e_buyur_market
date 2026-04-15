// lib/app/core/services/profile_api_service.dart
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:e_buyur_market_flutter_5/app/core/network/api.dart';

class ProfileApiService {
  /// GET /api/auth/me
  /// Mengembalikan Map user. Menangani berbagai bentuk payload:
  /// - { status: "success", data: {...user} }
  /// - {...user}
  /// - String JSON
  static Future<Map<String, dynamic>> getMe() async {
    final Response res = await API.dio.get('auth/me');

    // Normalisasi body (kadang backend mengirim String)
    dynamic body = res.data;
    if (body is String) {
      try { body = jsonDecode(body); } catch (_) {/* biarkan apa adanya */}
    }

    // Jika status bukan 200, coba ambil pesan error dari body
    if (res.statusCode != 200) {
      final msg = _extractErrorMessage(body) ?? res.statusMessage ?? 'Server Error';
      throw Exception(msg);
    }

    // Ambil objek user dari body
    final map = _asMap(body);

    // Pola umum: { status: "success", data: {...} }
    final hasStatusSuccess =
        map['status']?.toString().toLowerCase() == 'success' && map['data'] is Map;

    if (hasStatusSuccess) {
      return Map<String, dynamic>.from(map['data'] as Map);
    }

    // Jika tidak ada pembungkus 'status', kembalikan map apa adanya (anggap langsung user)
    return map;
  }

  /// Update profil pembeli. Mencoba beberapa endpoint agar cocok dengan variasi backend:
  /// 1) PATCH /api/users/:id
  /// 2) PATCH /api/buyers/:id
  /// 3) PATCH /api/profile/buyer
  ///
  /// Mengembalikan payload map (umumnya user terbaru / { ok: true }).
  static Future<Map<String, dynamic>> updateBuyer({
    required int userId,
    required String name,
    required String email,
    required String phone,
  }) async {
    final payload = <String, dynamic>{
      'name': name,
      'email': email,
      // Beberapa backend memakai kunci berbeda untuk nomor HP
      'phone': phone,
      'hp': phone,
      'no_hp': phone,
    };

    // Coba berurutan. Jika semua gagal, lempar exception terakhir.
    Response res;

    try {
      res = await API.dio.patch('/api/users/$userId', data: payload);
    } on DioException catch (_) {
      try {
        res = await API.dio.patch('/api/buyers/$userId', data: payload);
      } on DioException catch (_) {
        res = await API.dio.patch('/api/profile/buyer', data: payload);
      }
    }

    // Normalisasi & validasi
    dynamic body = res.data;
    if (body is String) {
      try { body = jsonDecode(body); } catch (_) {}
    }

    // Kalau bukan 2xx, lempar pesan error yang jelas
    if (res.statusCode == null || res.statusCode! < 200 || res.statusCode! >= 300) {
      final msg = _extractErrorMessage(body) ?? res.statusMessage ?? 'Server Error';
      throw Exception(msg);
    }

    final map = _asMap(body);

    // Jika bentuknya { status: "success", data: {...} }, kembalikan data
    if (map['status']?.toString().toLowerCase() == 'success') {
      final data = map['data'];
      if (data is Map) return Map<String, dynamic>.from(data);
      // beberapa server balas { status: "success", message: "...", data: null }
      return {'ok': true, 'message': map['message']};
    }

    // Jika tidak ada konvensi status, kembalikan map apa adanya
    // (umumnya berisi user yang sudah diperbarui)
    return map.isNotEmpty ? map : {'ok': true};
  }

  // ===== Helpers =====

  /// Pastikan keluaran berupa Map<String, dynamic>.
  static Map<String, dynamic> _asMap(dynamic body) {
    if (body is Map<String, dynamic>) return body;
    if (body is Map) return Map<String, dynamic>.from(body);
    // Jika bukan map, bungkus agar pemanggil tetap dapat struktur Map.
    return <String, dynamic>{'data': body};
  }

  /// Ambil pesan error dari payload berbagai bentuk.
  static String? _extractErrorMessage(dynamic body) {
    if (body is String) return body; // body text plain
    if (body is Map) {
      // Prioritas: error.message -> message -> msg
      final err = body['error'];
      if (err is Map) {
        final m = err['message'] ?? err['msg'];
        if (m is String && m.trim().isNotEmpty) return m;
      }
      final m = body['message'] ?? body['msg'];
      if (m is String && m.trim().isNotEmpty) return m;
    }
    return null;
    }
}
