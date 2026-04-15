// lib/app/presentation/providers/product_provider.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../../core/network/api.dart';
import '../../common/models/product_model.dart';

class ProductProvider extends ChangeNotifier {
  // ===== State =====
  final List<Product> _items = <Product>[];

  // Loading & request coalescing
  bool _loading = false;
  Future<void>? _inflight;
  DateTime? _lastFetchAt;
  String? _lastKey;

  String? _error;

  int _currentPage = 1;
  int _lastPage = 1;

  // Simpan filter terakhir agar nextPage/refresh konsisten
  String? _lastSearch;
  String? _lastCategory;
  int _lastPerPage = 24;

  // ===== Getters =====
  List<Product> get items => List.unmodifiable(_items);
  List<Product> get products => items; // kompat lama
  bool get isLoading => _loading;
  bool get loading => _loading;        // kompat lama
  String? get error => _error;
  bool get canLoadMore => _currentPage < _lastPage;

  // ===== Normalisasi kategori dari chip UI =====
  String? _normalizeCategory(String? cat) {
    if (cat == null || cat.trim().isEmpty) return null;
    final c = cat.trim().toLowerCase();
    if (c == 'semua' || c == 'all') return null;
    if (c == 'buah') return 'buah';
    if (c == 'sayur' || c == 'sayuran') return 'sayur';
    return c;
  }

  // ===== API Utama (fleksibel terhadap bentuk response) =====
  Future<void> fetch({
    String? search,
    String? category, // "Semua" | "Buah" | "Sayur" | lainnya
    int page = 1,
    int perPage = 24,
    bool append = false,
    bool force = false, // ✅ baru: paksa jalankan walau ada inflight/throttle
  }) {
    // Key untuk mendeteksi request beruntun yang identik
    final key =
        '${(search ?? '').trim()}|${_normalizeCategory(category) ?? ''}|$page|$perPage|$append';

    // 1) Koalesir request yang sedang jalan (hindari dobel)
    if (_inflight != null && !force) {
      return _inflight!;
    }

    // 2) Throttle ringan (2s) agar tidak dobel saat layar dibuka cepat dua kali
    final now = DateTime.now();
    if (!force &&
        _lastFetchAt != null &&
        now.difference(_lastFetchAt!) < const Duration(seconds: 2) &&
        key == _lastKey) {
      return Future.value();
    }
    _lastFetchAt = now;
    _lastKey = key;

    // 3) Simpan filter terakhir (dipakai nextPage/refresh)
    _lastSearch = search;
    _lastCategory = category;
    _lastPerPage = perPage;

    final prev = List<Product>.from(_items); // simpan data lama

    // 4) Hanya tampilkan spinner bila initial load (list masih kosong)
    final showSpinner = !append && prev.isEmpty;
    if (showSpinner) {
      _loading = true;
      _error = null;
      notifyListeners();
    } else {
      _error = null; // jangan nyalakan overlay saat sudah ada data
    }

    _inflight = () async {
      try {
        final params = <String, dynamic>{
          'per_page': perPage,
          if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
          if (_normalizeCategory(category) != null)
            'category': _normalizeCategory(category),
          if (page > 1) 'page': page,
        };

        // CATATAN:
        // - Jika baseUrl API SUDAH berakhiran /api → path cukup 'products'
        // - Jika baseUrl TANPA /api → path 'api/products'
        final res = await API.dio.get('products', queryParameters: params);

        dynamic body = res.data;
        if (body is String) {
          try {
            body = jsonDecode(body);
          } catch (_) {}
        }

        // ==== Ekstrak list & meta dalam berbagai bentuk ====
        List<dynamic> rawList = const [];
        int currentPage = page, lastPage = page;

        if (body is Map) {
          // Bentuk umum: { status, data: [...] }
          if (body['data'] is List) {
            rawList = body['data'] as List;

            // Laravel paginator langsung di root:
            if (body['current_page'] != null && body['last_page'] != null) {
              currentPage = int.tryParse('${body['current_page']}') ?? page;
              lastPage = int.tryParse('${body['last_page']}') ?? page;
            }
            // Atau di meta:
            else if (body['meta'] is Map &&
                (body['meta']['last_page'] != null)) {
              currentPage =
                  int.tryParse('${body['meta']['current_page'] ?? page}') ?? page;
              lastPage =
                  int.tryParse('${body['meta']['last_page'] ?? page}') ?? page;
            }
          }
          // Bentuk lain: { items: [...] }
          else if (body['items'] is List) {
            rawList = body['items'] as List;
          }
          // Kadang: { status: success, data: { items: [...], meta: {...} } }
          else if (body['data'] is Map) {
            final d = body['data'] as Map;
            if (d['items'] is List) rawList = d['items'] as List;
            final meta = d['meta'];
            if (meta is Map && meta['last_page'] != null) {
              currentPage =
                  int.tryParse('${meta['current_page'] ?? page}') ?? page;
              lastPage =
                  int.tryParse('${meta['last_page'] ?? page}') ?? page;
            }
          }
        } else if (body is List) {
          // Array langsung
          rawList = body;
        }

        // ==== Mapping aman -> Product ====
        final mapped = <Product>[];
        for (final e in rawList) {
          if (e is Map) {
            final m = Map<String, dynamic>.from(e as Map);
            mapped.add(
              Product(
                id: int.tryParse('${m['id']}'),
                name: m['name']?.toString(),
                price: (m['price'] is num)
                    ? (m['price'] as num).toDouble()
                    : double.tryParse('${m['price']}'),
                unit: m['unit']?.toString() ?? 'pcs',
                stock: int.tryParse('${m['stock'] ?? 0}') ?? 0,
                imageUrl: m['image_url']?.toString() ??
                    m['primary_image_url']?.toString(),
                freshnessScore: (m['suitability_percent'] is num)
                    ? (m['suitability_percent'] as num).toDouble()
                    : double.tryParse(
                        '${m['suitability_percent'] ?? m['freshness_score'] ?? 0}'),
                category: m['category']?.toString(),
                sellerId: int.tryParse('${m['seller_id'] ?? 0}'),
              ),
            );
          }
        }

        // === Update state HANYA setelah sukses ===
        if (append) {
          _items
            ..clear()
            ..addAll([...prev, ...mapped]);
        } else {
          // JANGAN kosongkan sebelum data baru siap → langsung ganti di sini
          _items
            ..clear()
            ..addAll(mapped);
        }

        _currentPage = currentPage;
        _lastPage = lastPage;
        _error = null;
      } catch (e, st) {
        debugPrint('[PRODUCTS] fetch error: $e\n$st');
        _error = e.toString();
        // Pada error, pertahankan data lama agar tidak kedip
        _items
          ..clear()
          ..addAll(prev);
      } finally {
        _loading = false;
        _inflight = null;
        notifyListeners();
      }
    }();

    return _inflight!;
  }

  // ===== Helper publik (kompat + enak dipakai dari UI) =====
  // Tidak mengosongkan list di awal; data lama tetap sampai fetch sukses.
  Future<void> fetchFirstPage({
    String? search,
    String? category,
    int perPage = 24,
    bool force = false, // opsional
  }) async {
    if (_loading && !force) return;
    await fetch(
      search: search,
      category: category,
      page: 1,
      perPage: perPage,
      append: false,
      force: force,
    );
  }

  Future<void> fetchNextPage() async {
    if (!canLoadMore || _loading) return;
    await fetch(
      search: _lastSearch,
      category: _lastCategory,
      page: _currentPage + 1,
      perPage: _lastPerPage,
      append: true,
    );
  }

  // ==== ganti method refresh (paksa page=1 tanpa hapus data dulu) ====
  Future<void> refresh({String? search, String? category}) {
    return fetch(
      search: search ?? _lastSearch,
      category: category ?? _lastCategory,
      page: 1,
      perPage: _lastPerPage,
      append: false,
      force: true, // ✅ penting: jangan koalesir/throttle saat refresh eksplisit
    );
  }
}
