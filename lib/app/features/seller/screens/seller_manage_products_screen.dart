import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../common/models/product_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format.dart';

// 🔧 Penting: import tipe dari ProductApiService
import '../../../core/services/product_api_service.dart'
    show SellerProductFilter, InventorySummary;

import '../../providers/seller_products_provider.dart';
import 'seller_product_edit_screen.dart';

class SellerManageProductsScreen extends StatefulWidget {
  const SellerManageProductsScreen({super.key});
  @override
  State<SellerManageProductsScreen> createState() => _SellerManageProductsScreenState();
}

class _SellerManageProductsScreenState extends State<SellerManageProductsScreen> {
  final _filter = SellerProductFilter()
    ..perPage = 50
    ..sort = 'updated_at'
    ..dir = 'desc';

  final _searchCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final p = context.read<SellerProductsProvider>();
    p.loadSummary();
    p.loadProducts(filter: _filter);
  }

  void _applyFilter() {
    final p = context.read<SellerProductsProvider>();
    p.loadProducts(filter: _filter);
    p.loadSummary();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SellerProductsProvider>();
    final s = p.summary;

    return Scaffold(
      appBar: AppBar(title: const Text('Kelola Produk')),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            p.loadSummary(),
            p.loadProducts(filter: _filter),
          ]);
        },
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // ====== HEADER SUMMARY ======
            if (s != null) _InventorySummaryCard(s),
            const SizedBox(height: 12),

            // ====== FILTER BAR ======
            _FilterBar(
              controller: _searchCtl,
              onSearch: () {
                _filter.search = _searchCtl.text.trim();
                _applyFilter();
              },
              onClear: () {
                _searchCtl.clear();
                _filter.search = null;
                _applyFilter();
              },
              onToggleActive: (val) {
                // 🔧 perbaikan: val adalah bool? → gunakan (val == true)
                _filter.isActive = (val == true) ? true : null;
                _applyFilter();
              },
              onStockOnly: (val) {
                _filter.inStockOnly = val;
                _applyFilter();
              },
              onPriceRange: (min, max) {
                _filter
                  ..priceMin = min
                  ..priceMax = max;
                _applyFilter();
              },
              onFreshRange: (min, max) {
                _filter
                  ..freshMin = min
                  ..freshMax = max;
                _applyFilter();
              },
            ),

            const SizedBox(height: 8),

            // ====== LIST ======
            if (p.isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              for (final it in p.items)
                _ProductTile(
                  it,
                  onEdit: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SellerProductEditScreen(productId: it.id!),
                      ),
                    );
                    _applyFilter();
                  },
                  onDelete: () async {
                    final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Hapus Produk'),
                            content: Text('Yakin menghapus "${it.name}"? Tindakan ini tidak dapat dibatalkan.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
                              ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Hapus')),
                            ],
                          ),
                        ) ??
                        false;
                    if (ok) {
                      await context.read<SellerProductsProvider>().remove(it.id!);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Produk dihapus')),
                        );
                      }
                    }
                  },
                ),
              if (p.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Center(child: Text('Tidak ada produk')),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InventorySummaryCard extends StatelessWidget {
  final InventorySummary s; // 🔧 tipe sekarang dikenali setelah import
  const _InventorySummaryCard(this.s);

  @override
  Widget build(BuildContext context) {
    String rp(num v) => Format.rupiah(v.toDouble()); // implement sesuai helpermu
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _KPI(title: 'Total SKU', value: '${s.totalSkus}'),
            _KPI(title: 'Total Unit', value: '${s.totalUnits}'),
            _KPI(title: 'Total Nilai', value: rp(s.totalValue)),
            _KPI(title: 'Stok Rendah', value: '${s.lowStock}'),
          ],
        ),
      ),
    );
  }
}

class _KPI extends StatelessWidget {
  final String title;
  final String value;
  const _KPI({required this.title, required this.value});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSearch, onClear;
  final ValueChanged<bool?> onToggleActive;
  final ValueChanged<bool> onStockOnly;
  final void Function(double?, double?) onPriceRange;
  final void Function(double?, double?) onFreshRange;

  const _FilterBar({
    required this.controller,
    required this.onSearch,
    required this.onClear,
    required this.onToggleActive,
    required this.onStockOnly,
    required this.onPriceRange,
    required this.onFreshRange,
  });

  @override
  Widget build(BuildContext context) {
    final priceMinCtl = TextEditingController();
    final priceMaxCtl = TextEditingController();
    final freshMinCtl = TextEditingController();
    final freshMaxCtl = TextEditingController();
    bool stockOnly = false;
    bool? activeOnly;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(children: [
          Row(children: [
            Expanded(
                child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Cari nama/desk...',
                prefixIcon: Icon(Icons.search),
              ),
              onSubmitted: (_) => onSearch(),
            )),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: onSearch, child: const Text('Cari')),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: onClear, child: const Text('Reset')),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: priceMinCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Harga min'),
                onSubmitted: (_) => onPriceRange(
                  double.tryParse(priceMinCtl.text),
                  double.tryParse(priceMaxCtl.text),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: priceMaxCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Harga max'),
                onSubmitted: (_) => onPriceRange(
                  double.tryParse(priceMinCtl.text),
                  double.tryParse(priceMaxCtl.text),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: freshMinCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Freshness % min'),
                onSubmitted: (_) => onFreshRange(
                  double.tryParse(freshMinCtl.text),
                  double.tryParse(freshMaxCtl.text),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: freshMaxCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Freshness % max'),
                onSubmitted: (_) => onFreshRange(
                  double.tryParse(freshMinCtl.text),
                  double.tryParse(freshMaxCtl.text),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            FilterChip(
              label: const Text('Hanya aktif'),
              selected: (activeOnly ?? false),
              onSelected: (v) {
                activeOnly = v ? true : null;
                onToggleActive(activeOnly);
              },
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: const Text('Stok > 0'),
              selected: stockOnly,
              onSelected: (v) {
                stockOnly = v;
                onStockOnly(stockOnly);
              },
            ),
          ]),
        ]),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final Product p;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProductTile(this.p, {required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    String rp(num v) => Format.rupiah(v.toDouble());
    return Card(
      child: ListTile(
        leading: (p.imageUrl?.isNotEmpty == true)
            ? Image.network(p.imageUrl!, width: 56, height: 56, fit: BoxFit.cover)
            : const Icon(Icons.shopping_bag_outlined, size: 32),
        title: Text(p.name ?? '-'),
        subtitle: Text('Harga: ${rp(p.price ?? 0)} • Stok: ${p.stock ?? 0}\nNilai: ${rp(p.inventoryValue)}'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(icon: const Icon(Icons.edit), onPressed: onEdit),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: onDelete),
        ]),
      ),
    );
  }
}
