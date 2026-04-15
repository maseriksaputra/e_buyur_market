// lib/app/presentation/screens/buyer/search_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../common/models/product_model.dart';
import '../../../common/models/product_category.dart';
import '../../providers/product_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../common/widgets/product_card.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _c = TextEditingController();
  String _query = '';
  Timer? _debounce;

  // ✅ State filter kategori lokal: null = semua
  ProductCategory? _activeCat;

  bool _boot = false;
  void _bootstrapOnce(BuildContext ctx) {
    if (_boot) return;
    _boot = true;
    // Provider baru: cukup muat halaman pertama
    ctx.read<ProductProvider>().fetchFirstPage();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapOnce(context));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _onQueryChanged(String v) {
    setState(() => _query = v.trim());
    // Debounce hanya untuk UX; kita filter lokal saja
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() {}); // trigger rebuild
    });
  }

  void _onClear() {
    _c.clear();
    setState(() => _query = '');
  }

  // ================= Modern Pills Bar (Semua, Buah, Sayur) =================
  Widget _categoryBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          _pill(
            label: 'Semua',
            selected: _activeCat == null,
            bg: const Color(0xFF16A34A), // emerald-600
            icon: Icons.check_circle_rounded,
            onTap: () => setState(() => _activeCat = null),
          ),
          const SizedBox(width: 8),
          _pill(
            label: 'Buah',
            selected: _activeCat == ProductCategory.buah,
            bg: const Color(0xFFF59E0B), // orange-500
            icon: Icons.spa_rounded,
            onTap: () => setState(() => _activeCat = ProductCategory.buah),
          ),
          const SizedBox(width: 8),
          _pill(
            label: 'Sayur',
            selected: _activeCat == ProductCategory.sayur,
            bg: const Color(0xFF34D399), // emerald-400
            icon: Icons.eco_rounded,
            onTap: () => setState(() => _activeCat = ProductCategory.sayur),
          ),
        ],
      ),
    );
  }

  Widget _pill({
    required String label,
    required bool selected,
    required Color bg,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final Color border = bg.withOpacity(0.35);
    final Color fill = selected ? bg : Colors.transparent;
    final Color fg = selected ? Colors.white : bg;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: border, width: 1),
          boxShadow: selected
              ? [
                  BoxShadow(
                      color: bg.withOpacity(0.22),
                      blurRadius: 10,
                      offset: const Offset(0, 4))
                ]
              : const [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(fontWeight: FontWeight.w700, color: fg)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Pencarian'),
        actions: [
          IconButton(
            tooltip: 'Segarkan',
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<ProductProvider>().refresh(),
          ),
        ],
      ),
      body: Consumer<ProductProvider>(
        builder: (context, p, _) {
          final List<Product> all = p.products;
          final List<Product> items = _filterSearch(all, _query);

          if (p.isLoading && all.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          return CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              // ===== Search bar =====
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: _SearchBar(
                    controller: _c,
                    onChanged: _onQueryChanged,
                    onClear: _onClear,
                  ),
                ),
              ),

              // ===== Satu-satunya bar kategori (modern pills) =====
              const SliverToBoxAdapter(child: SizedBox(height: 2)),
              SliverToBoxAdapter(child: _categoryBar()),

              // ===== Heading =====
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    _query.isEmpty ? 'Produk Terbaru' : 'Hasil untuk "$_query"',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),

              // ===== Hasil =====
              if (items.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 32, 16, 120),
                    child: _EmptyState(
                      title: 'Tidak ada produk',
                      subtitle: _query.isEmpty
                          ? 'Produk belum tersedia.'
                          : 'Coba kata kunci lain atau kurangi filter.',
                    ),
                  ),
                )
              else
                SliverToBoxAdapter(
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: items.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.70,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemBuilder: (context, index) {
                      return ProductCard(
                        product: items[index],
                        onTap: () {
                          Navigator.pushNamed(
                            context,
                            '/buyer-product-detail',
                            arguments: items[index],
                          );
                        },
                      );
                    },
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          );
        },
      ),
    );
  }

  // =========================================================
  // Gabungan filter teks + kategori lokal
  // =========================================================
  List<Product> _filterSearch(List<Product> src, String q) {
    final ql = q.trim().toLowerCase();
    Iterable<Product> it = src;

    if (ql.isNotEmpty) {
      it = it.where((p) {
        try {
          final name = (p as dynamic).name?.toString().toLowerCase() ?? '';
          final desc =
              (p as dynamic).description?.toString().toLowerCase() ?? '';
          return name.contains(ql) || desc.contains(ql);
        } catch (_) {
          return false;
        }
      });
    }

    if (_activeCat != null) {
      final cat = _activeCat!.slug;
      it = it.where((p) {
        // 1) kalau enum di model
        try {
          final c = (p as dynamic).category;
          if (c is ProductCategory) return c.slug == cat;
        } catch (_) {}
        // 2) kalau string/slug di model
        try {
          final s1 = (p as dynamic).category?.toString().toLowerCase();
          final s2 = (p as dynamic).categorySlug?.toString().toLowerCase();
          if (s1 == cat || s2 == cat) return true;
        } catch (_) {}
        // 3) fallback bila objek adalah Map
        try {
          final m = (p as dynamic) as Map;
          final s = (m['category'] ?? m['category_slug'] ?? '')
              .toString()
              .toLowerCase();
          return s == cat;
        } catch (_) {}
        return false;
      });
    }

    return it.toList();
  }
}

// =========================================================
// Search Bar
// =========================================================
class _SearchBar extends StatelessWidget {
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  const _SearchBar({this.controller, this.onChanged, this.onClear});

  @override
  Widget build(BuildContext context) {
    final hasText = (controller?.text ?? '').isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundGrey,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: AppColors.lightGrey),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          const Icon(Icons.search, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              onSubmitted: (v) => onChanged?.call(v.trim()), // filter lokal
              decoration: const InputDecoration(
                hintText: 'Cari buah, sayur, atau toko...',
                border: InputBorder.none,
              ),
            ),
          ),
          if (hasText)
            IconButton(
              onPressed: onClear,
              icon: const Icon(Icons.close, color: Colors.grey),
              tooltip: 'Hapus',
            ),
        ],
      ),
    );
  }
}

// =========================================================
// Empty State
// =========================================================
class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  const _EmptyState({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: const Color(0xFFF0F4F8),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.search_off_rounded,
              size: 40, color: Color(0xFF9AA8B2)),
        ),
        const SizedBox(height: 12),
        Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black54),
        ),
      ],
    );
  }
}
