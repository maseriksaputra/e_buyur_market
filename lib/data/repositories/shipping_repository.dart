import 'package:dio/dio.dart';

typedef JSON = Map<String, dynamic>;

class ShippingRepository {
  final Dio dio;
  ShippingRepository(this.dio);

  /// Ambil tarif pengiriman dari Biteship proxy server:
  /// Server kamu meneruskan ke /rates/couriers.
  ///
  /// Hasil Biteship biasa punya field `pricing` (list).
  /// Kita normalisasi: mengembalikan List<Map<String,dynamic>>.
  Future<List<JSON>> getRates({
    required JSON origin,
    required JSON destination,
    required List<JSON> items,
    String couriers = 'grabexpress',
    CancelToken? cancelToken,
  }) async {
    try {
      final res = await dio.post(
        'shipping/quote',
        data: {
          'origin': origin,
          'destination': destination,
          'couriers': couriers,
          'items': items,
        },
        cancelToken: cancelToken,
      );

      final data = res.data;
      if (data is Map<String, dynamic>) {
        final pricing = data['pricing'] ?? data['couriers'] ?? data['data'] ?? data['results'] ?? [];
        if (pricing is List) {
          return pricing.map<JSON>((e) => (e as Map).cast<String, dynamic>()).toList();
        }
      }
      // fallback
      return <JSON>[];
    } on DioException catch (e) {
      final msg = e.response?.data is Map && (e.response!.data['message']?.toString().isNotEmpty ?? false)
          ? e.response!.data['message'].toString()
          : (e.message ?? 'Gagal mengambil tarif pengiriman');
      throw Exception(msg);
    }
  }

  /// Membuat shipment/order di Biteship melalui server kamu
  Future<JSON> createShipment(JSON payload, {CancelToken? cancelToken}) async {
    try {
      final res = await dio.post('shipping/order', data: payload, cancelToken: cancelToken);
      return (res.data is Map<String, dynamic>) ? res.data as JSON : <String, dynamic>{'ok': true};
    } on DioException catch (e) {
      final msg = e.response?.data is Map && (e.response!.data['message']?.toString().isNotEmpty ?? false)
          ? e.response!.data['message'].toString()
          : (e.message ?? 'Gagal membuat shipment');
      throw Exception(msg);
    }
  }
}
