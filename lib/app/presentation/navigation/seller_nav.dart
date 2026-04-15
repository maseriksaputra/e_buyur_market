import 'package:flutter/material.dart';
import '../../core/routes.dart';

/// Utility supaya semua navigasi seller konsisten dan pakai root navigator.
class SellerNav {
  /// product boleh Map<String, dynamic> atau model yang punya properti mirip.
  static Map<String, dynamic> _toMap(dynamic p) {
    if (p is Map<String, dynamic>) return p;

    // Jika kamu punya model Product, mapping aman di bawah ini.
    // Abaikan field yang tidak ada di modelmu.
    return <String, dynamic>{
      'id'        : (p.id as num?)?.toInt(),
      'name'      : p.name?.toString(),
      'price'     : (p.price is num) ? (p.price as num).toDouble()
                    : double.tryParse('${p.price}') ?? 0,
      'stock'     : (p.stock is num) ? (p.stock as num).toInt()
                    : int.tryParse('${p.stock}') ?? 0,
      'image_url' : p.imageUrl ?? p.image_url ?? p.imageURL ?? null,
      'category'  : p.category?.toString(),
      'description': p.description?.toString(),
      'freshness_score': (p.freshnessScore ?? p.freshness_score) is num
          ? ((p.freshnessScore ?? p.freshness_score) as num).toDouble()
          : null,
    };
  }

  static Future<void> openDetail(BuildContext context, dynamic product) {
    final m = _toMap(product);
    final id = (m['id'] as num?)?.toInt();
    return Navigator.of(context, rootNavigator: true).pushNamed(
      AppRoutes.sellerProductDetail,
      arguments: {'id': id, 'product': m, 'source': 'seller'},
    );
  }

  static Future<void> openEdit(BuildContext context, dynamic product,
      {bool disableImage = true}) {
    final m = _toMap(product);
    final id = (m['id'] as num?)?.toInt();
    return Navigator.of(context, rootNavigator: true).pushNamed(
      AppRoutes.sellerEditProduct,
      arguments: {'id': id, 'product': m, 'disableImage': disableImage},
    );
  }
}
