// lib/app/presentation/providers/cart_provider.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

// Fallback jika tidak di-inject
import 'package:e_buyur_market_flutter_5/app/core/network/api.dart';
import 'package:e_buyur_market_flutter_5/app/common/models/cart_item.dart' show CartItemModel;

class CartProvider with ChangeNotifier {
  /// Gunakan Dio yang di-inject dari luar (disarankan),
  /// atau fallback ke API.dio (baseUrl kamu sendiri).
  final Dio _dio;
  CartProvider([Dio? dio]) : _dio = dio ?? API.dio;

  // ====== loading & error ======
  bool _isLoading = false; // dipertahankan untuk kompat UI lama
  String? _error;
  bool get loading => _isLoading;
  bool get isLoading => _isLoading; // kompat lama
  String? get error => _error;

  // ====== tambahan sesuai instruksi ======
  bool _loading = false;           // guard in-flight (baru)
  DateTime? _lastFetchAt;          // debounce timestamp (baru)

  // ====== payload cart mentah dari server ======
  Map<String, dynamic>? _cart;
  Map<String, dynamic>? get cart => _cart;

  // ====== data turunan agar kompat dengan UI lama ======
  final List<CartItemModel> _items = [];
  List<CartItemModel> get items => List.unmodifiable(_items);

  int _subtotal = 0;
  int get subtotal => _subtotal;

  // ====== Selection (untuk checkout sebagian) ======
  final Set<int> selectedIds = {}; // id cart_item
  bool get hasSelection => selectedIds.isNotEmpty;

  /// Daftar item yang sedang dipilih (untuk checkout sebagian).
  /// Mengembalikan list dinamis agar tahan-banting dengan berbagai tipe model.
  List<dynamic> get selectedItems =>
      items.where((e) => selectedIds.contains(e.id)).toList();

  /// Subtotal dari item yang dipilih saja (defensif).
  int get selectedSubtotal {
    int sum = 0;
    for (final it in selectedItems) {
      sum += _lineTotalDyn(it);
    }
    return sum;
  }

  /// Backward-compat: alias lama
  int get selectedTotal => selectedSubtotal;

  // ---------------- Utils kecil ----------------
  String _normalize(String path) {
    // Hindari leading slash (bisa jadi //)
    var p = path.startsWith('/') ? path.substring(1) : path;
    // Jika baseUrl sudah berakhiran /api, dan path dimulai "api/", hapus "api/"
    final b = _dio.options.baseUrl;
    final endsWithApi = b.endsWith('/api') || b.endsWith('/api/');
    if (endsWithApi && p.startsWith('api/')) {
      p = p.substring(4);
    }
    return p;
  }

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
    if (v is String) {
      try {
        final dec = jsonDecode(v);
        if (dec is Map<String, dynamic>) return dec;
        if (dec is Map) return dec.map((k, val) => MapEntry(k.toString(), val));
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _asListMap(dynamic v) {
    if (v is List) {
      return v
          .where((e) => e is Map)
          .map((e) => Map<String, dynamic>.from(
                (e as Map).map((k, val) => MapEntry(k.toString(), val)),
              ))
          .toList();
    }
    return const [];
  }

  // ✅ Helper angka: toleran string ⇄ int, dan round bila double
  int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.round();
    return int.tryParse('$v') ?? 0;
  }

  // ✅ Normalisasi 1 item agar field angka tidak hilang bila datang sebagai string
  Map<String, dynamic> _normalizeItem(Map<String, dynamic> e) {
    return {
      'id'         : _toInt(e['id'] ?? e['item_id']),
      'product_id' : _toInt(e['product_id']),
      'name'       : (e['name'] ?? '').toString(),
      'image_url'  : e['image_url']?.toString(),
      'qty'        : _toInt(e['qty']),
      'unit'       : (e['unit'] ?? 'pcs').toString(),
      'unit_price' : _toInt(e['unit_price']),
      'line_total' : _toInt(e['line_total']),
      'seller_id'  : _toInt(e['seller_id']),
    };
  }

  void _applyCartPayload(Map<String, dynamic> data) {
    _cart = data;

    // Ambil list item untuk kompat lama
    dynamic rawList = data['items'] ?? data['cart_items'];
    if (rawList is Map && rawList['data'] is List) {
      rawList = rawList['data'];
    }
    final list = _asListMap(rawList);

    _items
      ..clear()
      ..addAll(list.map(CartItemModel.fromJson));

    _subtotal = _toInt(
      data['subtotal'] ?? data['total'] ?? data['grand_total'] ?? data['amount'],
    );

    // Sinkronkan selection
    if (selectedIds.isEmpty) {
      selectedIds.addAll(_items.map((e) => e.id));
    } else {
      final exists = _items.map((e) => e.id).toSet();
      selectedIds.removeWhere((id) => !exists.contains(id));
      if (selectedIds.isEmpty && _items.isNotEmpty) {
        selectedIds.addAll(_items.map((e) => e.id));
      }
    }
  }

  // ---------------- Selection helpers ----------------
  void setSelected(int itemId, bool value) {
    if (value) {
      selectedIds.add(itemId);
    } else {
      selectedIds.remove(itemId);
    }
    notifyListeners();
  }

  void toggleSelect(int cartItemId) {
    if (selectedIds.contains(cartItemId)) {
      selectedIds.remove(cartItemId);
    } else {
      selectedIds.add(cartItemId);
    }
    notifyListeners();
  }

  void selectAll() {
    selectedIds
      ..clear()
      ..addAll(_items.map((e) => e.id));
    notifyListeners();
  }

  void clearSelection() {
    selectedIds.clear();
    notifyListeners();
  }

  void selectOnlyByProductId(int productId) {
    selectedIds
      ..clear()
      ..addAll(_items.where((e) => e.productId == productId).map((e) => e.id));
    notifyListeners();
  }

  // ====== API baru (sesuai patch) ======

  /// GET cart penuh – versi baru dengan guard + debounce dan multi-endpoint.
  /// Catatan:
  /// - Menggunakan _dio (bisa di-inject), fallback ke API.dio dari konstruktor.
  /// - Menyokong banyak variasi payload server, tanpa melempar exception.
  Future<void> fetchCart({bool force = false}) async {
    if (_loading) return; // inflight guard
    final now = DateTime.now();
    if (!force && _lastFetchAt != null && now.difference(_lastFetchAt!) < const Duration(seconds: 10)) {
      return; // debounce ringan biar ga spam
    }

    _loading = true;
    _isLoading = true;         // tetap set agar UI lama yang mengandalkan isLoading tidak putus
    _error = null;
    notifyListeners();

    try {
      // Coba beberapa endpoint umum; ambil yang sukses duluan
      final endpoints = <String>[
        'cart/active',
        'cart',
        'buyer/cart/active',
        'buyer/cart',
      ];

      dynamic payload;
      for (final ep in endpoints) {
        try {
          final res = await _dio.get(ep);
          payload = res.data;
          if (payload != null) break;
        } catch (_) {
          // coba endpoint berikutnya
        }
      }

      // Normalisasi bentuk payload
      // Terima bentuk:
      // 1) { status:'success', data: { items: [...], total/subtotal/... } }
      // 2) { cart: { items: [...], ... } }
      // 3) { items: [...], ... }
      Map<String, dynamic>? cartJson;
      if (payload is Map<String, dynamic>) {
        if (payload['data'] is Map<String, dynamic>) {
          cartJson = (payload['data'] as Map<String, dynamic>);
        } else if (payload['cart'] is Map<String, dynamic>) {
          cartJson = (payload['cart'] as Map<String, dynamic>);
        } else {
          cartJson = payload;
        }
      }

      if (cartJson == null) {
        // Anggap kosong, jangan meledak
        _items.clear();
        _subtotal = 0;
        selectedIds.clear();
        _cart = {'cart_id': null, 'items': <dynamic>[], 'subtotal': 0};
      } else {
        // --- Ambil items dari beberapa kemungkinan key ---
        dynamic itemsRaw = cartJson['items'] ?? cartJson['cart_items'] ?? cartJson['lines'] ?? cartJson['data'];
        if (itemsRaw is Map && itemsRaw['data'] is List) {
          itemsRaw = itemsRaw['data'];
        }
        final listMaps = _asListMap(itemsRaw);
        final itemsNormalized = listMaps.map(_normalizeItem).toList();

        // --- Ambil total/subtotal ---
        final totalRaw = cartJson['subtotal'] ?? cartJson['total'] ?? cartJson['grand_total'] ?? cartJson['amount'];
        int subtotal = _toInt(totalRaw);

        // Jika subtotal tidak ada, hitung dari item
        if (subtotal == 0 && itemsNormalized.isNotEmpty) {
          subtotal = itemsNormalized.fold<int>(0, (s, e) => s + _toInt(e['line_total']));
        }

        // Update state utama (kompat UI lama)
        _cart = {
          'cart_id'  : _toInt(cartJson['cart_id'] ?? cartJson['id']),
          'items'    : itemsNormalized,
          'subtotal' : subtotal,
        };

        _items
          ..clear()
          ..addAll(itemsNormalized.map(CartItemModel.fromJson));

        _subtotal = subtotal;

        // Sinkron selection (logika sama seperti sebelumnya)
        if (selectedIds.isEmpty) {
          selectedIds.addAll(_items.map((e) => e.id));
        } else {
          final exists = _items.map((e) => e.id).toSet();
          selectedIds.removeWhere((id) => !exists.contains(id));
          if (selectedIds.isEmpty && _items.isNotEmpty) {
            selectedIds.addAll(_items.map((e) => e.id));
          }
        }
      }
    } catch (e, st) {
      _error = 'Gagal memuat keranjang';
      debugPrint('[CartProvider.fetchCart] non-fatal: $e\n$st');
      _items.clear();
      _subtotal = 0;
      selectedIds.clear();
      _cart = {'cart_id': null, 'items': <dynamic>[], 'subtotal': 0};
    } finally {
      _lastFetchAt = DateTime.now();
      _loading = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Tambah item → refresh cart.
  Future<void> addToCart(int productId, int qty, {String? unit}) async {
    await _dio.post(
      _normalize('api/buyer/cart/items'),
      data: {'product_id': productId, 'qty': qty, if (unit != null) 'unit': unit},
    );
    await fetchCart(force: true);
  }

  /// Set qty berdasarkan product ID → refresh cart.
  Future<void> setQtyByProduct(int productId, int qty, {String? unit}) async {
    await _dio.post(
      _normalize('api/buyer/cart/items/$productId'),
      data: {'qty': qty, if (unit != null) 'unit': unit},
    );
    await fetchCart(force: true);
  }

  /// Hapus item berdasarkan product ID → refresh cart.
  Future<void> removeByProduct(int productId) async {
    await _dio.delete(_normalize('api/buyer/cart/items/$productId'));
    await fetchCart(force: true);
  }

  /// Refresh ringan tanpa spinner (opsional).
  Future<void> softRefresh() async {
    try {
      // Tetap kompat: ping endpoint lama cepat.
      final res = await _dio.get(_normalize('api/buyer/cart'));
      final root = _asMap(res.data);
      if ((root['status'] ?? 'success') == 'success') {
        final data = _asMap(root['data'] ?? root);

        dynamic itemsAny =
            (data['items'] is Map && data['items']['data'] is List)
                ? data['items']['data']
                : (data['items'] ?? data['cart_items']);
        final items = _asListMap(itemsAny).map(_normalizeItem).toList();

        _cart = {
          'cart_id'  : _toInt(data['cart_id'] ?? data['id']),
          'items'    : items,
          'subtotal' : _toInt(data['subtotal'] ?? data['total'] ?? data['grand_total'] ?? data['amount']),
        };

        _items
          ..clear()
          ..addAll(items.map(CartItemModel.fromJson));

        _subtotal = _cart!['subtotal'] as int? ?? _items.fold(0, (s, it) => s + it.lineTotal);

        // sinkron selection ringan
        final exists = _items.map((e) => e.id).toSet();
        selectedIds.removeWhere((id) => !exists.contains(id));
        if (selectedIds.isEmpty && _items.isNotEmpty) {
          selectedIds.addAll(_items.map((e) => e.id));
        }
      }
    } catch (e, st) {
      debugPrint('[CartProvider.softRefresh] $e\n$st');
    } finally {
      notifyListeners();
    }
  }

  // ====== Wrapper kompatibel dengan API lama (optional) ======

  /// Lama: fetch()
  Future<void> fetch() => fetchCart();

  /// Lama: add(productId, qty, unit?)
  Future<bool> add(int productId, int qty, {String? unit}) async {
    try {
      await addToCart(productId, qty, unit: unit);
      return true;
    } catch (e, st) {
      debugPrint('[CartProvider.add] $e\n$st');
      return false;
    }
  }

  /// Lama: addAndRefresh / addToCart(productId, qty)
  Future<void> addAndRefresh({required int productId, int qty = 1}) =>
      addToCart(productId, qty);

  /// Lama: updateQty(productId, qty)
  Future<void> updateQty(int productId, int qty) => setQtyByProduct(productId, qty);

  /// Lama: setQty(productId, qty, [cartItemId])
  Future<void> setQty(int productId, int qty, [int? _]) => setQtyByProduct(productId, qty);

  /// Lama: removeByProductId(productId)
  Future<void> removeByProductId(int productId) => removeByProduct(productId);

  /// Lama: removeByCartItemId(cartItemId) — backend baru tidak pakai item id,
  /// fallback ke fetch cepat saja agar UI tetap segar.
  Future<void> removeByCartItemId(int cartItemId) async {
    debugPrint('[CartProvider] removeByCartItemId($cartItemId) not supported on new API');
    await fetchCart(force: true);
  }

  /// Lama: clearCart() — tidak tersedia di route baru, diamkan + refresh.
  Future<void> clearCart() async {
    debugPrint('[CartProvider] clearCart not supported on new API');
    await fetchCart(force: true);
  }

  /// Lama: checkout() — tangani di provider lain / service checkout.
  Future<void> checkout() async {
    debugPrint('[CartProvider] checkout handled elsewhere');
  }

  // ====== Helper defensif untuk line_total dinamis ======
  int _lineTotalDyn(dynamic it) {
    try {
      final v = (it as dynamic).lineTotal;
      if (v is num) return v.toInt();
    } catch (_) {}

    if (it is Map && it['line_total'] != null) {
      return int.tryParse('${it['line_total']}') ?? 0;
    }

    int q = 0, p = 0;
    try {
      final v = (it as dynamic).qty;
      if (v is num) q = v.toInt();
    } catch (_) {}
    if (it is Map && it['qty'] != null) {
      q = int.tryParse('${it['qty']}') ?? q;
    }

    try {
      final v = (it as dynamic).unitPrice;
      if (v is num) p = v.toInt();
    } catch (_) {}
    if (it is Map && it['unit_price'] != null) {
      p = int.tryParse('${it['unit_price']}') ?? p;
    }
    if (p == 0 && it is Map && it['price'] != null) {
      p = int.tryParse('${it['price']}') ?? p;
    }

    return q * p;
  }
}
