// lib/app/common/models/cart_item.dart
//
// Model keranjang tunggal (hindari duplikasi).
// Robust terhadap variasi kunci JSON dari backend:
// - items vs cart_items
// - qty vs quantity
// - unit_price vs price
// - line_total vs subtotal (fallback hitung otomatis bila tidak ada)
// - image_url vs imageUrl vs image_path
// - name vs product_name
//
// Perubahan utama:
// - CartItemModel memakai field `lineTotal` (bukan `subtotal`).
// - Tetap sediakan getter `subtotal` => `lineTotal` untuk kompatibilitas lama.
// - CartModel menerima total dari: total | grand_total | amount | subtotal.

import 'package:flutter/foundation.dart';

int _toInt(dynamic v, {int def = 0}) {
  if (v == null) return def;
  if (v is int) return v;
  if (v is double) return v.round();
  if (v is num) return v.toInt();
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return def;
    final i = int.tryParse(s);
    if (i != null) return i;
    final d = double.tryParse(s.replaceAll(',', ''));
    if (d != null) return d.round();
  }
  return def;
}

int? _toIntOrNull(dynamic v) {
  if (v == null) return null;
  final i = _toInt(v, def: 0);
  return i == 0 ? null : i;
}

String? _toStrOrNull(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

Map<String, dynamic> _asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) {
    return Map<String, dynamic>.from(
      v.map((k, val) => MapEntry(k.toString(), val)),
    );
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

class CartItemModel {
  final int id;           // id row keranjang
  final int productId;
  final String name;
  final int quantity;     // qty
  final String? unit;
  final int unitPrice;    // rupiah
  final int lineTotal;    // rupiah
  final String? imageUrl; // URL gambar produk
  final int? sellerId;

  const CartItemModel({
    required this.id,
    required this.productId,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.lineTotal,
    required this.imageUrl,
    this.sellerId,
  });

  /// Robust parser: menerima variasi kunci dari server.
  factory CartItemModel.fromJson(Map<String, dynamic> j) {
    final qty = _toInt(j.containsKey('qty') ? j['qty'] : j['quantity']);
    final unitPrice = _toInt(j.containsKey('unit_price') ? j['unit_price'] : j['price']);

    // line_total bisa 'line_total' | 'lineTotal' | 'subtotal' | (qty * unitPrice)
    final ltRaw = j['line_total'] ?? j['lineTotal'] ?? j['subtotal'];
    final lineTotal = ltRaw != null ? _toInt(ltRaw) : (qty * unitPrice);

    // name bisa 'name' atau 'product_name'
    final nm = _toStrOrNull(j['name'] ?? j['product_name']) ?? '-';

    // image bisa 'image_url' | 'imageUrl' | 'image_path' | 'image'
    final img = _toStrOrNull(j['image_url'] ?? j['imageUrl'] ?? j['image_path'] ?? j['image']);

    return CartItemModel(
      id: _toInt(j['id']),
      productId: _toInt(j['product_id'] ?? j['productId']),
      name: nm.isEmpty ? '-' : nm,
      quantity: qty,
      unit: _toStrOrNull(j['unit']),
      unitPrice: unitPrice,
      lineTotal: lineTotal,
      imageUrl: img,
      sellerId: _toIntOrNull(j['seller_id']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'product_id': productId,
        'name': name,
        // sertakan keduanya untuk kompatibilitas request
        'qty': quantity,
        'quantity': quantity,
        'unit': unit,
        'unit_price': unitPrice,
        'line_total': lineTotal,
        'image_url': imageUrl,
        'seller_id': sellerId,
      };

  // Back-compat: beberapa kode lama masih membaca `subtotal`
  int get subtotal => lineTotal;

  CartItemModel copyWith({
    int? id,
    int? productId,
    String? name,
    int? quantity,
    String? unit,
    int? unitPrice,
    int? lineTotal,
    String? imageUrl,
    int? sellerId,
  }) {
    return CartItemModel(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      unitPrice: unitPrice ?? this.unitPrice,
      lineTotal: lineTotal ?? this.lineTotal,
      imageUrl: imageUrl ?? this.imageUrl,
      sellerId: sellerId ?? this.sellerId,
    );
  }
}

class CartModel {
  final int id;
  final String status;
  final int total; // rupiah
  final List<CartItemModel> items;

  const CartModel({
    required this.id,
    required this.status,
    required this.total,
    required this.items,
  });

  /// Terima bentuk:
  /// {id,status,total,items:[]}
  /// {cart:{...}}
  /// {data:{...}}
  /// items boleh berada di 'items' atau 'cart_items'
  factory CartModel.fromJson(Map<String, dynamic> json) {
    final root = _pickCartRoot(json);
    final itemsRaw = _pickItems(root);

    return CartModel(
      id: _toInt(root['id']),
      status: (root['status'] ?? 'active').toString(),
      // Ambil total dari beberapa kemungkinan kunci:
      // total | grand_total | amount | subtotal
      total: _toInt(
        root['total'] ??
            root['grand_total'] ??
            root['amount'] ??
            root['subtotal'],
      ),
      items: itemsRaw
          .map<CartItemModel>(
            (e) => CartItemModel.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'status': status,
        'total': total,
        'items': items.map((e) => e.toJson()).toList(),
      };

  bool get isEmpty => items.isEmpty;
  int get totalQty => items.fold(0, (sum, it) => sum + it.quantity);
  int get computedTotal => items.fold(0, (sum, it) => sum + it.lineTotal);
}

/* =======================
 * Utilities (private)
 * ======================= */

Map<String, dynamic> _pickCartRoot(Map<String, dynamic> json) {
  if (json['cart'] is Map) return _asMap(json['cart']);
  if (json['data'] is Map) {
    final data = _asMap(json['data']);
    if (data['cart'] is Map) return _asMap(data['cart']);
    return data;
  }
  return json;
}

List<Map<String, dynamic>> _pickItems(Map<String, dynamic> root) {
  if (root['items'] is List) return _asListMap(root['items']);
  if (root['cart_items'] is List) return _asListMap(root['cart_items']);

  // Alternatif pagination: { items: { data: [...] } }
  if (root['items'] is Map && (root['items'] as Map)['data'] is List) {
    return _asListMap((root['items'] as Map)['data']);
  }

  // Alternatif nested: { data: { items: [...] } }
  if (root['data'] is Map && (root['data'] as Map)['items'] is List) {
    return _asListMap((root['data'] as Map)['items']);
  }

  return const [];
}
