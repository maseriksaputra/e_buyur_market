// lib/features/cart/data/cart_repository.dart
import '../../../app/core/api_client.dart';

class CartItemDto {
  final int productId;
  final String name;
  final int price; // IDR
  final int qty;
  final String? imageUrl;

  CartItemDto({
    required this.productId,
    required this.name,
    required this.price,
    required this.qty,
    this.imageUrl,
  });

  factory CartItemDto.fromJson(Map<String, dynamic> j) => CartItemDto(
        productId: j['product_id'] is int
            ? j['product_id'] as int
            : int.parse('${j['product_id']}'),
        name: j['product_name'] ?? j['name'] ?? '',
        price: (j['price'] is num)
            ? (j['price'] as num).toInt()
            : int.parse(j['price'].toString()),
        qty: (j['qty'] is num)
            ? (j['qty'] as num).toInt()
            : int.parse(j['qty'].toString()),
        imageUrl: j['image_url'],
      );
}

class CartDto {
  final List<CartItemDto> items;
  final int subtotal;
  CartDto(this.items, this.subtotal);
}

class CartRepository {
  CartRepository(this.api);
  final ApiClient api;

  // NOTE:
  // Jika baseUrl kamu SUDAH berakhiran `/api`
  //   (contoh: https://api.ebuyurmarket.com/api),
  // gunakan path tanpa prefix `/api` di bawah.
  // Jika baseUrl TANPA `/api`, tambahkan `/api` di depan semua path.

  Future<CartDto> fetch() async {
    final res = await api.get('/buyer/cart'); // ← sesuaikan jika perlu
    final d = res['data'] ?? res;
    final items =
        (d['items'] as List).map((e) => CartItemDto.fromJson(e)).toList();
    final subtotal = (d['subtotal'] ?? 0) is num
        ? (d['subtotal'] as num).toInt()
        : 0;
    return CartDto(items, subtotal);
  }

  Future<void> add({required int productId, required int qty}) async {
    await api.post('/buyer/cart/items', {
      'product_id': productId,
      'qty': qty,
    });
  }

  Future<void> remove(int productId) async {
    await api.delete('/buyer/cart/items/$productId');
  }

  Future<void> changeQty(int productId, int qty) async {
    await api.post('/buyer/cart/items/$productId', {'qty': qty});
  }
}
