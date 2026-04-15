import 'package:dio/dio.dart';

class PaymentRepository {
  final Dio dio;
  PaymentRepository(this.dio);

  /// Ambil SNAP {token, redirect_url} untuk suatu order buyer.
  /// Route server: POST /buyer/pay/{order}
  Future<Map<String, String?>> getSnapRedirect(int orderId, {CancelToken? cancelToken}) async {
    try {
      final res = await dio.post('buyer/pay/$orderId', cancelToken: cancelToken);
      final data = res.data is Map ? res.data as Map : const {};
      return {
        'token': data['token'] as String?,
        'redirect_url': data['redirect_url'] as String?,
      };
    } on DioException catch (e) {
      final msg = e.response?.data is Map && (e.response!.data['message']?.toString().isNotEmpty ?? false)
          ? e.response!.data['message'].toString()
          : (e.message ?? 'Gagal mengambil SNAP token');
      throw Exception(msg);
    }
  }
}
