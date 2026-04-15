// lib/app/features/providers/seller_products_provider.dart
import 'package:flutter/foundation.dart';

import '../../common/models/product_model.dart';
import '../../core/services/product_api_service.dart'
    show ProductApiService, InventorySummary, SellerProductFilter;

class SellerProductsProvider extends ChangeNotifier {
  final ProductApiService api;
  SellerProductsProvider(this.api);

  InventorySummary? summary;
  List<Product> items = [];
  bool isLoading = false;
  Map<String, dynamic>? meta;

  /// Ambil ringkasan inventori langsung sebagai objek DTO dari service
  Future<void> loadSummary({bool onlyActive = false}) async {
    summary = await api.getSellerInventorySummary(onlyActive: onlyActive);
    notifyListeners();
  }

  /// Ambil list produk + meta paginate (compatible dengan service.getSellerProducts)
  Future<void> loadProducts({SellerProductFilter? filter}) async {
    isLoading = true;
    notifyListeners();
    try {
      final res = await api.getSellerProducts(filter: filter);
      items = List<Product>.from(res['items'] as List<Product>);
      meta = res['meta'] as Map<String, dynamic>?;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<Product> loadDetail(int id) => api.getSellerProductDetail(id);

  Future<void> update({
    required int id,
    String? name,
    double? price,
    int? stock,
    int? categoryId,
    String? description,
    double? freshnessScore,
    List<String>? nutrition,
    bool? isActive,
    int? suitabilityPercent, // NEW
  }) async {
    await api.updateSellerProduct(
      id: id,
      name: name,
      price: price,
      stock: stock,
      categoryId: categoryId,
      description: description,
      freshnessScore: freshnessScore,
      nutrition: nutrition,
      isActive: isActive,
      suitabilityPercent: suitabilityPercent, // NEW
    );
    await Future.wait([loadProducts(), loadSummary()]);
  }

  Future<void> remove(int id) async {
    await api.deleteSellerProduct(id);
    items.removeWhere((e) => e.id == id);
    await loadSummary();
    notifyListeners();
  }
}
