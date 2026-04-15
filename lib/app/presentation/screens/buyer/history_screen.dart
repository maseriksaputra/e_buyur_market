// lib/app/presentation/screens/buyer/history_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// ✅ Import path AppColors yang benar
import 'package:e_buyur_market_flutter_5/app/core/theme/app_colors.dart';

// ✅ Import PrimaryAppBar
import 'package:e_buyur_market_flutter_5/app/common/widgets/primary_app_bar.dart';

// ==================== Order Model (mock) ====================
class Order {
  final String id;
  final String? storeName;
  final String customerName;
  final DateTime orderDate;
  final double totalAmount;
  final String status;
  final List<OrderItem> items;
  final String? trackingNumber;
  final String courier;
  final String paymentMethod;
  final double shippingCost;

  Order({
    required this.id,
    this.storeName,
    required this.customerName,
    required this.orderDate,
    required this.totalAmount,
    required this.status,
    required this.items,
    this.trackingNumber,
    required this.courier,
    required this.paymentMethod,
    required this.shippingCost,
  });
}

class OrderItem {
  final String productId;
  final String productName;
  final int quantity;
  final double price;
  final String? imageUrl;

  OrderItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.price,
    this.imageUrl,
  });
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({Key? key}) : super(key: key);

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _activeTab = 'all';

  // Mock data for orders
  final List<Order> mockOrders = [
    Order(
      id: 'ORD001',
      storeName: 'Toko Sayur Segar',
      customerName: 'John Doe',
      orderDate: DateTime.now().subtract(const Duration(days: 1)),
      totalAmount: 85000,
      status: 'delivered',
      courier: 'JNE Express',
      paymentMethod: 'Transfer Bank',
      shippingCost: 10000,
      items: [
        OrderItem(
            productId: '1',
            productName: 'Brokoli Segar',
            quantity: 2,
            price: 15000),
        OrderItem(
            productId: '2',
            productName: 'Tomat Merah',
            quantity: 3,
            price: 12000),
      ],
    ),
    Order(
      id: 'ORD002',
      storeName: 'Fresh Fruit Store',
      customerName: 'Jane Smith',
      orderDate: DateTime.now().subtract(const Duration(days: 2)),
      totalAmount: 125000,
      status: 'shipped',
      trackingNumber: 'JNE123456789',
      courier: 'JNE Regular',
      paymentMethod: 'OVO',
      shippingCost: 15000,
      items: [
        OrderItem(
            productId: '6',
            productName: 'Apel Fuji Import',
            quantity: 2,
            price: 35000),
        OrderItem(
            productId: '7',
            productName: 'Jeruk Medan',
            quantity: 3,
            price: 18000),
      ],
    ),
    Order(
      id: 'ORD003',
      storeName: 'Pasar Tradisional',
      customerName: 'Bob Wilson',
      orderDate: DateTime.now().subtract(const Duration(days: 3)),
      totalAmount: 45000,
      status: 'confirmed',
      courier: 'GoSend',
      paymentMethod: 'GoPay',
      shippingCost: 8000,
      items: [
        OrderItem(
            productId: '3',
            productName: 'Wortel Orange',
            quantity: 2,
            price: 10000),
        OrderItem(
            productId: '4', productName: 'Kentang', quantity: 3, price: 8000),
      ],
    ),
    Order(
      id: 'ORD004',
      storeName: 'Warung Buah',
      customerName: 'Alice Brown',
      orderDate: DateTime.now().subtract(const Duration(days: 5)),
      totalAmount: 30000,
      status: 'pending',
      courier: 'Grab Express',
      paymentMethod: 'COD',
      shippingCost: 12000,
      items: [
        OrderItem(
            productId: '8',
            productName: 'Pisang Raja',
            quantity: 2,
            price: 15000),
      ],
    ),
    Order(
      id: 'ORD005',
      storeName: 'Toko Diskon',
      customerName: 'Charlie Davis',
      orderDate: DateTime.now().subtract(const Duration(days: 7)),
      totalAmount: 15000,
      status: 'cancelled',
      courier: 'SiCepat',
      paymentMethod: 'Transfer Bank',
      shippingCost: 10000,
      items: [
        OrderItem(
            productId: '5',
            productName: 'Bayam Bundle',
            quantity: 3,
            price: 5000),
      ],
    ),
  ];

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'confirmed':
        return Colors.blue;
      case 'processing':
        return Colors.indigo;
      case 'shipped':
        return Colors.purple;
      case 'delivered':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'Menunggu Konfirmasi';
      case 'confirmed':
        return 'Dikonfirmasi';
      case 'processing':
        return 'Diproses';
      case 'shipped':
        return 'Dikirim';
      case 'delivered':
        return 'Selesai';
      case 'cancelled':
        return 'Dibatalkan';
      default:
        return status;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Icons.access_time;
      case 'confirmed':
        return Icons.check_circle_outline;
      case 'processing':
        return Icons.inventory_2_outlined;
      case 'shipped':
        return Icons.local_shipping_outlined;
      case 'delivered':
        return Icons.check_circle;
      case 'cancelled':
        return Icons.cancel_outlined;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Order> filteredOrders = mockOrders.where((order) {
      if (_activeTab == 'all') return true;
      if (_activeTab == 'pending') {
        return ['pending', 'confirmed', 'processing', 'shipped']
            .contains(order.status);
      }
      if (_activeTab == 'completed') {
        return ['delivered', 'cancelled'].contains(order.status);
      }
      return false;
    }).toList();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      // ✅ Pakai PrimaryAppBar
      appBar: const PrimaryAppBar(title: 'Riwayat Pesanan'),
      body: Column(
        children: [
          // Tab Bar
          Container(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  _buildTabButton('all', 'Semua', mockOrders.length),
                  const SizedBox(width: 12),
                  _buildTabButton(
                    'pending',
                    'Diproses',
                    mockOrders
                        .where((o) => [
                              'pending',
                              'confirmed',
                              'processing',
                              'shipped'
                            ].contains(o.status))
                        .length,
                  ),
                  const SizedBox(width: 12),
                  _buildTabButton(
                    'completed',
                    'Selesai',
                    mockOrders
                        .where((o) =>
                            ['delivered', 'cancelled'].contains(o.status))
                        .length,
                  ),
                ],
              ),
            ),
          ),

          // Order List
          Expanded(
            child: filteredOrders.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredOrders.length,
                    itemBuilder: (context, index) {
                      return _buildOrderCard(filteredOrders[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(String tab, String label, int count) {
    final isActive = _activeTab == tab;
    return Expanded(
      child: Material(
        color: isActive ? AppColors.primaryGreen : Colors.grey[100],
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () => setState(() => _activeTab = tab),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isActive ? Colors.white : Colors.grey[700],
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isActive
                          ? Colors.white.withOpacity(0.3)
                          : Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      count.toString(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isActive ? Colors.white : Colors.grey[700],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 20),
          const Text('Belum Ada Riwayat Pesanan',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Mulai belanja sekarang untuk melihat riwayat pesanan Anda di sini.',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () =>
                Navigator.pushReplacementNamed(context, '/buyer-dashboard'),
            icon: const Icon(Icons.shopping_bag),
            label: const Text('Mulai Belanja'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(Order order) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: InkWell(
        onTap: () => _showOrderDetail(order),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _getStatusColor(order.status).withOpacity(0.1),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Order ID & Date
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Order #${order.id}',
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat('dd MMM yyyy, HH:mm')
                                .format(order.orderDate),
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                      // Status Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _getStatusColor(order.status),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_getStatusIcon(order.status),
                                size: 14, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              _getStatusText(order.status),
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Body
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow(
                      Icons.store_outlined, order.storeName ?? 'Nama Toko',
                      color: AppColors.primaryGreen),
                  const SizedBox(height: 12),
                  _buildDetailRow(
                    Icons.local_shipping_outlined,
                    '${order.courier} ${order.trackingNumber != null ? '• ${order.trackingNumber}' : ''}',
                  ),
                  const SizedBox(height: 12),
                  _buildDetailRow(Icons.payment_outlined, order.paymentMethod),
                  const Divider(height: 24),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Produk:',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      ...order.items.take(2).map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  Text('• ${item.productName}',
                                      style: const TextStyle(fontSize: 12)),
                                  const SizedBox(width: 8),
                                  Text('(${item.quantity}x)',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600])),
                                ],
                              ),
                            ),
                          ),
                      if (order.items.length > 2)
                        Text(
                          '+${order.items.length - 2} produk lainnya',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                              fontStyle: FontStyle.italic),
                        ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Total Pembayaran',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey)),
                            Text(
                              'Rp ${_formatPrice(order.totalAmount)}',
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryGreen),
                            ),
                          ]),
                      Row(
                        children: [
                          if (order.status == 'delivered')
                            OutlinedButton.icon(
                              onPressed: () {},
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Beli Lagi'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primaryGreen,
                                side: const BorderSide(
                                    color: AppColors.primaryGreen),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                              ),
                            ),
                          if (order.status == 'shipped' &&
                              order.trackingNumber != null) ...[
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () {},
                              icon: const Icon(Icons.local_shipping, size: 16),
                              label: const Text('Lacak'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.purple,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String text, {Color? color}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color ?? Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 14, color: color)),
        ),
      ],
    );
  }

  void _showOrderDetail(Order order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Detail Pesanan #${order.id}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStatusTimeline(order.status),
                      const SizedBox(height: 24),
                      _buildSection(
                        'Informasi Toko',
                        Column(children: [
                          _buildInfoRow(
                              'Nama Toko', order.storeName ?? 'Unknown'),
                          _buildInfoRow('Kurir', order.courier),
                          if (order.trackingNumber != null)
                            _buildInfoRow('No. Resi', order.trackingNumber!),
                        ]),
                      ),
                      _buildSection(
                        'Daftar Produk',
                        Column(
                            children: order.items
                                .map((item) => _buildOrderItem(item))
                                .toList()),
                      ),
                      _buildSection(
                        'Ringkasan Pembayaran',
                        Column(children: [
                          _buildPriceRow('Subtotal',
                              order.totalAmount - order.shippingCost),
                          _buildPriceRow('Ongkos Kirim', order.shippingCost),
                          const Divider(),
                          _buildPriceRow('Total', order.totalAmount,
                              isBold: true),
                        ]),
                      ),
                    ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusTimeline(String currentStatus) {
    final statuses = ['pending', 'confirmed', 'shipped', 'delivered'];
    final currentIndex = statuses.indexOf(currentStatus.toLowerCase());

    return Column(
      children: statuses.asMap().entries.map((entry) {
        final index = entry.key;
        final status = entry.value;
        final isCompleted = index <= currentIndex;
        final isCancelled = currentStatus == 'cancelled';

        return Row(
          children: [
            Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCancelled
                        ? Colors.red
                        : isCompleted
                            ? AppColors.primaryGreen
                            : Colors.grey[300],
                  ),
                  child: Icon(
                    isCancelled
                        ? Icons.close
                        : isCompleted
                            ? Icons.check
                            : null,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
                if (index < statuses.length - 1)
                  Container(
                    width: 2,
                    height: 30,
                    color: isCompleted && !isCancelled
                        ? AppColors.primaryGreen
                        : Colors.grey[300],
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                    bottom: index < statuses.length - 1 ? 32 : 0),
                child: Text(
                  _getStatusText(status),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight:
                        isCompleted ? FontWeight.w600 : FontWeight.normal,
                    color: isCompleted && !isCancelled
                        ? Colors.black
                        : Colors.grey,
                  ),
                ),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildSection(String title, Widget content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        content,
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
          Text(value,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildOrderItem(OrderItem item) {
    return Container(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8)),
            child: item.imageUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(item.imageUrl!, fit: BoxFit.cover),
                  )
                : Icon(Icons.shopping_basket, color: Colors.grey[400]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.productName,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500)),
              Text(
                '${item.quantity} x Rp ${_formatPrice(item.price)}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ]),
          ),
          Text(
            'Rp ${_formatPrice(item.price * item.quantity)}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceRow(String label, double amount, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: isBold ? Colors.black : Colors.grey[600],
            ),
          ),
          Text(
            'Rp ${_formatPrice(amount)}',
            style: TextStyle(
              fontSize: isBold ? 16 : 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: isBold ? AppColors.primaryGreen : Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  String _formatPrice(double price) {
    return NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0)
        .format(price);
  }
}
