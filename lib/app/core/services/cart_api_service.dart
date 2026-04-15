// lib/app/core/services/cart_api_service.dart
import 'package:dio/dio.dart';
import 'package:e_buyur_market_flutter_5/app/core/network/api.dart';

class CartApiService {
  const CartApiService();

  /// Ambil keranjang buyer (payload cart penuh)
  Future<Map<String, dynamic>> getCart() async {
    final Response res = await API.dio.get('buyer/cart');
    return API.decodeBody(res.data) as Map<String, dynamic>;
  }

  /// Tambah item ke keranjang buyer
  /// Server mengembalikan payload cart penuh
  Future<Map<String, dynamic>> addItem({
    required int productId,
    int qty = 1,
  }) async {
    final Response res = await API.dio.post(
      'buyer/cart/items',
      data: {
        'product_id': productId,
        'qty': qty,
      },
    );
    return API.decodeBody(res.data) as Map<String, dynamic>;
  }

  /// Set/update kuantitas item di keranjang buyer
  Future<Map<String, dynamic>> setQty({
    required int itemId,
    required int qty,
  }) async {
    final Response res = await API.dio.put(
      'buyer/cart/items/$itemId',
      data: {'qty': qty},
    );
    return API.decodeBody(res.data) as Map<String, dynamic>;
  }
}
