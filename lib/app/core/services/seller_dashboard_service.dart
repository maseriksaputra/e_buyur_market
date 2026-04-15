// lib/app/core/services/seller_dashboard_service.dart
import 'dart:convert';
import '../network/api.dart';

class SellerDashboardService {
  // ---------- Helpers kompatibel (Dio/http) ----------
  static int _status(dynamic r) {
    try {
      final sc = r.statusCode;
      if (sc is int) return sc;
    } catch (_) {}
    return 0;
  }

  static bool _ok(int code) => code >= 200 && code < 300;

  static dynamic _payload(dynamic r) {
    // Prioritas: r.data (Dio), fallback r.body (http)
    try {
      final d = r.data;
      if (d != null) return d is String ? _tryDecode(d) : d;
    } catch (_) {}
    try {
      final b = r.body;
      if (b != null) return b is String ? _tryDecode(b) : b;
    } catch (_) {}
    return null;
  }

  static dynamic _tryDecode(String s) {
    try { return jsonDecode(s); } catch (_) { return s; }
  }

  static Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  static Map<String, dynamic> _extractData(dynamic p) {
    final m = _asMap(p);
    if (m.isEmpty) return {};

    // Pola umum: { data: {...} }
    final d = m['data'];
    if (d is Map) return Map<String, dynamic>.from(d);

    // Varian lain yang sering muncul
    for (final k in ['dashboard', 'summary', 'metrics']) {
      final v = m[k];
      if (v is Map) return Map<String, dynamic>.from(v);
    }

    // Jika API langsung mengembalikan objek metrik di root
    return m;
  }

  /// GET 'seller/dashboard' dengan query {days}
  static Future<Map<String, dynamic>> fetch({int days = 30}) async {
    final r = await API.get('seller/dashboard', query: {'days': days});
    if (_ok(_status(r))) {
      final p = _payload(r);
      return _extractData(p);
    }
    throw Exception('Gagal memuat dashboard (${_status(r)})');
  }
}
