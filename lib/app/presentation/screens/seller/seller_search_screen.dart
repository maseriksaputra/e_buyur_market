// lib/features/seller/screens/search_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // debugPrint
import 'package:provider/provider.dart';

import '../../../common/models/product_model.dart';
import '../../providers/product_provider.dart'; // Sesuaikan path jika berbeda
import '../../../core/theme/app_colors.dart';   // Sesuaikan path

// ⬇️ WAJIB: helper perbaikan URL gambar
import 'package:e_buyur_market_flutter_5/app/core/utils/url_fix.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({Key? key}) : super(key: key);

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String _searchQuery = '';
  String _selectedCategory = 'all';

  @override
  Widget build(BuildContext context) {
    final productProvider = Provider.of<ProductProvider>(context);

    final List<Product> filteredProducts = productProvider.products.where((p) {
      final name = (p.name ?? '').toLowerCase();
      final matchesSearch = name.contains(_searchQuery.toLowerCase());

      // ✅ bandingkan kategori sesuai DB ('buah' / 'sayur'), case-insensitive + trim
      final rawCat = (p.category ?? '').toLowerCase().trim();
      final matchesCategory = _selectedCategory == 'all'
          ? true
          : (rawCat == _selectedCategory.toLowerCase().trim());

      return matchesSearch && matchesCategory;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pencarian', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Cari di E-Buyur Market...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: const BorderSide(color: AppColors.lightGrey),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: const BorderSide(color: AppColors.primaryGreen),
                ),
              ),
            ),
          ),

          // Category chips (✅ gunakan 'buah' & 'sayur' agar cocok dengan DB)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildCategoryChip('Semua', 'all'),
                _buildCategoryChip('Buah',  'buah'),
                _buildCategoryChip('Sayur', 'sayur'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Grid Produk (gambar sudah lewat fixImageUrl)
          Expanded(
            child: filteredProducts.isEmpty
                ? const Center(
                    child: Text('Produk tidak ditemukan',
                        style: TextStyle(color: Colors.grey)),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredProducts.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.7,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemBuilder: (context, index) {
                      final product = filteredProducts[index];
                      return _SellerProductTile(
                        product: product,
                        onTap: () {
                          // ⬇️ route seller + kirim arguments product
                          Navigator.pushNamed(
                            context,
                            '/seller/product/detail',
                            arguments: product,
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String label, String categoryId) {
    final bool isActive = _selectedCategory == categoryId;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ChoiceChip(
        label: Text(label),
        selected: isActive,
        onSelected: (selected) {
          if (selected) setState(() => _selectedCategory = categoryId);
        },
        selectedColor: AppColors.primaryGreen,
        labelStyle: TextStyle(
          color: isActive ? Colors.white : AppColors.textDark,
        ),
        backgroundColor: AppColors.backgroundGrey,
        shape: StadiumBorder(
          side: BorderSide(
            color: isActive ? AppColors.primaryGreen : AppColors.lightGrey,
          ),
        ),
      ),
    );
  }
}

/// Kartu produk khusus layar seller-search
/// ⬇️ Gambar SELALU via fixImageUrl (fallback pilih kandidat pertama dari imageUrls bila ada)
class _SellerProductTile extends StatelessWidget {
  final Product product;
  final VoidCallback? onTap;

  const _SellerProductTile({
    Key? key,
    required this.product,
    this.onTap,
  }) : super(key: key);

  String _resolveUrl(Product p) {
    // Ambil kandidat fallback pertama jika primary null/kosong
    final primary = p.imageUrl; // pastikan model men-setup ini dg benar
    final List<String>? imageUrls = p.imageUrls; // pastikan field ada di model
    final firstFallback =
        (imageUrls != null && imageUrls.isNotEmpty) ? imageUrls.first : null;

    final chosen = (primary != null && primary.isNotEmpty)
        ? primary
        : (firstFallback ?? '');

    return fixImageUrl(chosen);
  }

  String _formatPrice(num? price, String? unit) {
    final n = (price ?? 0).toDouble();
    final u = (unit ?? '').trim();
    return 'Rp ${n.toStringAsFixed(0)}${u.isNotEmpty ? ' / $u' : ''}';
    }

  @override
  Widget build(BuildContext context) {
    final url = _resolveUrl(product);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border.withOpacity(0.6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🔳 Gambar pakai fixImageUrl + error/loading handlers
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: AspectRatio(
                  aspectRatio: 1, // kotak
                  child: url.isEmpty
                      ? const Placeholder(fallbackHeight: 120)
                      : Image.network(
                          url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, err, __) {
                            debugPrint('IMG_ERROR -> $url :: $err');
                            return const Center(
                              child: Icon(Icons.broken_image_outlined,
                                  size: 56, color: Colors.grey),
                            );
                          },
                          loadingBuilder: (context, child, loading) {
                            if (loading == null) return child;
                            return const Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            );
                          },
                        ),
                ),
              ),

              // 🧾 Info
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                child: Text(
                  product.name ?? '-',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  (product.category ?? '').isEmpty ? '—' : (product.category ?? ''),
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),

              // 💸 Harga ringkas
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: Text(
                  _formatPrice(product.price, product.unit),
                  style: const TextStyle(
                    color: AppColors.primaryGreen,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
