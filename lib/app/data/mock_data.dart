// lib/data/mock_data.dart (Diperbarui)
import '../common/models/order_model.dart';

final List<Order> mockOrders = [
  Order(
    id: 'TRX-001',
    sellerId: 'user-123',
    totalAmount: 65000,
    status: 'delivered',
    customerName: 'Budi Santoso',
    courier: 'JNE Regular',
    createdAt: DateTime.parse('2024-01-15T10:00:00Z'),
    shippingAddress: 'Jl. Merdeka No. 123, Jakarta', // <-- BARU
    paymentMethod: 'Transfer Bank', // <-- BARU
  ),
  Order(
    id: 'TRX-002',
    sellerId: 'user-123',
    totalAmount: 45000,
    status: 'shipped',
    customerName: 'Citra Lestari',
    courier: 'GoSend',
    createdAt: DateTime.parse('2024-01-14T15:30:00Z'),
    shippingAddress: 'Jl. Sudirman Kav. 5, Bandung',
    paymentMethod: 'E-Wallet',
  ),
  Order(
    id: 'TRX-003',
    sellerId: 'user-123',
    totalAmount: 32000,
    status: 'pending',
    customerName: 'Agus Wijaya',
    courier: 'Sicepat',
    createdAt: DateTime.parse('2024-01-13T09:15:00Z'),
    shippingAddress: 'Jl. Pahlawan No. 10, Surabaya',
    paymentMethod: 'COD',
  ),
  Order(
    id: 'TRX-004',
    sellerId: 'user-123',
    totalAmount: 112000,
    status: 'confirmed', // <-- Status baru untuk contoh
    customerName: 'Dewi Anggraini',
    courier: 'Anteraja',
    createdAt: DateTime.parse('2024-01-16T11:00:00Z'),
    shippingAddress: 'Jl. Gatot Subroto No. 88, Medan',
    paymentMethod: 'Virtual Account',
  ),
  Order(
    id: 'TRX-005',
    sellerId: 'user-123',
    totalAmount: 25000,
    status: 'cancelled',
    customerName: 'Eko Prasetyo',
    courier: 'J&T',
    createdAt: DateTime.parse('2024-01-12T14:20:00Z'),
    shippingAddress: 'Jl. Diponegoro No. 21, Semarang',
    paymentMethod: 'E-Wallet',
  ),
];
