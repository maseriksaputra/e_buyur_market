// lib/app/presentation/screens/seller/seller_manage_products_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart' as theme;
import '../../providers/auth_provider.dart';
import '../../providers/seller_dashboard_provider.dart';
import '../../../core/utils/url_fix.dart';

// ✅ konsolidasi route
import '../../../core/routes.dart';

// ✅ NAV helper (untuk detail & edit via root navigator)
import '../../navigation/seller_nav.dart';

// Opsional untuk hapus (kompatibel dengan berbagai ProductProvider).
import '../../providers/product_provider.dart';

extension ProductDeletionCompat on ProductProvider {
  Future<void> safeDeleteById(String id) async {
    final p = this as dynamic;
    try {
      final r = p.deleteProduct(id);
      if (r is Future) await r;
      return;
    } catch (_) {}
    try {
      final r = p.removeProductById(id);
      if (r is Future) await r;
      return;
    } catch (_) {}
    try {
      // ignore: invalid_use_of_protected_member
      p._products.removeWhere((e) => (e.id?.toString() ?? '') == id);
      // ignore: invalid_use_of_protected_member
      p.notifyListeners();
    } catch (_) {}
  }
}

class SellerManageProductsScreen extends StatefulWidget {
  const SellerManageProductsScreen({super.key});

  @override
  State<SellerManageProductsScreen> createState() =>
      _SellerManageProductsScreenState();
}

class _SellerManageProductsScreenState extends State<SellerManageProductsScreen>
    with TickerProviderStateMixin {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  late AnimationController _fabAnimationController;
  late Animation<double> _fabScaleAnimation;

  String _sortBy = 'name'; // name, stock, price
  bool _showLowStockOnly = false;

  @override
  void initState() {
    super.initState();
    // Pastikan data sinkron dengan beranda
    Future.microtask(
      () => context.read<SellerDashboardProvider>().loadDashboard(),
    );

    _fabAnimationController =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _fabScaleAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _fabAnimationController, curve: Curves.elasticOut),
    );
    _fabAnimationController.forward();
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _fabAnimationController.dispose();
    super.dispose();
  }

  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Urutkan & Filter',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text('Urutkan berdasarkan',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey)),
            const SizedBox(height: 12),
            ...[
              {'value': 'name', 'label': 'Nama Produk', 'icon': Icons.sort_by_alpha},
              {'value': 'stock', 'label': 'Jumlah Stok', 'icon': Icons.layers},
              {'value': 'price', 'label': 'Harga', 'icon': Icons.attach_money},
            ].map((item) {
              final act = _sortBy == item['value'];
              return ListTile(
                leading: Icon(item['icon'] as IconData,
                    color: act ? theme.AppColors.primaryGreen : Colors.grey),
                title: Text(item['label'] as String),
                trailing:
                    act ? Icon(Icons.check_circle, color: theme.AppColors.primaryGreen) : null,
                onTap: () {
                  setState(() => _sortBy = item['value'] as String);
                  Navigator.pop(context);
                },
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              );
            }),
            const Divider(height: 32),
            const Text('Filter',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey)),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Stok Rendah Saja'),
              subtitle: const Text('Tampilkan produk dengan stok < 10'),
              value: _showLowStockOnly,
              onChanged: (v) {
                setState(() => _showLowStockOnly = v);
                Navigator.pop(context);
              },
              activeColor: theme.AppColors.primaryGreen,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _filterSort(
    List<Map<String, dynamic>> src, {
    required int sellerId,
    required String query,
  }) {
    // filter by seller_id jika tersedia (fallback ke sellerId auth)
    var list = src.where((e) {
      final sid = int.tryParse('${e['seller_id'] ?? e['sellerId'] ?? sellerId}') ?? sellerId;
      return sid == sellerId;
    }).toList();

    // filter by query
    if (query.isNotEmpty) {
      list = list
          .where((e) => (('${e['name'] ?? ''}').toLowerCase()).contains(query.toLowerCase()))
          .toList();
    }

    // filter low stock
    if (_showLowStockOnly) {
      list = list.where((e) => (e['stock'] ?? 0) < 10).toList();
    }

    // sort
    list.sort((a, b) {
      switch (_sortBy) {
        case 'stock':
          return ((b['stock'] ?? 0) as int).compareTo((a['stock'] ?? 0) as int);
        case 'price':
          final ap = (a['price'] is num) ? (a['price'] as num).toDouble() : 0.0;
          final bp = (b['price'] is num) ? (b['price'] as num).toDouble() : 0.0;
          return bp.compareTo(ap);
        default:
          return ('${a['name'] ?? ''}').compareTo('${b['name'] ?? ''}');
      }
    });

    return list;
  }

  String _productNameOf(dynamic p) {
    try {
      if (p is Map) return '${p['name'] ?? '-'}';
      // ignore: avoid_dynamic_calls
      return '${(p as dynamic).name ?? '-'}';
    } catch (_) {
      return '-';
    }
  }

  @override
  Widget build(BuildContext context) {
    final nf = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final auth = context.watch<AuthProvider>();
    final dash = context.watch<SellerDashboardProvider>();

    final sellerId = int.tryParse('${auth.user?.id ?? 0}') ?? 0;

    final items = _filterSort(
      dash.myProducts,
      sellerId: sellerId,
      query: _search.text.trim(),
    );

    final totalValue = dash.myProducts.fold<double>(
      0.0,
      (sum, p) =>
          sum +
          (((p['price'] is num) ? (p['price'] as num).toDouble() : 0.0) *
              ((p['stock'] is num) ? (p['stock'] as num).toInt() : 0)),
    );

    final lowStockCount =
        dash.myProducts.where((p) => ((p['stock'] ?? 0) as int) < 10).length;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [theme.AppColors.primaryGreen.withOpacity(0.05), Colors.white],
            stops: const [0, 0.3],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                color: Colors.white,
                child: Column(
                  children: [
                    // title row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Kelola Produk',
                                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Text('${items.length} produk terdaftar',
                                style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                          ],
                        ),
                        Row(
                          children: [
                            if (lowStockCount > 0)
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.warning_amber_rounded,
                                        size: 16, color: Colors.orange),
                                    const SizedBox(width: 4),
                                    Text('$lowStockCount stok rendah',
                                        style: const TextStyle(
                                            color: Colors.orange,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            const SizedBox(width: 12),
                            IconButton(
                              onPressed: _showSortOptions,
                              icon: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: theme.AppColors.primaryGreen.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(Icons.tune,
                                    color: theme.AppColors.primaryGreen, size: 20),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // summary
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            theme.AppColors.primaryGreen.withOpacity(0.1),
                            theme.AppColors.primaryGreen.withOpacity(0.05),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.account_balance_wallet,
                              color: theme.AppColors.primaryGreen, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Total Nilai Inventori',
                                    style: TextStyle(
                                        fontSize: 12, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                Text(
                                  nf.format(totalValue),
                                  style: TextStyle(
                                      color: theme.AppColors.primaryGreen,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // search
                    TextField(
                      controller: _search,
                      focusNode: _searchFocus,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Cari produk...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _search.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _search.clear();
                                  setState(() {});
                                })
                            : null,
                        filled: true,
                        fillColor: Colors.grey[50],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),

              // list
              Expanded(
                child: dash.isLoading && dash.myProducts.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : (items.isEmpty
                        ? _empty(context)
                        : RefreshIndicator(
                            onRefresh: () =>
                                context.read<SellerDashboardProvider>().loadDashboard(),
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                              itemCount: items.length,
                              itemBuilder: (context, i) {
                                final p = items[i];
                                final lowStock = ((p['stock'] ?? 0) as int) < 10;
                                final name = '${p['name'] ?? '-'}';
                                final price = (p['price'] is num)
                                    ? (p['price'] as num).toDouble()
                                    : 0.0;
                                final stock = (p['stock'] ?? 0) as int;
                                final fresh = (p['suitability_percent'] ??
                                        p['freshness_score'] ??
                                        0)
                                    .toString();
                                final img = fixImageUrl(
                                  (p['image'] ??
                                          p['image_url'] ??
                                          p['primary_image_url'] ??
                                          '')
                                      .toString(),
                                );

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: Dismissible(
                                    key: Key('product-${p['id']}'),
                                    direction: DismissDirection.endToStart,
                                    background: Container(
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.only(right: 20),
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child:
                                          const Icon(Icons.delete, color: Colors.white, size: 28),
                                    ),
                                    // ✅ guard: swipe khusus hapus (butuh konfirmasi)
                                    confirmDismiss: (dir) async =>
                                        await _showDeleteConfirmation(p),
                                    onDismissed: (_) async => await _deleteAndRefresh(p),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(20),
                                        // ✅ Optional: buka detail via helper (root navigator di dalam)
                                        onTap: () {
                                          HapticFeedback.lightImpact();
                                          SellerNav.openDetail(context, p);
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(
                                              color: lowStock
                                                  ? Colors.orange.withOpacity(0.3)
                                                  : Colors.grey.withOpacity(0.1),
                                              width: 1.5,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(0.04),
                                                blurRadius: 10,
                                                offset: const Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          child: Row(
                                            children: [
                                              // image
                                              Container(
                                                width: 72,
                                                height: 72,
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    colors: [
                                                      theme.AppColors.primaryGreen
                                                          .withOpacity(0.1),
                                                      theme.AppColors.primaryGreen
                                                          .withOpacity(0.05),
                                                    ],
                                                  ),
                                                  borderRadius: BorderRadius.circular(16),
                                                ),
                                                child: ClipRRect(
                                                  borderRadius: BorderRadius.circular(16),
                                                  child: img.isEmpty
                                                      ? Icon(Icons.shopping_basket,
                                                          color: theme.AppColors.primaryGreen,
                                                          size: 32)
                                                      : Image.network(
                                                          img,
                                                          fit: BoxFit.cover,
                                                          errorBuilder: (_, __, ___) => Icon(
                                                            Icons.broken_image_outlined,
                                                            color:
                                                                theme.AppColors.primaryGreen,
                                                            size: 32,
                                                          ),
                                                        ),
                                                ),
                                              ),
                                              const SizedBox(width: 16),

                                              // info
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            name,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow.ellipsis,
                                                            style: const TextStyle(
                                                              fontSize: 16,
                                                              fontWeight:
                                                                  FontWeight.w700,
                                                            ),
                                                          ),
                                                        ),
                                                        if (lowStock)
                                                          Container(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                    horizontal: 8,
                                                                    vertical: 4),
                                                            decoration: BoxDecoration(
                                                              color: Colors.orange
                                                                  .withOpacity(0.1),
                                                              borderRadius:
                                                                  BorderRadius.circular(8),
                                                            ),
                                                            child: const Text(
                                                              'Stok Rendah',
                                                              style: TextStyle(
                                                                color: Colors.orange,
                                                                fontSize: 10,
                                                                fontWeight:
                                                                    FontWeight.w600,
                                                              ),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: Wrap(
                                                            spacing: 8,
                                                            runSpacing: 8,
                                                            children: [
                                                              _ChipInfo(
                                                                icon: Icons
                                                                    .inventory_2_outlined,
                                                                label: 'Stok: $stock',
                                                              ),
                                                              _ChipInfo(
                                                                icon: Icons.eco,
                                                                label: '$fresh%',
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            // ✅ Edit aman (tidak memicu swipe); pakai helper
                                                            IconButton(
                                                              onPressed: () {
                                                                HapticFeedback.lightImpact();
                                                                SellerNav.openEdit(
                                                                  context,
                                                                  p,
                                                                  disableImage: true,
                                                                );
                                                              },
                                                              icon: Container(
                                                                padding:
                                                                    const EdgeInsets.all(8),
                                                                decoration: BoxDecoration(
                                                                  color: Colors.blue
                                                                      .withOpacity(0.1),
                                                                  shape:
                                                                      BoxShape.circle,
                                                                ),
                                                                child: const Icon(
                                                                  Icons.edit,
                                                                  size: 18,
                                                                  color: Colors.blue,
                                                                ),
                                                              ),
                                                            ),
                                                            // ✅ Hapus aman (konfirmasi)
                                                            IconButton(
                                                              onPressed: () async {
                                                                HapticFeedback.lightImpact();
                                                                final ok =
                                                                    await _showDeleteConfirmation(
                                                                        p);
                                                                if (ok == true) {
                                                                  await _deleteAndRefresh(p);
                                                                }
                                                              },
                                                              icon: Container(
                                                                padding:
                                                                    const EdgeInsets.all(8),
                                                                decoration: BoxDecoration(
                                                                  color: Colors.red
                                                                      .withOpacity(0.1),
                                                                  shape:
                                                                      BoxShape.circle,
                                                                ),
                                                                child: const Icon(
                                                                  Icons.delete_outline,
                                                                  size: 18,
                                                                  color: Colors.red,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      nf.format(price),
                                                      style: TextStyle(
                                                        color: theme.AppColors.primaryGreen,
                                                        fontSize: 18,
                                                        fontWeight: FontWeight.w800,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          )),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: ScaleTransition(
        scale: _fabScaleAnimation,
        child: FloatingActionButton.extended(
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.pushNamed(context, '/seller/scan-product');
          },
          backgroundColor: theme.AppColors.primaryGreen,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Scan Produk', style: TextStyle(fontWeight: FontWeight.w600)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  /// Dialog konfirmasi hapus — kini menerima objek produk (Map/model).
  Future<bool?> _showDeleteConfirmation(dynamic p) {
    final name = _productNameOf(p);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Hapus Produk?'),
        content: Text('Anda akan menghapus: $name'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  /// Kini hapus via SellerDashboardProvider (optimistic), lalu snackbar.
  Future<void> _deleteAndRefresh(Map<String, dynamic> p) async {
    final dash = context.read<SellerDashboardProvider>();
    final success = await dash.deleteProductById(p['id']);

    if (!mounted) return;
    final name = _productNameOf(p);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(success ? Icons.check_circle : Icons.error, color: Colors.white),
          const SizedBox(width: 12),
          Text(success ? '$name terhapus' : 'Gagal menghapus $name'),
        ]),
        backgroundColor: success ? Colors.green : Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.grey[200]!, Colors.grey[100]!]),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          Text(
            _search.text.isNotEmpty ? 'Produk tidak ditemukan' : 'Belum ada produk',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            _search.text.isNotEmpty
                ? 'Coba kata kunci lain'
                : 'Mulai tambahkan produk pertama Anda',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

class _ChipInfo extends StatelessWidget {
  final IconData icon;
  final String label;
  const _ChipInfo({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
