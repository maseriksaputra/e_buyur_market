// lib/app/routes/checkout_args.dart
import 'package:flutter/foundation.dart';

@immutable
class CheckoutArgs {
  final List<int>? cartItemIds; // mode checkout dari item keranjang tertentu
  final int? productId;         // mode direct buy (opsional)
  final int? qty;

  const CheckoutArgs.cart({required this.cartItemIds})
      : productId = null,
        qty = null;

  const CheckoutArgs.direct({required this.productId, this.qty = 1})
      : cartItemIds = null;
}
