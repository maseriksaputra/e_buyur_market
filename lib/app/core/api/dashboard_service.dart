import 'dart:convert';
import 'package:dio/dio.dart';

class DashboardData {
  final double stockValueTotal;
  final int productCount;
  final int stockUnits;
  final double freshnessAvg;
  final List<Map<String, dynamic>> myProducts;
  final String? error;
  const DashboardData({
    required this.stockValueTotal,
    required this.productCount,
    required this.stockUnits,
    required this.freshnessAvg,
    required this.myProducts,
    this.error,
  });
  factory DashboardData.empty({String? error}) => DashboardData(
    stockValueTotal: 0, productCount: 0, stockUnits: 0, freshnessAvg: 0,
    myProducts: const [], error: error,
  );
}

class DashboardService {
  final Dio dio;
  DashboardService(this.dio);

  /// Pastikan dio sudah punya baseUrl & Authorization di tempat lain (interceptor)
  Future<DashboardData> fetchSellerDashboard() async {
    try {
      final res = await dio.get('seller/dashboard');
      final root = res.data is String ? jsonDecode(res.data) : (res.data as Map);
      final ok = (root['status'] == 'success') || (root['ok'] == true);
      final data = (root['data'] ?? {}) as Map;
      final stats = (data['stats'] ?? {}) as Map;

      if (!ok) {
        return DashboardData.empty(error: (root['error']?['message'] ?? 'Gagal memuat').toString());
      }

      return DashboardData(
        stockValueTotal: ((stats['stock_value_total'] ?? 0) as num).toDouble(),
        productCount: (stats['product_count'] ?? 0) as int,
        stockUnits: (stats['stock_units'] ?? 0) as int,
        freshnessAvg: ((stats['freshness_avg'] ?? 0) as num).toDouble(),
        myProducts: List<Map<String, dynamic>>.from(data['my_products'] ?? const []),
      );
    } catch (e) {
      return DashboardData.empty(error: 'Tidak dapat memuat dashboard');
    }
  }
}
