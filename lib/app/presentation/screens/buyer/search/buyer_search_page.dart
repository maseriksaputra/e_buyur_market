// lib/app/presentation/screens/buyer/search/buyer_search_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Provider & model
import '../../../providers/product_provider.dart';
import 'package:e_buyur_market_flutter_5/app/common/models/product_model.dart';

// util (tetap dipakai untuk jaga-jaga perbaikan URL gambar)
import '../../../../core/utils/url_fix.dart';

// routes (untuk push ke detail produk)
import 'package:e_buyur_market_flutter_5/main.dart' show AppRoutes;

class BuyerSearchPage extends StatefulWidget {
  const BuyerSearchPage({super.key});

  @override
  State<BuyerSearchPage> createState() => _BuyerSearchPageState();
}

class _BuyerSearchPageState extends State<BuyerSearchPage> {
  final TextEditingController _c = TextEditingController();
  final FocusNode _fn = FocusNode();

  Timer? _debounce;
  String _selectedCategory = 'Semua';

  @override
  void initState() {
    super.initState();
    // Autofocus ringan
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fn.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _c.dispose();
    _fn.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _doSearch);
  }

  void _onSubmitted(String _) => _doSearch();

  /// ✅ DISARANKAN: panggil ProductProvider.refresh(search, category)
  void _doSearch() {
    final q = _c.text.trim();
    final cat = _selectedCategory;
    if (!mounted) return;

    if (q.isEmpty) {
      // kosongkan hasil ketika query kosong, biar UI bersih
      context.read<ProductProvider>().fetch(
            search: '',
            category: cat,
            page: 1,
            append: false,
          );
      return;
    }

    context.read<ProductProvider>().refresh(search: q, category: cat);
  }

  Future<void> _pullToRefresh() async => _doSearch();

  void _onCategoryTap(String cat) {
    setState(() => _selectedCategory = cat);
    _doSearch();
  }

  @override
  Widget build(BuildContext context) {
    final pp = context.watch<ProductProvider>();
    final items = pp.items; // List<Product>

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: TextField(
          controller: _c,
          focusNode: _fn,
          onChanged: _onChanged,
          onSubmitted: _onSubmitted,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Cari buah, sayur, toko…',
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (_c.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _c.clear();
                _onChanged('');
              },
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _pullToRefresh,
        child: ListView(
          children: [
            // Chips kategori
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: _CategoryChipsBar(
                selected: _selectedCategory,
                onChanged: _onCategoryTap,
              ),
            ),

            // State kosong / loading / error / hasil
            if (_c.text.trim().isEmpty && items.isEmpty && !pp.loading)
              const _EmptyState(text: 'Ketik kata kunci untuk mulai mencari'),

            if (pp.loading && items.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              ),

            if (pp.error != null && pp.error!.isNotEmpty && items.isEmpty && !pp.loading)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Gagal memuat hasil: ${pp.error}',
                  textAlign: TextAlign.center,
                ),
              ),

            if (_c.text.trim().isNotEmpty && !pp.loading && items.isEmpty)
              const _EmptyState(text: 'Tidak ada hasil'),

            // Hasil pencarian
            if (items.isNotEmpty)
              ...List.generate(items.length, (i) {
                final Product p = items[i];

                final image = fixImageUrl(p.imageUrl ?? '');
                final price = p.price ?? 0;

                return Column(
                  children: [
                    ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: (image.isEmpty)
                            ? const SizedBox(width: 48, height: 48)
                            : Image.network(
                                image,
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const SizedBox(width: 48, height: 48),
                              ),
                      ),
                      title: Text(
                        p.name ?? '-',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(_formatCurrency(price)),
                      onTap: () {
                        Navigator.of(context, rootNavigator: true).pushNamed(
                          AppRoutes.buyerProductDtl,
                          arguments: p,
                        );
                      },
                    ),
                    const Divider(height: 1),
                  ],
                );
              }),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  String _formatCurrency(num v) => 'Rp ${v.toStringAsFixed(0)}';
}

class _CategoryChipsBar extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _CategoryChipsBar({
    required this.selected,
    required this.onChanged,
  });

  static const _items = <String>['Semua', 'Buah', 'Sayur'];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: _items.length,
        itemBuilder: (context, i) {
          final label = _items[i];
          final active = label == selected;
          return ChoiceChip(
            label: Text(label),
            selected: active,
            onSelected: (bool sel) {
              if (sel) onChanged(label); // ✅ trigger _doSearch()
            },
            selectedColor: Theme.of(context).colorScheme.primary,
            labelStyle: TextStyle(
              color: active ? Colors.white : Theme.of(context).colorScheme.onSurface,
            ),
            backgroundColor: const Color(0xFFF4F6F8),
            shape: StadiumBorder(
              side: BorderSide(
                color: active ? Theme.of(context).colorScheme.primary : const Color(0xFFE5E7EB),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String text;
  const _EmptyState({required this.text});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
