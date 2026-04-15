import 'package:flutter/foundation.dart';
import '../data/cart_repository.dart';

class CartState {
  final bool loading;
  final List<CartItemDto> items;
  final int subtotal;
  const CartState({this.loading=false, this.items=const [], this.subtotal=0});
  CartState copyWith({bool? loading, List<CartItemDto>? items, int? subtotal}) =>
      CartState(loading: loading ?? this.loading, items: items ?? this.items, subtotal: subtotal ?? this.subtotal);
}

class CartController extends ChangeNotifier {
  CartController(this.repo);
  final CartRepository repo;
  CartState state = const CartState(loading: true);

  Future<void> refresh() async {
    state = state.copyWith(loading: true); notifyListeners();
    final c = await repo.fetch();
    state = CartState(loading: false, items: c.items, subtotal: c.subtotal);
    notifyListeners();
  }

  Future<void> add(int productId, int qty) async {
    await repo.add(productId: productId, qty: qty);
    await refresh(); // pastikan UI terbarui
  }
}
