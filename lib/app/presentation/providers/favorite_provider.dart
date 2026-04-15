// lib/app/presentation/providers/favorite_provider.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

// ✅ pakai helper API proyekmu (tanpa /api di path)
import '../../core/network/api.dart';

class FavoriteProvider with ChangeNotifier {
  bool _isLoading = false;
  String? _error;
  int _count = 0;
  List<Map<String, dynamic>> _items = [];

  bool _disposed = false;
  int _seq = 0;

  bool get isLoading => _isLoading;
  String? get error => _error;
  int get count => _count;
  List<Map<String, dynamic>> get items => List.unmodifiable(_items);

  void _notifySafe() {
    if (!_disposed) notifyListeners();
  }

  void _setLoading(bool v) {
    _isLoading = v;
    _notifySafe();
  }

  void _setError(String? e) {
    _error = e;
    _notifySafe();
  }

  void _setItems(List<Map<String, dynamic>> list) {
    _items = list;
    _count = list.length;
    _notifySafe();
  }

  void reset() {
    _items = [];
    _count = 0;
    _error = null;
    _isLoading = false;
    _notifySafe();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // =======================
  // COMPAT LAYER untuk API
  // =======================
  static Future<Response<dynamic>> _getCompat(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final dynamic api = API;
    return await api.get(path, query: query);
  }

  static Future<Response<dynamic>> _deleteCompat(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final dynamic api = API;
    try {
      return await api.delete(path, query: query);
    } catch (_) {
      // fallback tanpa named query (kalau implementasi lama)
      return await api.delete(path);
    }
  }

  static Future<Response<dynamic>> _postCompat(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    final dynamic api = API;
    try {
      // Jika ada API.post(path, data: ...)
      return await api.post(path, data: data);
    } catch (_) {
      // Fallback: postJson(path, data: {...})
      try {
        return await api.postJson(path, data: data);
      } catch (_) {
        // Fallback positional (kompat lama)
        return await api.postJson(path, data);
      }
    }
  }

  // =======================
  // Utils parsing JSON
  // =======================
  static dynamic _ensureJson(dynamic data) {
    if (data == null) return null;
    if (data is String) {
      try {
        return jsonDecode(data);
      } catch (_) {
        return data;
      }
    }
    return data;
  }

  static List<Map<String, dynamic>> _extractList(dynamic j) {
    if (j == null) return <Map<String, dynamic>>[];
    if (j is Map) {
      for (final k in ['data', 'items', 'favorites']) {
        final v = j[k];
        if (v is List) {
          return v.map<Map<String, dynamic>>((e) {
            if (e is Map<String, dynamic>) return e;
            if (e is Map) return Map<String, dynamic>.from(e);
            return <String, dynamic>{'value': e};
          }).toList();
        }
      }
      return [Map<String, dynamic>.from(j)];
    }
    if (j is List) {
      return j.map<Map<String, dynamic>>((e) {
        if (e is Map<String, dynamic>) return e;
        if (e is Map) return Map<String, dynamic>.from(e);
        return <String, dynamic>{'value': e};
      }).toList();
    }
    return <Map<String, dynamic>>[];
  }

  static int? _extractCount(dynamic j) {
    if (j == null) return null;
    if (j is Map) {
      if (j['count'] != null) return int.tryParse(j['count'].toString());
      for (final k in ['total', 'total_count', 'favorites_count']) {
        if (j[k] != null) return int.tryParse(j[k].toString());
      }
      final meta = j['meta'];
      if (meta is Map && meta['count'] != null) {
        return int.tryParse(meta['count'].toString());
      }
      final list = _extractList(j);
      return list.isNotEmpty ? list.length : null;
    }
    if (j is List) return j.length;
    return null;
  }

  // =======================
  // Endpoints (tanpa /api)
  // =======================
  static const _listCandidates = <String>['favorites', 'buyer/favorites'];
  static const _countCandidates = <String>[
    'favorites/count',
    'buyer/favorites/count'
  ];

  // =======================
  // PUBLIC API
  // =======================

  Future<void> fetchList({String? token}) async {
    final int mySeq = ++_seq;
    if (token == null || token.isEmpty) {
      _setItems([]);
      _setError(null);
      return;
    }

    _setLoading(true);
    _setError(null);
    String? lastError;
    List<Map<String, dynamic>>? got;

    for (final path in _listCandidates) {
      if (mySeq != _seq || _disposed) return;
      try {
        final r = await _getCompat(path).timeout(const Duration(seconds: 12));
        if (mySeq != _seq || _disposed) return;

        final code = r.statusCode ?? 0;
        if (code >= 200 && code < 300) {
          final j = _ensureJson(r.data);
          got = _extractList(j);
          break;
        } else {
          lastError = 'HTTP $code pada $path';
        }
      } on DioException catch (e) {
        lastError = 'HTTP ${e.response?.statusCode ?? '-'} pada $path';
      } on TimeoutException {
        lastError = 'Timeout saat akses $path';
      } catch (e) {
        lastError = '$e';
      }
    }

    if (mySeq != _seq || _disposed) return;
    if (got != null) {
      _setItems(got);
      _setError(null);
    } else {
      _setItems([]);
      _setError('Gagal memuat favorit. ${lastError ?? ''}'.trim());
    }
    _setLoading(false);
  }

  Future<void> refresh(String? token) async {
    final int mySeq = ++_seq;
    if (token == null || token.isEmpty) {
      _count = 0;
      _setError(null);
      _setLoading(false);
      return;
    }

    _setLoading(true);
    _setError(null);
    String? lastError;
    int? found;

    // Coba endpoint count lebih dulu
    for (final path in _countCandidates) {
      if (mySeq != _seq || _disposed) return;
      try {
        final r = await _getCompat(path).timeout(const Duration(seconds: 12));
        if (mySeq != _seq || _disposed) return;

        final code = r.statusCode ?? 0;
        if (code >= 200 && code < 300) {
          final j = _ensureJson(r.data);
          final c = _extractCount(j);
          if (c != null) {
            found = c;
            break;
          }
          lastError = 'Format tidak dikenali pada $path';
        } else {
          lastError = 'HTTP $code pada $path';
        }
      } on DioException catch (e) {
        lastError = 'HTTP ${e.response?.statusCode ?? '-'} pada $path';
      } on TimeoutException {
        lastError = 'Timeout saat akses $path';
      } catch (e) {
        lastError = '$e';
      }
    }

    // Fallback: hitung dari list
    if (found == null) {
      for (final path in _listCandidates) {
        if (mySeq != _seq || _disposed) return;
        try {
          final r = await _getCompat(path).timeout(const Duration(seconds: 12));
          if (mySeq != _seq || _disposed) return;

          final code = r.statusCode ?? 0;
          if (code >= 200 && code < 300) {
            final j = _ensureJson(r.data);
            final list = _extractList(j);
            found = list.length;
            break;
          } else {
            lastError = 'HTTP $code pada $path';
          }
        } on DioException catch (e) {
          lastError = 'HTTP ${e.response?.statusCode ?? '-'} pada $path';
        } on TimeoutException {
          lastError = 'Timeout saat akses $path';
        } catch (e) {
          lastError = '$e';
        }
      }
    }

    if (mySeq != _seq || _disposed) return;
    _count = found ?? 0;
    _setError((found == null && lastError != null)
        ? 'Gagal memuat favorit. $lastError'
        : null);
    _setLoading(false);
  }

  /// Tambah favorit — konsisten: API.postJson('favorites', data: {...})
  Future<bool> add(int productId) async {
    try {
      final r = await _postCompat('favorites', data: {'product_id': productId})
          .timeout(const Duration(seconds: 12));

      final code = r.statusCode ?? 0;
      if (code >= 200 && code < 300) {
        _count += 1;
        _notifySafe();
        return true;
      }
      _setError('Gagal menambah favorit (HTTP $code).');
      return false;
    } on DioException catch (e) {
      _setError('Gagal menambah favorit (HTTP ${e.response?.statusCode ?? '-'})');
      return false;
    } on TimeoutException {
      _setError('Timeout saat menambah favorit.');
      return false;
    } catch (e) {
      _setError('Gagal menambah favorit: $e');
      return false;
    }
  }

  Future<bool> removeByFavoriteId(int favoriteId) async {
    final candidates = <String>[
      'favorites/$favoriteId',
      'buyer/favorites/$favoriteId'
    ];
    String? lastError;
    for (final path in candidates) {
      try {
        final r =
            await _deleteCompat(path).timeout(const Duration(seconds: 12));
        final code = r.statusCode ?? 0;
        if (code >= 200 && code < 300) {
          _count = (_count > 0) ? _count - 1 : 0;
          _notifySafe();
          return true;
        }
        lastError = 'HTTP $code pada $path';
      } on DioException catch (e) {
        lastError = 'HTTP ${e.response?.statusCode ?? '-'} pada $path';
      } on TimeoutException {
        lastError = 'Timeout saat akses $path';
      } catch (e) {
        lastError = '$e';
      }
    }
    _setError('Gagal menghapus favorit. ${lastError ?? ''}'.trim());
    return false;
  }

  Future<bool> removeByProductId(int productId) async {
    final tries = <Future<Response<dynamic>> Function()>[
      () => _deleteCompat('favorites/by-product/$productId'),
      () => _deleteCompat('favorites/product/$productId'),
      () => _deleteCompat('favorites', query: {'product_id': productId}),
      () => _deleteCompat('buyer/favorites/by-product/$productId'),
    ];

    String? lastError;
    for (final call in tries) {
      try {
        final r = await call().timeout(const Duration(seconds: 12));
        final code = r.statusCode ?? 0;
        if (code >= 200 && code < 300) {
          _count = (_count > 0) ? _count - 1 : 0;
          _notifySafe();
          return true;
        }
        lastError = 'HTTP $code';
      } on DioException catch (e) {
        lastError = 'HTTP ${e.response?.statusCode ?? '-'}';
      } on TimeoutException {
        lastError = 'Timeout';
      } catch (e) {
        lastError = '$e';
      }
    }
    _setError(
        'Gagal menghapus favorit by product_id. ${lastError ?? ''}'.trim());
    return false;
  }

  Future<bool> toggle(int productId, {bool? currentlyFavorited}) async {
    bool isFav = currentlyFavorited ??
        _items.any((e) {
          final pid = e['product_id'] ?? e['productId'];
          return pid?.toString() == productId.toString();
        });

    if (isFav) {
      final ok = await removeByProductId(productId);
      if (!ok) return false;
      return true;
    } else {
      return await add(productId);
    }
  }
}
