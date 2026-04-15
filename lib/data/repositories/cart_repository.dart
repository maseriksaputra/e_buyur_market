import 'package:dio/dio.dart';

typedef JSON = Map<String, dynamic>;

class CartRepository {
  final Dio dio;
  CartRepository(this.dio);

  /// Ambil keranjang aktif milik user yang login
  Future<JSON> fetchCart({CancelToken? cancelToken}) async {
    try {
      final res = await dio.get('buyer/cart', cancelToken: cancelToken);
      return _asMap(res.data);
    } on DioException catch (e) {
      throw Exception(_err(e, 'Gagal memuat keranjang'));
    }
  }

  /// Tambah / update item ke keranjang
  Future<void> addItem(int productId, int qty, {CancelToken? cancelToken}) async {
    try {
      await dio.post(
        'buyer/cart/items',
        data: {'product_id': productId, 'qty': qty},
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw Exception(_err(e, 'Gagal menambah item'));
    }
  }

  /// Ubah kuantitas item
  Future<void> updateQty(int itemId, int qty, {CancelToken? cancelToken}) async {
    try {
      await dio.patch(
        '/buyer/cart/items/$itemId',
        data: {'qty': qty},
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw Exception(_err(e, 'Gagal memperbarui kuantitas'));
    }
  }

  /// Hapus item dari keranjang
  Future<void> removeItem(int itemId, {CancelToken? cancelToken}) async {
    try {
      await dio.delete('buyer/cart/items/$itemId', cancelToken: cancelToken);
    } on DioException catch (e) {
      throw Exception(_err(e, 'Gagal menghapus item'));
    }
  }

  /// Bersihkan seluruh keranjang
  Future<void> clear({CancelToken? cancelToken}) async {
    try {
      await dio.post('buyer/cart/clear', cancelToken: cancelToken);
    } on DioException catch (e) {
      throw Exception(_err(e, 'Gagal mengosongkan keranjang'));
    }
  }

  // ---- helpers ----
  JSON _asMap(dynamic d) => (d is Map<String, dynamic>) ? d : <String, dynamic>{};

  String _err(DioException e, String fallback) {
    final msg = e.response?.data is Map && (e.response!.data['message']?.toString().isNotEmpty ?? false)
        ? e.response!.data['message'].toString()
        : e.message ?? fallback;
    return msg;
  }
}
