// lib/app/presentation/screens/seller/seller_history_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart' as theme;

// (a) Tambah import PrimaryAppBar
import 'package:e_buyur_market_flutter_5/app/common/widgets/primary_app_bar.dart';

class SellerHistoryScreen extends StatefulWidget {
  const SellerHistoryScreen({Key? key}) : super(key: key);

  @override
  State<SellerHistoryScreen> createState() => _SellerHistoryScreenState();
}

class _SellerHistoryScreenState extends State<SellerHistoryScreen> {
  String _activeTab = 'all';
  String _search = '';

  final _orders = _mockOrders; // In real app, ambil dari provider

  @override
  Widget build(BuildContext context) {
    final filtered = _orders.where((o) {
      final matchTab = _activeTab == 'all' ? true : o.status == _activeTab;
      final q = _search.toLowerCase();
      final matchSearch = _search.isEmpty
          ? true
          : (o.customerName.toLowerCase().contains(q) ||
              (o.storeName ?? '').toLowerCase().contains(q) ||
              o.id.toLowerCase().contains(q));
      return matchTab && matchSearch;
    }).toList();

    return Scaffold(
      // (b) Ganti AppBar → PrimaryAppBar
      appBar: const PrimaryAppBar(title: 'Riwayat'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Cari pesanan / pelanggan / ID...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide(color: theme.AppColors.lightGrey),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide(color: theme.AppColors.primaryGreen),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _chip('Semua', 'all'),
                _chip('Baru', 'pending'),
                _chip('Diproses', 'processing'),
                _chip('Selesai', 'completed'),
                _chip('Dibatalkan', 'cancelled'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filtered.isEmpty
                ? _empty()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _orderCard(filtered[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String key) {
    final active = _activeTab == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: active,
        onSelected: (_) => setState(() => _activeTab = key),
        selectedColor: theme.AppColors.primaryGreen,
        labelStyle: TextStyle(
          color: active ? Colors.white : theme.AppColors.textDark,
        ),
        backgroundColor: theme.AppColors.backgroundGrey,
        shape: StadiumBorder(
          side: BorderSide(
            color: active
                ? theme.AppColors.primaryGreen
                : theme.AppColors.lightGrey,
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey),
          SizedBox(height: 12),
          Text('Belum ada pesanan',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          SizedBox(height: 4),
          Text('Pesanan yang masuk akan tampil di sini',
              style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _orderCard(_Order o) {
    final nf =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final statusColor = {
          'pending': Colors.orange,
          'processing': Colors.blue,
          'completed': Colors.green,
          'cancelled': Colors.red,
        }[o.status] ??
        Colors.grey;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(
                  o.statusLabel,
                  style: TextStyle(
                      fontSize: 12,
                      color: statusColor,
                      fontWeight: FontWeight.w600),
                ),
              ),
              const Spacer(),
              Text(DateFormat('dd MMM yyyy, HH:mm').format(o.orderDate),
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Text(o.customerName,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          ...o.items.take(2).map((it) => Row(
                children: [
                  const Icon(Icons.circle, size: 6, color: Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text('${it.productName} x${it.quantity}',
                          style: const TextStyle(color: Colors.black87))),
                  Text(nf.format(it.price * it.quantity),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              )),
          if (o.items.length > 2)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('+${o.items.length - 2} item lainnya',
                  style: const TextStyle(color: Colors.grey)),
            ),
          const Divider(height: 20),
          Row(
            children: [
              Expanded(
                  child:
                      Text('Total', style: TextStyle(color: Colors.grey[700]))),
              Text(nf.format(o.totalAmount),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.print_outlined, size: 18),
                label: const Text('Cetak'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.AppColors.primaryGreen,
                  side: BorderSide(color: theme.AppColors.primaryGreen),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: const Text('Detail'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// ==== MOCK DATA ====
class _OrderItem {
  final String productName;
  final int quantity;
  final double price;
  _OrderItem(
      {required this.productName, required this.quantity, required this.price});
}

class _Order {
  final String id;
  final String customerName;
  final String? storeName;
  final DateTime orderDate;
  final String status; // pending, processing, completed, cancelled
  final List<_OrderItem> items;
  double get totalAmount =>
      items.fold(0, (s, it) => s + it.price * it.quantity);

  String get statusLabel {
    switch (status) {
      case 'pending':
        return 'Baru';
      case 'processing':
        return 'Diproses';
      case 'completed':
        return 'Selesai';
      case 'cancelled':
        return 'Dibatalkan';
      default:
        return status;
    }
  }

  _Order({
    required this.id,
    required this.customerName,
    required this.orderDate,
    required this.status,
    required this.items,
    this.storeName,
  });
}

final _mockOrders = <_Order>[
  _Order(
    id: 'ORD-S-001',
    customerName: 'Andi Wijaya',
    orderDate: DateTime.now().subtract(const Duration(hours: 2)),
    status: 'pending',
    items: [
      _OrderItem(productName: 'Tomat Merah', quantity: 3, price: 12000),
      _OrderItem(productName: 'Wortel', quantity: 2, price: 8000),
    ],
  ),
  _Order(
    id: 'ORD-S-002',
    customerName: 'Sari Melati',
    orderDate: DateTime.now().subtract(const Duration(days: 1, hours: 3)),
    status: 'processing',
    items: [
      _OrderItem(productName: 'Pisang Ambon', quantity: 1, price: 20000),
      _OrderItem(productName: 'Apel Malang', quantity: 2, price: 15000),
      _OrderItem(productName: 'Bayam', quantity: 3, price: 5000),
    ],
  ),
  _Order(
    id: 'ORD-S-003',
    customerName: 'Budi Santoso',
    orderDate: DateTime.now().subtract(const Duration(days: 2)),
    status: 'completed',
    items: [
      _OrderItem(productName: 'Cabai Rawit', quantity: 5, price: 7000),
    ],
  ),
  _Order(
    id: 'ORD-S-004',
    customerName: 'Nina Putri',
    orderDate: DateTime.now().subtract(const Duration(days: 3)),
    status: 'cancelled',
    items: [
      _OrderItem(productName: 'Jeruk', quantity: 2, price: 18000),
      _OrderItem(productName: 'Selada', quantity: 1, price: 6000),
    ],
  ),
];
