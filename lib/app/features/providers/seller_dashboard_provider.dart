import 'package:flutter/material.dart';
import '../../core/services/product_api_service.dart';
import '../../common/models/product_model.dart'; // ✅ path model yang benar

class SellerDashboardProvider extends ChangeNotifier {
  SellerDashboardProvider(this.api);
  final ProductApiService api;

  bool loading = false;
  int inventoryValue = 0;
  int productsCount  = 0;
  int stockUnits     = 0;
  int avgFreshness   = 0;
  List<Product> latest = const [];

  Future<void> load() async {
    loading = true;
    notifyListeners();
    try {
      final m = await api.fetchSellerDashboard();
      inventoryValue = (m['inventory_value'] as int?) ?? 0;
      productsCount  = (m['products_count']  as int?) ?? 0;
      stockUnits     = (m['stock_units']     as int?) ?? 0;
      avgFreshness   = (m['avg_freshness']   as int?) ?? 0;
      latest         = (m['latest'] as List<Product>);
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
