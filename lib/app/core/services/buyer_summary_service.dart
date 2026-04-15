// lib/app/core/services/buyer_summary_service.dart
import 'dart:convert';
import '../api/api.dart';

class BuyerSummary {
  final int cart;
  final int favorites;
  BuyerSummary({required this.cart, required this.favorites});
}

class BuyerSummaryService {
  // ---------- Helpers kompatibel (Dio/http) ----------
  static int _status(dynamic r) {
    try { final sc = r.statusCode; if (sc is int) return sc; } catch (_) {}
    return 0;
  }

  static bool _ok(int code) => code >= 200 && code < 300;

  static dynamic _payload(dynamic r) {
    // Prioritas: r.data (Dio), fallback r.body (http)
    dynamic d;
    try { d = r.data; } catch (_) {}
    if (d != null) return d;

    dynamic b;
    try { b = r.body; } catch (_) {}
    if (b is String) {
      try { return jsonDecode(b); } catch (_) { return b; }
    }
    return b;
  }

  static int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    final s = v.toString();
    final i = int.tryParse(s);
    if (i != null) return i;
    final d = double.tryParse(s);
    return d?.toInt() ?? 0;
  }

  static List _extractListFromMap(Map m) {
    for (final k in ['data', 'items', 'list', 'cart', 'favorites']) {
      final v = m[k];
      if (v is List) return v;
    }
    return const [];
  }

  static int _extractCount(dynamic j, {List<String> preferKeys = const []}) {
    // Urutan: preferKeys → count/total* → meta.count → panjang list
    if (j is Map) {
      for (final k in preferKeys) {
        if (j.containsKey(k)) return _asInt(j[k]);
      }
      if (j.containsKey('count')) return _asInt(j['count']);
      for (final k in ['total', 'total_count', 'favorites_count', 'cart_count']) {
        if (j.containsKey(k)) return _asInt(j[k]);
      }
      final meta = j['meta'];
      if (meta is Map && meta['count'] != null) return _asInt(meta['count']);
      final list = _extractListFromMap(j);
      return list.length;
    }
    if (j is List) return j.length;
    return 0;
  }

  // ---------- Public ----------
  static Future<BuyerSummary> fetch() async {
    // 1) Endpoint gabungan (kalau tersedia)
    final res1 = await API.get('buyer/me/summary');
    if (_ok(_status(res1))) {
      final p = _payload(res1);
      if (p is Map) {
        final cart = _extractCount(p, preferKeys: ['cart_count', 'cartCount']);
        final fav  = _extractCount(p, preferKeys: ['favorites_count', 'favoritesCount']);
        return BuyerSummary(cart: cart, favorites: fav);
      }
    }

    // 2) Fallback: hitungan terpisah
    final cartRes = await API.get('buyer/cart/count');
    final favRes  = await API.get('buyer/favorites/count');
    if (_ok(_status(cartRes)) && _ok(_status(favRes))) {
      final c = _extractCount(_payload(cartRes));
      final f = _extractCount(_payload(favRes));
      return BuyerSummary(cart: c, favorites: f);
    }

    // 3) Fallback terakhir: ambil list lalu hitung panjang.
    final cartList = await API.get('buyer/cart');
    final favList  = await API.get('buyer/favorites');

    final cc = _ok(_status(cartList))
        ? _extractCount(_payload(cartList))
        : 0;
    final ff = _ok(_status(favList))
        ? _extractCount(_payload(favList))
        : 0;

    return BuyerSummary(cart: cc, favorites: ff);
  }
}
