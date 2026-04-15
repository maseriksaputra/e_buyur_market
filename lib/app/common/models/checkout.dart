// lib/app/common/models/checkout.dart
class CheckoutItem {
  final int productId;
  final String name;
  final String? imageUrl;
  final int qty;
  final int unitPrice; // rupiah
  final int subtotal;  // rupiah
  final String? storeName;

  CheckoutItem({
    required this.productId,
    required this.name,
    this.imageUrl,
    required this.qty,
    required this.unitPrice,
    required this.subtotal,
    this.storeName,
  });

  factory CheckoutItem.fromJson(Map<String, dynamic> j) => CheckoutItem(
        productId: _asInt(j['product_id']),
        name: (j['name'] ?? '-').toString(),
        imageUrl: j['image_url']?.toString(),
        qty: _asInt(j['qty']),
        unitPrice: _asInt(j['unit_price']),
        subtotal: _asInt(j['subtotal'] ?? j['line_total']),
        storeName: j['store_name']?.toString(),
      );
}

class AddressBrief {
  final int? id;
  final String line;
  AddressBrief({this.id, required this.line});
  factory AddressBrief.fromJson(Map<String, dynamic> j) =>
      AddressBrief(id: j['id'] as int?, line: (j['line'] ?? '').toString());
}

class PaymentOption {
  final String code;   // bri_va, bca_va, alfamart, cod
  final String label;  // BRI Virtual Account, dst
  final String? note;

  PaymentOption({required this.code, required this.label, this.note});
  factory PaymentOption.fromJson(Map<String, dynamic> j) =>
      PaymentOption(code: j['code'], label: j['label'], note: j['note']?.toString());
}

class CheckoutDraft {
  final List<CheckoutItem> items;
  final AddressBrief? address;
  final int subtotal;
  final int shippingFee;
  final int insuranceFee;
  final int discount;
  final int total;
  final List<PaymentOption> options;

  CheckoutDraft({
    required this.items,
    this.address,
    required this.subtotal,
    required this.shippingFee,
    required this.insuranceFee,
    required this.discount,
    required this.total,
    required this.options,
  });

  factory CheckoutDraft.fromJson(Map<String, dynamic> j) {
    final root = (j['checkout'] is Map) ? (j['checkout'] as Map) : j;
    final items = (root['items'] as List? ?? [])
        .whereType<Map>()
        .map((e) => CheckoutItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final addr = (root['address'] is Map)
        ? AddressBrief.fromJson(Map<String, dynamic>.from(root['address']))
        : null;
    final opts = (root['payment_options'] as List? ?? [])
        .whereType<Map>()
        .map((e) => PaymentOption.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return CheckoutDraft(
      items: items,
      address: addr,
      subtotal: _asInt(root['subtotal']),
      shippingFee: _asInt(root['shipping_fee']),
      insuranceFee: _asInt(root['insurance_fee']),
      discount: _asInt(root['discount']),
      total: _asInt(root['total']),
      options: opts,
    );
  }
}

class PaymentResult {
  final String method; // bri_va/bca_va/alfamart/cod
  final String status; // pending/success
  final String? vaNumber;
  final String? bank;
  final String? paymentCode; // alfamart
  final String? instruction; // COD teks
  final String? transactionId;
  final String? orderId;

  PaymentResult({
    required this.method,
    required this.status,
    this.vaNumber,
    this.bank,
    this.paymentCode,
    this.instruction,
    this.transactionId,
    this.orderId,
  });

  factory PaymentResult.fromJson(Map<String, dynamic> j) => PaymentResult(
        method: (j['method'] ?? '').toString(),
        status: (j['status'] ?? '').toString(),
        vaNumber: j['va_number']?.toString(),
        bank: j['bank']?.toString(),
        paymentCode: j['payment_code']?.toString(),
        instruction: j['instruction']?.toString(),
        transactionId: j['transaction_id']?.toString(),
        orderId: j['order_id']?.toString(),
      );
}

/* utils */
int _asInt(dynamic v, {int def = 0}) {
  if (v == null) return def;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return def;
    final x = int.tryParse(s) ?? double.tryParse(s.replaceAll(',', ''))?.toInt();
    return x ?? def;
  }
  return def;
}
