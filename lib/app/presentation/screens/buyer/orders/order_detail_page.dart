import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/orders_provider.dart';
import '../../../providers/auth_provider.dart';

class OrderDetailPage extends StatefulWidget {
  final String orderId;
  const OrderDetailPage({Key? key, required this.orderId}) : super(key: key);

  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  Map<String, dynamic>? _detail;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapAndLoad());
  }

  void _bootstrapAndLoad() async {
    final auth = context.read<AuthProvider>();
    context.read<OrdersProvider>().setAuthToken(auth.token);
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final m = await context.read<OrdersProvider>().fetchDetail(widget.orderId);
      setState(() {
        _detail = m;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    final title = 'Order #${widget.orderId}';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : (d == null || d.isEmpty)
                  ? const _EmptyView(text: 'Detail pesanan tidak ditemukan.')
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _HeaderCard(detail: d),
                          const SizedBox(height: 12),
                          _ItemsCard(detail: d),
                          const SizedBox(height: 12),
                          _TotalsCard(detail: d),
                          const SizedBox(height: 12),
                          _ShippingCard(detail: d),
                          const SizedBox(height: 24),
                          _Actions(detail: d, orderId: widget.orderId, onDone: _load),
                        ],
                      ),
                    ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final Map<String, dynamic> detail;
  const _HeaderCard({required this.detail});

  @override
  Widget build(BuildContext context) {
    final code = (detail['code'] ?? detail['order_code'] ?? detail['id'] ?? '').toString();
    final status = (detail['status'] ?? '').toString();
    final createdAtStr = (detail['created_at'] ?? detail['date'] ?? '').toString();
    final createdAt = _tryParseDate(createdAtStr);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.receipt_long, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(code, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                    status.isEmpty ? '—' : _statusLabel(status),
                    style: TextStyle(
                      color: _statusColor(context, status),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (createdAt != null) ...[
                    const SizedBox(height: 4),
                    Text(_formatDate(createdAt), style: _mutedStyle(context)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemsCard extends StatelessWidget {
  final Map<String, dynamic> detail;
  const _ItemsCard({required this.detail});

  @override
  Widget build(BuildContext context) {
    final list = (detail['items'] ??
            detail['order_items'] ??
            detail['products'] ??
            detail['lines'] ??
            const []) as List?;

    if (list == null || list.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Tidak ada item.', style: _mutedStyle(context)),
        ),
      );
    }

    return Card(
      child: Column(
        children: [
          const ListTile(
            leading: Icon(Icons.shopping_bag_outlined),
            title: Text('Item Pesanan', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          const Divider(height: 1),
          ...list.map((e) {
            final m = (e is Map<String, dynamic>) ? e : Map<String, dynamic>.from(e as Map);
            final name = (m['name'] ?? m['product_name'] ?? 'Item').toString();
            final qty = _asInt(m['qty'] ?? m['quantity'] ?? 1);
            final price = _asNum(m['price'] ?? m['unit_price'] ?? m['subtotal'] ?? 0) ?? 0;

            return ListTile(
              title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('Qty: $qty', style: _mutedStyle(context)),
              trailing: Text(_formatCurrency(price)),
            );
          }).toList(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  final Map<String, dynamic> detail;
  const _TotalsCard({required this.detail});

  @override
  Widget build(BuildContext context) {
    final subtotal = _asNum(detail['subtotal'] ?? detail['sub_total'] ?? 0) ?? 0;
    final shipping = _asNum(detail['shipping_cost'] ?? detail['delivery_fee'] ?? 0) ?? 0;
    final discount = _asNum(detail['discount'] ?? 0) ?? 0;
    final total = _asNum(detail['total'] ?? detail['grand_total'] ?? 0) ?? 0;

    Widget row(String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            children: [
              Expanded(child: Text(label, style: bold ? const TextStyle(fontWeight: FontWeight.w700) : null)),
              Text(value, style: bold ? const TextStyle(fontWeight: FontWeight.w700) : null),
            ],
          ),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            const ListTile(
              leading: Icon(Icons.attach_money),
              title: Text('Ringkasan Pembayaran', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            row('Subtotal', _formatCurrency(subtotal)),
            row('Ongkir', _formatCurrency(shipping)),
            if (discount > 0) row('Diskon', '- ${_formatCurrency(discount)}'),
            const Divider(height: 24),
            row('Total', _formatCurrency(total), bold: true),
          ],
        ),
      ),
    );
  }
}

class _ShippingCard extends StatelessWidget {
  final Map<String, dynamic> detail;
  const _ShippingCard({required this.detail});

  @override
  Widget build(BuildContext context) {
    final addr = (detail['shipping_address'] ??
            detail['address'] ??
            (detail['shipping'] is Map ? (detail['shipping'] as Map)['address'] : null))
        ?.toString();

    if (addr == null || addr.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Alamat pengiriman tidak tersedia.', style: _mutedStyle(context)),
        ),
      );
    }

    return Card(
      child: ListTile(
        leading: const Icon(Icons.location_on_outlined),
        title: const Text('Alamat Pengiriman', style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(addr),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  final Map<String, dynamic> detail;
  final String orderId;
  final Future<void> Function() onDone;

  const _Actions({required this.detail, required this.orderId, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final status = (detail['status'] ?? '').toString().toLowerCase();

    final canCancel = <String>['pending', 'paid', 'processing'].contains(status);
    final canConfirm = <String>['shipped'].contains(status);

    if (!canCancel && !canConfirm) return const SizedBox.shrink();

    return Row(
      children: [
        if (canCancel)
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Batalkan'),
              onPressed: () async {
                final ok = await context.read<OrdersProvider>().cancelOrder(orderId);
                if (ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Pesanan dibatalkan')),
                  );
                  await onDone();
                } else {
                  final err = context.read<OrdersProvider>().error ?? 'Gagal membatalkan pesanan.';
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                }
              },
            ),
          ),
        if (canCancel && canConfirm) const SizedBox(width: 12),
        if (canConfirm)
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Sudah Diterima'),
              onPressed: () async {
                final ok = await context.read<OrdersProvider>().confirmReceived(orderId);
                if (ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Pesanan dikonfirmasi diterima')),
                  );
                  await onDone();
                } else {
                  final err = context.read<OrdersProvider>().error ?? 'Gagal konfirmasi penerimaan.';
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                }
              },
            ),
          ),
      ],
    );
  }
}

// ===== Utilities (lokal) =====
TextStyle _mutedStyle(BuildContext c) => TextStyle(color: Theme.of(c).colorScheme.outline);

String _statusLabel(String s) {
  final v = s.toLowerCase();
  switch (v) {
    case 'pending':
      return 'Menunggu Pembayaran';
    case 'paid':
      return 'Dibayar';
    case 'processing':
      return 'Diproses';
    case 'shipped':
      return 'Dikirim';
    case 'delivered':
      return 'Selesai';
    case 'cancelled':
    case 'canceled':
      return 'Dibatalkan';
    default:
      return s;
  }
}

Color _statusColor(BuildContext c, String s) {
  final v = s.toLowerCase();
  switch (v) {
    case 'pending':
      return Colors.orange.shade700;
    case 'paid':
    case 'processing':
      return Colors.blue.shade700;
    case 'shipped':
      return Colors.indigo.shade700;
    case 'delivered':
      return Colors.green.shade700;
    case 'cancelled':
    case 'canceled':
      return Colors.red.shade700;
    default:
      return Theme.of(c).colorScheme.primary;
  }
}

DateTime? _tryParseDate(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  try {
    return DateTime.tryParse(iso)?.toLocal();
  } catch (_) {
    return null;
  }
}

int _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

num? _asNum(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  if (v is String) {
    final s = v.replaceAll(RegExp(r'[^\d\.]'), '');
    return num.tryParse(s);
  }
  return null;
}

String _formatCurrency(num v) => 'Rp ${v.toStringAsFixed(0)}';

// ✅ Tambahan helper yang hilang: format tanggal dd/MM/yyyy HH:mm
String _formatDate(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final yy = d.year.toString();
  final hh = d.hour.toString().padLeft(2, '0');
  final mi = d.minute.toString().padLeft(2, '0');
  return '$dd/$mm/$yy $hh:$mi';
}

class _EmptyView extends StatelessWidget {
  final String text;
  const _EmptyView({required this.text});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
        ),
      );
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Terjadi kesalahan saat memuat detail pesanan.'),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center, style: _mutedStyle(context)),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: onRetry, child: const Text('Coba Lagi')),
            ],
          ),
        ),
      );
}
