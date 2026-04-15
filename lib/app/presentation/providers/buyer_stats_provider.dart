import 'package:flutter/foundation.dart';
import '../../core/services/buyer_stats_service.dart';

class BuyerStatsProvider extends ChangeNotifier {
  bool isLoading = false;
  String? error;

  int cartCount = 0;
  int favoriteCount = 0;
  int ordersCount = 0;

  Future<void> load({required String? token}) async {
    isLoading = true;
    error = null;
    notifyListeners();

    try {
      final data = await BuyerStatsService.fetchStats(token: token);
      cartCount = (data['cart_count'] ?? 0) as int;
      favoriteCount = (data['favorite_count'] ?? 0) as int;
      ordersCount = (data['orders_count'] ?? 0) as int;
    } on UnauthorizedException {
      error = 'unauthorized';
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void reset() {
    cartCount = 0;
    favoriteCount = 0;
    ordersCount = 0;
    error = null;
    isLoading = false;
    notifyListeners();
  }
}
