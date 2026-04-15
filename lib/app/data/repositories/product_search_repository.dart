import 'package:e_buyur_market_flutter_5/app/core/network/api.dart';

class ProductSearchRepository {
  static Future<Map<String, dynamic>> search({
    String? q,
    String? category,
    double? minPrice,
    double? maxPrice,
    int page = 1,
  }) async {
    final res = await API.get(
      'products/search',
      query: {
        if (q != null && q.trim().isNotEmpty) 'q': q,
        if (category != null && category.isNotEmpty) 'category': category,
        if (minPrice != null) 'min_price': minPrice,
        if (maxPrice != null) 'max_price': maxPrice,
        'page': page,
      },
    );
    return Map<String, dynamic>.from(res.data);
  }
}
