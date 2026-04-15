// lib/app/presentation/screens/buyer/cart_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:e_buyur_market_flutter_5/app/presentation/providers/cart_provider.dart';
// Jika AppEventBus belum ada di project-mu, hapus import di bawah ini.
import 'package:e_buyur_market_flutter_5/app/core/event/app_event.dart';

final _idr = NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp ',
  decimalDigits: 0,
);

class CartScreen extends StatefulWidget {
  const CartScreen({Key? key}) : super(key: key);

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  StreamSubscription<AppEvent>? _sub;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<CartProvider>().fetch());

    // Kalau AppEventBus tidak ada, comment 3 baris ini
    _sub = AppEventBus.I.stream
        .where((e) => e == AppEvent.cartChanged)
        .listen((_) => context.read<CartProvider>().fetch());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ---------- Helpers ----------
  int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.round();
    return int.tryParse('$v') ?? 0;
  }

  String _toStr(dynamic v, {String fallback = ''}) {
    if (v == null) return fallback;
    return v.toString();
  }

  // Gambar produk dengan fallback ikon (tanpa asset)
  Widget _productThumb(String? url) {
    const size = 64.0;
    Widget fallback() => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFEFEFEF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.image_not_supported),
        );

    if (url == null || url.isEmpty) return fallback();

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback(),
      ),
    );
  }

  Future<void> _refresh(CartProvider cp) async {
    try {
      await cp.fetch();
    } catch (_) {}
  }

  // Operasi berbasis product_id (sesuai API baru)
  Future<void> _removeByProduct(CartProvider cp, int productId) async {
    try {
      await cp.removeByProduct(productId);
    } catch (_) {
      // fallback kompat lama yang ADA di CartProvider kamu
      try {
        await cp.removeByProductId(productId);
      } catch (_) {}
    }
    await _refresh(cp);
  }

  Future<void> _setQtyByProduct(CartProvider cp, int productId, int qty) async {
    if (qty < 0) qty = 0;
    try {
      await cp.setQtyByProduct(productId, qty);
    } catch (_) {
      // fallback kompat lama yang ADA di CartProvider kamu
      try {
        await cp.updateQty(productId, qty);
      } catch (_) {
        try {
          await cp.setQty(productId, qty);
        } catch (_) {}
      }
    }
    await _refresh(cp);
  }

  @override
  Widget build(BuildContext context) {
    final cp = context.watch<CartProvider>();

    if (cp.loading || cp.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Ambil item langsung dari payload cart (bukan Set/dedup)
    final cartMap = cp.cart;
    final items = (cartMap?['items'] as List?) ?? [];

    if (items.isEmpty) {
      // 🚫 Hapus "const" di Scaffold karena ada AppBar (non-const)
      return Scaffold(
        appBar: AppBar(title: const Text('Keranjang')),
        body: const Center(child: Text('Keranjang kosong')),
      );
    }

    // Subtotal keseluruhan (untuk referensi)
    final subtotalAll = cp.subtotal;

    // ===== Seleksi =====
    final canCheckout = cp.hasSelection;
    final subSel = cp.selectedSubtotal;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Keranjang'),
        actions: [
          // Aksi "Pilih Semua" / "Kosongkan Pilihan" (opsional, tapi membantu)
          TextButton(
            onPressed: () {
              if (cp.hasSelection && cp.selectedIds.length == items.length) {
                cp.clearSelection();
              } else {
                cp.selectAll();
              }
            },
            child: Text(
              (cp.hasSelection && cp.selectedIds.length == items.length)
                  ? 'Batal Pilih'
                  : 'Pilih Semua',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 120),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) {
            final m = (items[i] as Map).map(
              (k, v) => MapEntry(k.toString(), v),
            ) as Map<String, dynamic>;

            final cartItemId = _toInt(m['id']);              // id baris cart
            final productId  = _toInt(m['product_id']);      // ID produk
            final title      = _toStr(m['name'], fallback: 'Produk');
            final unitLabel  = _toStr(m['unit'], fallback: 'pcs');
            final qty        = _toInt(m['qty']);
            final unitPrice  = _toInt(m['unit_price']);
            final lineTotal  = _toInt(m['line_total'] ?? (unitPrice * qty));
            final imgUrl     = _toStr(m['image_url']);

            final selected = cp.selectedIds.contains(cartItemId);

            return Dismissible(
              key: ValueKey('cart_${cartItemId}_${productId}_$i'),
              direction: DismissDirection.endToStart, // geser kiri utk hapus
              background: _DeleteBg(),
              confirmDismiss: (_) async {
                return await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Hapus item?'),
                        content: Text('Hapus "$title" dari keranjang?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Batal'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Hapus'),
                          ),
                        ],
                      ),
                    ) ??
                    false;
              },
              onDismissed: (_) async {
                await _removeByProduct(context.read<CartProvider>(), productId);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Item "$title" dihapus')),
                  );
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(blurRadius: 8, color: Colors.black12),
                  ],
                ),
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    // ✅ Checkbox seleksi item
                    Checkbox(
                      value: selected,
                      onChanged: (_) => cp.toggleSelect(cartItemId),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    const SizedBox(width: 6),

                    _productThumb(imgUrl),
                    const SizedBox(width: 10),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$qty $unitLabel • ${_idr.format(unitPrice)}',
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),

                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _idr.format(lineTotal),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        _QtyStepper(
                          qty: qty,
                          onDec: () async {
                            final next = qty - 1;
                            if (next <= 0) {
                              final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (_) => AlertDialog(
                                      title: const Text('Hapus item?'),
                                      content: Text(
                                        'Kuantitas menjadi 0.\nHapus "$title" dari keranjang?',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, false),
                                          child: const Text('Batal'),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, true),
                                          child: const Text('Hapus'),
                                        ),
                                      ],
                                    ),
                                  ) ??
                                  false;
                              if (ok) {
                                await _removeByProduct(context.read<CartProvider>(), productId);
                              }
                            } else {
                              await _setQtyByProduct(context.read<CartProvider>(), productId, next);
                            }
                          },
                          onInc: () async {
                            await _setQtyByProduct(context.read<CartProvider>(), productId, qty + 1);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(blurRadius: 8, color: Colors.black12)],
          ),
          child: Row(
            children: [
              // Info subtotal seleksi + total semua sebagai info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Subtotal Terpilih', style: TextStyle(fontWeight: FontWeight.w600)),
                    Text(_idr.format(subSel)),
                    const SizedBox(height: 2),
                    Text(
                      'Total: ${_idr.format(subtotalAll)}',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  shape: const StadiumBorder(),
                  minimumSize: const Size(0, 44),
                ),
                onPressed: canCheckout
                    ? () {
                        // 👉 Hanya lanjut jika ada seleksi
                        Navigator.pushNamed(context, '/checkout');
                      }
                    : null,
                child: Text('Checkout (${_idr.format(subSel)})'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- Widgets kecil ----------

class _QtyStepper extends StatelessWidget {
  final int qty;
  final VoidCallback onDec;
  final VoidCallback onInc;

  const _QtyStepper({
    Key? key,
    required this.qty,
    required this.onDec,
    required this.onInc,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final disabledMinus = qty <= 1;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(999),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      height: 34,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RoundIconButton(icon: Icons.remove, onTap: disabledMinus ? null : onDec),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('$qty', style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          _RoundIconButton(icon: Icons.add, onTap: onInc),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _RoundIconButton({Key? key, required this.icon, this.onTap}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkResponse(onTap: onTap, radius: 18, child: Icon(icon, size: 18));
  }
}

class _DeleteBg extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.red.shade600,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.delete, color: Colors.white),
    );
  }
}
