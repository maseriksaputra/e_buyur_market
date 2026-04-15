// lib/app/presentation/providers/orders_provider.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import '../../core/network/api.dart';
import '../../core/services/product_api_service.dart' show ProductApiService;

/// Provider untuk daftar pesanan (orders) + detail + aksi umum.
/// - Tanpa '/api/' di path (seragam dengan migrasi API terbaru)
/// - Fallback multi-endpoint agar kompatibel dengan variasi backend
class OrdersProvider with ChangeNotifier {
  // ===== Guard race-condition & safe-notify =====
  bool _disposed = false;
  int _seq = 0; // nomor urut request terakhir

  void _notifySafe() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // ===== State =====
  bool _loading = false;
  String? _error;

  final List<Map<String, dynamic>> _orders = <Map<String, dynamic>>[];

  // meta pagination (jika ada di respons)
  int? _currentPage;
  int? _lastPage;
  int? _total;
  String? _statusFilter;

  // cancel token agar list sebelumnya bisa dibatalkan saat user cepat scroll/ubah filter
  CancelToken? _lastToken;

  // ===== Getters =====
  bool get isLoading => _loading;
  String? get error => _error;

  List<Map<String, dynamic>> get orders => List.unmodifiable(_orders);

  int? get currentPage => _currentPage;
  int? get lastPage => _lastPage;
  int? get total => _total;

  String? get statusFilter => _statusFilter;

  // ===== Small mutators =====
  void _setLoading(bool v) {
    _loading = v;
    _notifySafe();
  }

  void _setError(String? e) {
    _error = e;
    _notifySafe();
  }

  void setStatusFilter(String? status) {
    final s = status?.trim();
    _statusFilter = (s == null || s.isEmpty) ? null : s;
    _notifySafe();
  }

  /// Opsional: injeksi token Bearer (sinkron ke API global).
  void setAuthToken(String? token) => API.setBearer(token);

  // ===== Helpers decode payload =====
  dynamic _decode(dynamic body) => ProductApiService.decodeBody(body);

  List _asList(dynamic body) {
    final j = _decode(body);
    if (j is List) return j;
    if (j is Map && j['data'] is List) return List.from(j['data'] as List);
    return const [];
  }

  Map<String, dynamic> _asMap(dynamic body) {
    final j = _decode(body);
    if (j is Map<String, dynamic>) return j;
    if (j is Map && j['data'] is Map) return Map<String, dynamic>.from(j['data'] as Map);
    return <String, dynamic>{};
  }

  // ====== Normalisasi respons meta (current_page, last_page, total) ======
  void _applyMetaFrom(dynamic root) {
    try {
      final j = _decode(root);
      Map<String, dynamic> meta;
      if (j is Map && j['meta'] is Map) {
        meta = Map<String, dynamic>.from(j['meta'] as Map);
      } else if (j is Map) {
        meta = Map<String, dynamic>.from(j);
      } else {
        return;
      }

      int _toInt(dynamic v, int? d) {
        if (v is num) return v.toInt();
        return int.tryParse('$v') ?? (d ?? 0);
      }

      _currentPage = meta.containsKey('current_page')
          ? _toInt(meta['current_page'], _currentPage)
          : _currentPage;
      _lastPage = meta.containsKey('last_page')
          ? _toInt(meta['last_page'], _lastPage)
          : _lastPage;
      _total = meta.containsKey('total') ? _toInt(meta['total'], _total) : _total;
    } catch (_) {
      // abaikan meta jika format berbeda
    }
  }

  // ====== Common: pilih endpoint terbaik ======
  Future<Response> _getOrdersFromAny({
    required int page,
    String? status,
    CancelToken? cancelToken,
  }) async {
    // 🔁 Urutan prioritas: history → my → buyer/orders → orders
    final candidates = <String>[
      'orders/history',
      'buyer/orders/history',
      'orders/my',
      'buyer/orders',
      'orders',
    ];

    DioException? lastErr;

    for (final path in candidates) {
      try {
        final r = await API.dio.get(
          path,
          queryParameters: {
            'page': page,
            if (status != null && status.isNotEmpty) 'status': status,
          },
          cancelToken: cancelToken,
        );

        final code = r.statusCode ?? 0;
        if (code >= 200 && code < 300) return r;

        lastErr = DioException(
          requestOptions: r.requestOptions,
          response: r,
          type: DioExceptionType.badResponse,
          error: r.statusMessage ?? 'HTTP $code',
        );
      } on DioException catch (e) {
        lastErr = e;
      }
    }
    throw lastErr ??
        DioException(
          requestOptions: RequestOptions(path: candidates.join('|')),
          error: 'Tidak ada endpoint orders yang merespons.',
          type: DioExceptionType.unknown,
        );
  }

  Future<Response> _getOrderDetailFromAny(dynamic id) async {
    final orderId = '$id';
    final candidates = <String>[
      'orders/$orderId',
      'orders/history/$orderId',
      'buyer/orders/$orderId',
      'buyer/orders/history/$orderId',
    ];
    DioException? lastErr;
    for (final path in candidates) {
      try {
        final r = await API.dio.get(path);
        final code = r.statusCode ?? 0;
        if (code >= 200 && code < 300) return r;
        lastErr = DioException(
          requestOptions: r.requestOptions,
          response: r,
          type: DioExceptionType.badResponse,
          error: r.statusMessage ?? 'HTTP $code',
        );
      } on DioException catch (e) {
        lastErr = e;
      }
    }
    throw lastErr ??
        DioException(
          requestOptions: RequestOptions(path: candidates.join('|')),
          error: 'Tidak ada endpoint detail order yang merespons.',
          type: DioExceptionType.unknown,
        );
  }

  // ===== Actions =====

  /// Muat ulang daftar pesanan (page 1).
  Future<void> refresh({int page = 1, String? status}) async {
    final mySeq = ++_seq;

    _lastToken?.cancel('cancel previous list');
    _lastToken = CancelToken();

    _setLoading(true);
    _setError(null);

    try {
      final r = await _getOrdersFromAny(
        page: page,
        status: status ?? _statusFilter,
        cancelToken: _lastToken,
      );

      if (mySeq != _seq || _disposed) return;

      final dataList = _asList(r.data);

      _orders
        ..clear()
        ..addAll(
          dataList
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList(),
        );

      _currentPage = page;
      _applyMetaFrom(r.data);
      _setError(null);
    } on DioException catch (e) {
      if (mySeq != _seq || _disposed) return;
      _setError(_stringifyDioError(e));
    } catch (e) {
      if (mySeq != _seq || _disposed) return;
      _setError(e.toString());
    } finally {
      if (mySeq != _seq || _disposed) return;
      _setLoading(false);
    }
  }

  /// Ambil halaman berikutnya dan menambahkan ke list.
  Future<void> loadMore() async {
    if (_loading) return;
    final next = (_currentPage ?? 1) + 1;
    if (_lastPage != null && next > _lastPage!) return;

    final mySeq = ++_seq;
    _setLoading(true);
    try {
      final r = await _getOrdersFromAny(
        page: next,
        status: _statusFilter,
      );

      if (mySeq != _seq || _disposed) return;

      final dataList = _asList(r.data);
      _orders.addAll(
        dataList
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );

      _currentPage = next;
      _applyMetaFrom(r.data);
      _setError(null);
    } on DioException catch (e) {
      if (mySeq != _seq || _disposed) return;
      _setError(_stringifyDioError(e));
    } catch (e) {
      if (mySeq != _seq || _disposed) return;
      _setError(e.toString());
    } finally {
      if (mySeq != _seq || _disposed) return;
      _setLoading(false);
    }
  }

  /// Ambil detail 1 order. Mengembalikan Map (aman untuk berbagai bentuk API).
  Future<Map<String, dynamic>?> fetchDetail(dynamic id) async {
    try {
      final r = await _getOrderDetailFromAny(id);
      final m = _asMap(r.data);
      if (m.isEmpty) {
        // beberapa API kirim { order: {...} }
        final root = _decode(r.data);
        if (root is Map && root.values.whereType<Map>().isNotEmpty) {
          return Map<String, dynamic>.from(
              root.values.firstWhere((v) => v is Map) as Map);
        }
      }
      return m.isNotEmpty ? m : null;
    } on DioException catch (e) {
      _setError(_stringifyDioError(e));
      return null;
    } catch (e) {
      _setError(e.toString());
      return null;
    }
  }

  /// Batalkan order.
  /// Mencoba beberapa endpoint umum: `orders/{id}/cancel`, `buyer/orders/{id}/cancel`.
  Future<bool> cancelOrder(dynamic id, {String? reason}) async {
    final orderId = '$id';
    final candidates = <String>[
      'orders/$orderId/cancel',
      'buyer/orders/$orderId/cancel',
    ];
    for (final path in candidates) {
      try {
        final r = await API.postJson(path, data: {
          if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        });
        if ((r.statusCode ?? 500) >= 400) continue;
        await refresh(page: 1, status: _statusFilter); // sync ulang list
        return true;
      } catch (_) {
        // coba kandidat berikutnya
      }
    }
    _setError('Gagal membatalkan pesanan.');
    return false;
  }

  /// Konfirmasi penerimaan/barang sudah diterima.
  /// Mencoba endpoint: `orders/{id}/received`, `buyer/orders/{id}/received`.
  Future<bool> confirmReceived(dynamic id) async {
    final orderId = '$id';
    final paths = <String>[
      'orders/$orderId/received',
      'buyer/orders/$orderId/received',
    ];
    for (final p in paths) {
      try {
        final r = await API.postJson(p, data: const {});
        if ((r.statusCode ?? 500) >= 400) continue;
        await refresh(page: 1, status: _statusFilter);
        return true;
      } catch (_) {}
    }
    _setError('Gagal mengonfirmasi penerimaan pesanan.');
    return false;
  }

  // ===== Utils =====
  String _stringifyDioError(DioException e) {
    // tampilkan pesan server kalau ada
    final data = e.response?.data;
    try {
      final j = (data is String) ? jsonDecode(data) : data;
      if (j is Map) {
        if (j['message'] is String && (j['message'] as String).isNotEmpty) {
          return j['message'] as String;
        }
        if (j['error'] is String && (j['error'] as String).isNotEmpty) {
          return j['error'] as String;
        }
        if (j['errors'] is Map && (j['errors'] as Map).isNotEmpty) {
          final first = (j['errors'] as Map).values.first;
          if (first is List && first.isNotEmpty) return '${first.first}';
          return '$first';
        }
      }
    } catch (_) {}
    final sc = e.response?.statusCode;
    final sm = e.response?.statusMessage ?? e.message;
    return 'HTTP ${sc ?? '-'}: ${sm ?? 'Terjadi kesalahan'}';
  }
}
