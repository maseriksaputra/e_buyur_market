// lib/common/models/order_model.dart (Diperbarui)
class Order {
  final String id;
  final String sellerId; // Atau buyerId, sesuaikan dengan logika Anda
  final double totalAmount;
  final String status;
  final String customerName;
  final String courier;
  final DateTime createdAt;
  final String shippingAddress; // <-- BARU
  final String paymentMethod; // <-- BARU

  Order({
    required this.id,
    required this.sellerId,
    required this.totalAmount,
    required this.status,
    required this.customerName,
    required this.courier,
    required this.createdAt,
    required this.shippingAddress, // <-- BARU
    required this.paymentMethod, // <-- BARU
  });
}
