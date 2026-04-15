// lib/app/presentation/screens/buyer/home_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:e_buyur_market_flutter_5/app/common/models/product_model.dart';
import '../../providers/product_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../common/widgets/product_card.dart';
import 'package:e_buyur_market_flutter_5/main.dart' show AppRoutes;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _selectedCategory = 'Semua';
  bool _bootstrapped = false;

  @override
  void initState() {
    super.initState();
    // ✅ panggil fetch SEKALI setelah frame pertama
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_bootstrapped) {
        _bootstrapped = true;
        context.read<ProductProvider>().fetch(category: _selectedCategory);
      }
    });
  }

  void _onCategoryTap(String cat) {
    setState(() => _selectedCategory = cat);
    // ✅ refresh dari server sesuai kategori yang dipilih
    context.read<ProductProvider>().refresh(category: _selectedCategory);
  }

  Future<void> _onPullRefresh() async {
    await context.read<ProductProvider>().refresh(category: _selectedCategory);
  }

  Future<void> _loadMore(ProductProvider pp) async {
    if (!pp.canLoadMore || pp.loading) return;
    // sesuaikan angka ini jika perPage backend berbeda 
    const perPage = 24;
    final nextPage = (pp.items.length ~/ perPage) + 1;
    await context
        .read<ProductProvider>()
        .fetch(category: _selectedCategory, page: nextPage, append: true);
  }

  @override
  Widget build(BuildContext context) {
    final pp = context.watch<ProductProvider>();
    final List<Product> products = pp.items;

    // ✅ tinggi kartu adaptif terhadap textScale
    final textScale = MediaQuery.of(context).textScaleFactor;
    final double cardHeight = 252 + (textScale > 1 ? (textScale - 1) * 24 : 0);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        title: const Text(
          'E-Buyur Market',
          style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
        ),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () => Navigator.pushNamed(context, AppRoutes.cart),
            icon: const Icon(Icons.shopping_cart_outlined),
          ),
        ],
      ),
      body: Builder(
        builder: (_) {
          if (pp.loading && products.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (pp.error != null && products.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Gagal memuat produk.', style: TextStyle(fontSize: 16)),
                    const SizedBox(height: 8),
                    if (pp.error!.isNotEmpty)
                      Text(
                        pp.error!.length > 240 ? '${pp.error!.substring(0, 240)}…' : pp.error!,
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () =>
                          context.read<ProductProvider>().fetch(category: _selectedCategory),
                      child: const Text('Coba Lagi'),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _onPullRefresh,
            child: CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 10),
                    child: _SearchBar(),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: _Banner(),
                  ),
                ),

                // Kategori (server-side filter)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: CategoryChipsBar(
                      selected: _selectedCategory,
                      onChanged: _onCategoryTap, // ✅ panggil handler
                    ),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'Produk Terbaru',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),

                // GRID PRODUK — langsung dari provider (tanpa filter lokal)
                if (products.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Center(child: Text('Tidak ada produk untuk kategori ini.')),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    sliver: SliverGrid(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final product = products[index];
                          return ProductCard(
                            product: product,
                            onTap: () {
                              Navigator.pushNamed(
                                context,
                                AppRoutes.buyerProductDtl,
                                arguments: product,
                              );
                            },
                          );
                        },
                        childCount: products.length,
                      ),
                      // ✅ GANTI: pakai mainAxisExtent untuk tinggi konsisten
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 10,
                        mainAxisExtent: cardHeight, // ✅ fix overflow
                      ),
                    ),
                  ),

                // Load more / indikator bawah
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: Center(
                      child: pp.loading && products.isNotEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: CircularProgressIndicator(),
                            )
                          : (pp.canLoadMore
                              ? OutlinedButton.icon(
                                  onPressed: () => _loadMore(pp),
                                  icon: const Icon(Icons.expand_more),
                                  label: const Text('Muat Lagi'),
                                )
                              : const SizedBox.shrink()),
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 8)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar();
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, AppRoutes.buyerSearch),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F6F8),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          children: [
            Icon(Icons.search, color: Color(0xFF99A1A8)),
            SizedBox(width: 12),
            Text('Cari buah dan sayuran...', style: TextStyle(color: Color(0xFF99A1A8))),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text('🌱', style: TextStyle(fontSize: 22)),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Buah & Sayur Segar',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                SizedBox(height: 4),
                Text(
                  'Kurangi food waste dengan berbelanja produk berkualitas',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CategoryChipsBar extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const CategoryChipsBar({
    super.key,
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
              if (sel) onChanged(label); // ✅ trigger fetch/refresh
            },
            selectedColor: AppColors.primary,
            labelStyle: TextStyle(
              color: active ? const Color.from(alpha: 1, red: 1, green: 1, blue: 1) : AppColors.textDark,
            ),
            backgroundColor: const Color(0xFFF4F6F8),
            shape: StadiumBorder(
              side: BorderSide(
                color: active ? AppColors.primary : AppColors.border,
              ),
            ),
          );
        },
      ),
    );
  }
}
