import 'package:dio/dio.dart';

typedef JSON = Map<String, dynamic>;

class CheckoutRepository {
  final Dio dio;
  CheckoutRepository(this.dio);

  /// Membuat order per seller dari keranjang aktif.
  /// Endpoint: POST /buyer/checkout (lihat CheckoutController@checkout)
  ///
  /// Return: daftar {order_id, code, amount}
  Future<List<JSON>> checkout({
    required String recipientName,
    required String recipientPhone,
    required JSON shippingAddressJson,
    required List<JSON> shippingChoices, // per seller: {seller_id, service_code, provider, fee, quote_id}
    CancelToken? cancelToken,
  }) async {
    try {
      final res = await dio.post(
        'buyer/checkout',
        data: {
          'recipient_name': recipientName,
          'recipient_phone': recipientPhone,
          'shipping_address': shippingAddressJson,
          'shipping_choices': shippingChoices,
        },
        cancelToken: cancelToken,
      );

      final data = res.data;
      if (data is Map && data['orders'] is List) {
        return List<JSON>.from((data['orders'] as List).map((e) => (e as Map).cast<String, dynamic>()));
      }
      return <JSON>[];
    } on DioException catch (e) {
      final msg = e.response?.data is Map && (e.response!.data['message']?.toString().isNotEmpty ?? false)
          ? e.response!.data['message'].toString()
          : (e.message ?? 'Checkout gagal');
      throw Exception(msg);
    }
  }
}
