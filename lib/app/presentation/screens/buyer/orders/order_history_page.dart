import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/orders_provider.dart';
import '../../../providers/auth_provider.dart';

class OrderHistoryPage extends StatefulWidget {
  const OrderHistoryPage({Key? key}) : super(key: key);

  @override
  State<OrderHistoryPage> createState() => _OrderHistoryPageState();
}

class _OrderHistoryPageState extends State<OrderHistoryPage> {
  final ScrollController _sc = ScrollController();
  bool _inited = false;

  // daftar status yang umum di backend
  static const List<String> _statuses = <String>[
    'all', 'pending', 'paid', 'processing', 'shipped', 'delivered', 'cancelled'
  ];

  @override
  void initState() {
    super.initState();
    _sc.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapAndLoad());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_inited) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapAndLoad());
    }
  }

  void _bootstrapAndLoad() {
    if (_inited || !mounted) return;
    _inited = true;

    final auth = context.read<AuthProvider>();
    context.read<OrdersProvider>().setAuthToken(auth.token);

    context.read<OrdersProvider>().refresh(page: 1);
  }

  @override
  void dispose() {
    _sc.removeListener(_onScroll);
    _sc.dispose();
    super.dispose();
  }

  void _onScroll() {
    final p = context.read<OrdersProvider>();
    if (!p.isLoading && _sc.position.pixels > _sc.position.maxScrollExtent - 240) {
      p.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<OrdersProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Pesanan'),
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<OrdersProvider>().refresh(page: 1),
        child: CustomScrollView(
          controller: _sc,
          slivers: [
            // Filter status
            SliverToBoxAdapter(
              child: SizedBox(
                height: 48,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  scrollDirection: Axis.horizontal,
                  itemCount: _statuses.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final s = _statuses[i];
                    final isAll = s == 'all';
                    final selected = (p.statusFilter ?? 'all') == s;
                    return ChoiceChip(
                      label: Text(isAll ? 'Semua' : s[0].toUpperCase() + s.substring(1)),
                      selected: selected,
                      onSelected: (_) {
                        final next = isAll ? null : s;
                        context.read<OrdersProvider>().setStatusFilter(next);
                        context.read<OrdersProvider>().refresh(page: 1, status: next);
                      },
                    );
                  },
                ),
              ),
            ),

            if (p.isLoading && p.orders.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (p.error != null && p.orders.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _ErrorView(
                  message: p.error!,
                  onRetry: () => context.read<OrdersProvider>().refresh(page: 1),
                ),
              )
            else if (p.orders.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyView(text: 'Belum ada pesanan.'),
              )
            else
              SliverList.separated(
                itemCount: p.orders.length + (p.isLoading ? 1 : 0),
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, idx) {
                  if (idx >= p.orders.length) {
                    // item extra sebagai loading tail
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final m = p.orders[idx];

                  // Ambil field aman
                  final id = m['id'] ?? m['order_id'] ?? m['code'] ?? m['uuid'];
                  final code = (m['code'] ?? m['order_code'] ?? '#$id').toString();
                  final status = (m['status'] ?? '').toString();
                  final total = _asNum(m['total'] ?? m['grand_total'] ?? m['amount'] ?? 0) ?? 0;
                  final createdAtStr = (m['created_at'] ?? m['date'] ?? '').toString();
                  final createdAt = _tryParseDate(createdAtStr);

                  // jumlah item (coba berbagai nama key)
                  final items = (m['items'] ??
                          m['order_items'] ??
                          m['products'] ??
                          m['lines'] ??
                          const []) as List?;
                  final itemCount = items?.length ?? 0;

                  return ListTile(
                    onTap: () {
                      Navigator.of(context).pushNamed(
                        '/order-detail',
                        arguments: id.toString(),
                      );
                    },
                    title: Text(code, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          status.isEmpty ? '—' : _statusLabel(status),
                          style: TextStyle(
                            color: _statusColor(context, status),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (createdAt != null)
                              Text(_formatDate(createdAt), style: _mutedStyle(context)),
                            if (createdAt != null) const Text(' • '),
                            Text('$itemCount item', style: _mutedStyle(context)),
                          ],
                        ),
                      ],
                    ),
                    trailing: Text(_formatCurrency(total)),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  TextStyle _mutedStyle(BuildContext c) =>
      TextStyle(color: Theme.of(c).colorScheme.outline);

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
  String _formatDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yy = d.year.toString();
    final hh = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yy $hh:$mi';
  }
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
              const Text('Gagal memuat pesanan.'),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: onRetry, child: const Text('Coba Lagi')),
            ],
          ),
        ),
      );
}
