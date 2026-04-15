// lib/app/presentation/providers/order_history_provider.dart
import 'package:flutter/foundation.dart';

import '../../core/network/api.dart';

/// Provider untuk memuat daftar/riwayat pesanan (paginated).
/// - Default endpoint: 'orders/history'
/// - Jika backend-mu memakai 'orders' biasa, set endpoint:'orders' di konstruktor.
class OrderHistoryProvider with ChangeNotifier {
  OrderHistoryProvider({String? endpoint})
      : _endpoint = (endpoint?.trim().isNotEmpty == true)
            ? endpoint!.trim()
            : 'orders/history';

  // Endpoint yang digunakan untuk fetch list (mis. 'orders/history' atau 'orders')
  String _endpoint;

  // State
  bool _loading = false;
  String? _error;
  final List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];

  // Meta pagination
  int _currentPage = 1;
  int _lastPage = 1;
  int _total = 0;

  // Filters/Query terakhir (opsional)
  Map<String, dynamic>? _lastQuery;

  // Getters
  bool get isLoading => _loading;
  String? get error => _error;
  List<Map<String, dynamic>> get items => List.unmodifiable(_items);

  int get currentPage => _currentPage;
  int get lastPage => _lastPage;
  int get total => _total;

  /// Opsional: sinkronkan bearer ke helper API global (kalau belum diset via TokenStore)
  Future<void> setAuthToken(String? token) async {
    API.setBearer(token); // gunakan API helper baru
  }

  void _setLoading(bool v) {
    _loading = v;
    notifyListeners();
  }

  void _setError(String? e) {
    _error = e;
    notifyListeners();
  }

  /// Ambil halaman order (paginated).
  /// [append] = true untuk menambahkan ke list yang sudah ada (infinite scroll).
  Future<void> fetchPage({
    int page = 1,
    Map<String, dynamic>? query,
    bool append = false,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final qp = <String, dynamic>{'page': page, if (query != null) ...query};
      _lastQuery = query;

      final res = await API.get(_endpoint, query: qp);
      final j = API.decodeBody(res.data);

      // ----- Ambil list items dari berbagai bentuk payload -----
      List raw = const [];
      if (j is List) {
        raw = j;
      } else if (j is Map) {
        if (j['data'] is List) {
          raw = j['data'] as List;
        } else if (j['orders'] is List) {
          raw = j['orders'] as List;
        } else if (j['data'] is Map && (j['data']['data'] is List)) {
          // Laravel resource nested: { data: { data: [...], meta:..., links:... } }
          raw = (j['data']['data'] as List);
        }
      }

      final parsed = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (append) {
        _items.addAll(parsed);
      } else {
        _items
          ..clear()
          ..addAll(parsed);
      }

      // ----- Meta pagination (berbagai bentuk umum) -----
      if (j is Map) {
        if (j['current_page'] != null) {
          _currentPage = _toInt(j['current_page'], page);
          _lastPage = _toInt(j['last_page'], _lastPage);
          _total = _toInt(j['total'], _total);
        } else if (j['data'] is Map) {
          final m = j['data'] as Map;
          _currentPage = _toInt(m['current_page'], page);
          _lastPage = _toInt(m['last_page'], _lastPage);
          _total = _toInt(m['total'], _total);
        } else {
          // fallback jika tidak ada meta — set minimal
          _currentPage = page;
          _lastPage = page;
          _total = _items.length;
        }
      } else {
        // payload List tanpa meta
        _currentPage = page;
        _lastPage = page;
        _total = _items.length;
      }

      _setError(null);
    } catch (e) {
      _setError(e.toString());
      if (!append) _items.clear();
    } finally {
      _setLoading(false);
    }
  }

  /// Refresh halaman saat ini dengan query/filter terakhir.
  Future<void> refresh() =>
      fetchPage(page: _currentPage, query: _lastQuery, append: false);

  /// Ambil halaman berikutnya (jika masih ada).
  Future<void> nextPage() async {
    if (_currentPage >= _lastPage) return;
    await fetchPage(page: _currentPage + 1, query: _lastQuery, append: true);
  }

  /// Ganti endpoint (misal: 'orders' <-> 'orders/history') dan muat ulang.
  Future<void> setEndpoint(String endpoint, {bool reload = true}) async {
    final ep = endpoint.trim();
    if (ep.isEmpty) return;
    _endpoint = ep;
    if (reload) {
      await fetchPage(page: 1, query: _lastQuery, append: false);
    }
  }

  // ---- Helpers ----
  int _toInt(dynamic v, int dflt) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? dflt;
    return dflt;
  }
}
