// lib/app/data/repositories/review_repository.dart
import 'package:e_buyur_market_flutter_5/app/core/network/api.dart';

class ReviewRepository {
  static Future<Map<String, dynamic>> getByProduct(int productId, {int page = 1}) async {
    final res = await API.get('products/$productId/reviews', query: {'page': page});
    return Map<String, dynamic>.from(res.data);
  }

  static Future<Map<String, dynamic>> add({
    required int productId,
    required int rating, // 1..5
    String? comment,
  }) async {
    final res = await API.postJson('reviews', data: {
      'product_id': productId,
      'rating': rating,
      if (comment != null && comment.trim().isNotEmpty) 'comment': comment,
    });
    return Map<String, dynamic>.from(res.data);
  }
}
