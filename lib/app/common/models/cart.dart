// lib/models/cart.dart
// Model keranjang yang robust terhadap variasi JSON API.
// Mendukung bentuk respons:
// 1) { "cart": { id, status, total, items: [...] } }
// 2) { "data": { id, status, total, items: [...] } }
// 3) { id, status, total, items: [...] }  (langsung)
// 4) items bisa bernama "items" atau "cart_items"
// 5) field kuantitas/harga bisa "qty"/"quantity", "unit_price"/"price", "line_total"/"subtotal" (fallback hitung otomatis)

import 'dart:convert';

double _numToDouble(dynamic v, {double fallback = 0.0}) {
  if (v == null) return fallback;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return fallback;
    final parsed = double.tryParse(s.replaceAll(',', ''));
    return parsed ?? fallback;
  }
  return fallback;
}

int _numToInt(dynamic v, {int fallback = 0}) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return fallback;
    final parsed = int.tryParse(s);
    return parsed ?? _numToDouble(s, fallback: fallback.toDouble()).toInt();
  }
  return fallback;
}

Map<String, dynamic> _ensureMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.map((k, v) => MapEntry(k.toString(), v));
  if (v is String && v.trim().isNotEmpty) {
    try {
      final dec = jsonDecode(v);
      if (dec is Map<String, dynamic>) return dec;
      if (dec is Map) {
        return dec.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {}
  }
  return <String, dynamic>{};
}

List _ensureList(dynamic v) {
  if (v is List) return v;
  return const [];
}

class CartItemModel {
  final int id;
  final int productId;
  final String? name;
  final String? imageUrl;
  final int qty;
  final double unitPrice;
  final double subtotal; // = line_total

  const CartItemModel({
    required this.id,
    required this.productId,
    required this.qty,
    required this.unitPrice,
    required this.subtotal,
    this.name,
    this.imageUrl,
  });

  factory CartItemModel.fromJson(Map<String, dynamic> j) {
    final q = j.containsKey('qty') ? j['qty'] : j['quantity'];
    final up = j.containsKey('unit_price') ? j['unit_price'] : j['price'];
    // ambil line_total dulu, fallback ke subtotal, terakhir dihitung qty*unitPrice
    final sbRaw = (j['line_total'] ?? j['subtotal']);

    final qty = _numToInt(q);
    final unitPrice = _numToDouble(up);
    final subtotal = sbRaw == null ? (qty * unitPrice) : _numToDouble(sbRaw);

    // name bisa 'name' atau 'product_name'
    final nm = (j['name'] ?? j['product_name'])?.toString();

    // image: image_url / imageUrl / image_path
    final img = (j['image_url'] ?? j['imageUrl'] ?? j['image_path'])?.toString();

    return CartItemModel(
      id: _numToInt(j['id']),
      productId: _numToInt(j['product_id'] ?? j['productId']),
      qty: qty,
      unitPrice: unitPrice,
      subtotal: subtotal,
      name: nm,
      imageUrl: img,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'product_id': productId,
        'name': name,
        'image_url': imageUrl,
        'qty': qty,
        'unit_price': unitPrice,
        'subtotal': subtotal,
      };

  CartItemModel copyWith({
    int? id,
    int? productId,
    String? name,
    String? imageUrl,
    int? qty,
    double? unitPrice,
    double? subtotal,
  }) {
    return CartItemModel(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      name: name ?? this.name,
      imageUrl: imageUrl ?? this.imageUrl,
      qty: qty ?? this.qty,
      unitPrice: unitPrice ?? this.unitPrice,
      subtotal: subtotal ?? this.subtotal,
    );
  }
}

class CartModel {
  final int id;
  final String status;
  final double total;
  final List<CartItemModel> items;

  const CartModel({
    required this.id,
    required this.status,
    required this.total,
    required this.items,
  });

  factory CartModel.empty() => const CartModel(
        id: 0,
        status: 'active',
        total: 0.0,
        items: <CartItemModel>[],
      );

  /// Ambil root cart dari berbagai bentuk respons.
  static Map<String, dynamic> _pickCartRoot(Map<String, dynamic> json) {
    if (json['cart'] is Map) return _ensureMap(json['cart']);
    if (json['data'] is Map) {
      final data = _ensureMap(json['data']);
      if (data['cart'] is Map) return _ensureMap(data['cart']);
      return data;
    }
    return json;
  }

  /// Ambil array item dari root cart, toleransi nama berbeda.
  static List _pickItems(Map<String, dynamic> root) {
    if (root['items'] is List) return root['items'] as List;
    if (root['cart_items'] is List) return root['cart_items'] as List;

    // Alternatif { data: { items: [...] } }
    final data = _ensureMap(root['data']);
    if (data['items'] is List) return data['items'] as List;

    // Alternatif { items: { data: [...] } }
    final itemsObj = _ensureMap(root['items']);
    if (itemsObj['data'] is List) return itemsObj['data'] as List;

    return const [];
  }

  factory CartModel.fromApi(dynamic json) {
    final map = _ensureMap(json);
    final root = _pickCartRoot(map);

    final id = _numToInt(root['id']);
    final status = (root['status']?.toString() ?? 'active');
    // total fallback ke subtotal jika API hanya kirim subtotal
    final total = _numToDouble(
      root['total'] ?? root['grand_total'] ?? root['amount'] ?? root['subtotal'],
    );

    final rawItems = _pickItems(root);
    final parsedItems = <CartItemModel>[];
    for (final e in rawItems) {
      if (e is Map) parsedItems.add(CartItemModel.fromJson(_ensureMap(e)));
    }

    return CartModel(
      id: id,
      status: status,
      total: total,
      items: parsedItems,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'status': status,
        'total': total,
        'items': items.map((e) => e.toJson()).toList(),
      };

  CartModel copyWith({
    int? id,
    String? status,
    double? total,
    List<CartItemModel>? items,
  }) {
    return CartModel(
      id: id ?? this.id,
      status: status ?? this.status,
      total: total ?? this.total,
      items: items ?? this.items,
    );
  }

  double get computedTotal {
    if (items.isEmpty) return 0;
    return items.fold<double>(0, (sum, it) => sum + it.subtotal);
  }

  int get totalQty {
    if (items.isEmpty) return 0;
    return items.fold<int>(0, (sum, it) => sum + it.qty);
  }

  bool get isEmpty => items.isEmpty;
}
