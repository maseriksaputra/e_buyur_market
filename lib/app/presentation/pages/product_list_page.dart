// lib/app/presentation/pages/product_list_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/product_provider.dart';
import '../../common/widgets/product_card.dart';
import '../../common/helpers/freshness_helper.dart';
import '../../common/models/product_model.dart';

class ProductListPage extends StatefulWidget {
  const ProductListPage({Key? key}) : super(key: key);

  @override
  State<ProductListPage> createState() => _ProductListPageState();
}

class _ProductListPageState extends State<ProductListPage> {
  String selectedFilter = 'Semua';
  bool isGridView = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Produk Segar'),
        backgroundColor: Colors.green,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(isGridView ? Icons.list : Icons.grid_view),
            onPressed: () {
              setState(() {
                isGridView = !isGridView;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Section
          Container(
            color: Colors.white,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _buildFilterChip(
                    'Semua',
                    Icons.all_inclusive,
                    Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'Sangat Layak',
                    Icons.verified,
                    const Color(0xFF4CAF50),
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'Layak',
                    Icons.check_circle,
                    const Color(0xFF8BC34A),
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'Cukup Layak',
                    Icons.info,
                    const Color(0xFFCDDC39),
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'Kurang Layak',
                    Icons.warning_amber,
                    const Color(0xFFFFC107),
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'Tidak Layak',
                    Icons.error_outline,
                    const Color(0xFFFF9800),
                  ),
                ],
              ),
            ),
          ),

          // Products Section
          Expanded(
            child: Consumer<ProductProvider>(
              builder: (context, provider, child) {
                List<Product> filteredProducts = _getFilteredProducts(provider);

                if (filteredProducts.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Tidak ada produk dengan filter "$selectedFilter"',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: isGridView
                      ? _buildGridView(filteredProducts)
                      : _buildListView(filteredProducts),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, IconData icon, Color color) {
    final isSelected = selectedFilter == label;

    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: isSelected ? Colors.white : color,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black87,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          selectedFilter = label;
        });
      },
      backgroundColor: color.withOpacity(0.1),
      selectedColor: color,
      checkmarkColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: color.withOpacity(0.3),
        ),
      ),
    );
  }

  List<Product> _getFilteredProducts(ProductProvider provider) {
    switch (selectedFilter) {
      case 'Sangat Layak':
        return provider.getProductsByFreshness(90, 100);
      case 'Layak':
        return provider.getProductsByFreshness(75, 89);
      case 'Cukup Layak':
        return provider.getProductsByFreshness(60, 74);
      case 'Kurang Layak':
        return provider.getProductsByFreshness(40, 59);
      case 'Tidak Layak':
        return provider.getProductsByFreshness(0, 39);
      default:
        return provider.products;
    }
  }

  Widget _buildGridView(List<Product> products) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.72,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        return ProductCard(
          product: products[index],
          onTap: () => _showProductDetail(context, products[index]),
          onAddToCart: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    Text('${products[index].name} ditambahkan ke keranjang'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildListView(List<Product> products) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: products.length,
      itemBuilder: (context, index) {
        return ListProductCard(
          product: products[index],
          onTap: () => _showProductDetail(context, products[index]),
          onAddToCart: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    Text('${products[index].name} ditambahkan ke keranjang'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          },
        );
      },
    );
  }

  void _showProductDetail(BuildContext context, Product product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ProductDetailSheet(product: product),
    );
  }
}

// Product Detail Bottom Sheet
class ProductDetailSheet extends StatelessWidget {
  final Product product;

  const ProductDetailSheet({Key? key, required this.product}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final freshnessColor =
        FreshnessHelper.getFreshnessColor(product.freshnessPercentage);
    final freshnessDescription =
        FreshnessHelper.getFreshnessDescription(product.freshnessPercentage);

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product Image
                  Container(
                    height: 250,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      image: DecorationImage(
                        image: NetworkImage(
                          product.imageUrls.isNotEmpty
                              ? product.imageUrls[0]
                              : 'https://via.placeholder.com/350',
                        ),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Product Name and Store
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (product.storeName != null)
                    Text(
                      product.storeName!,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                  const SizedBox(height: 16),

                  // Freshness Section
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: FreshnessHelper.getFreshnessBackgroundColor(
                          product.freshnessPercentage),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: freshnessColor.withOpacity(0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              FreshnessHelper.getFreshnessIcon(
                                  product.freshnessPercentage),
                              color: freshnessColor,
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Status Kesegaran',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: freshnessColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        FreshnessHelper.getFreshnessProgressBar(
                          product.freshnessPercentage,
                          height: 10,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          freshnessDescription,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Price and Stock
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Harga',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                          Text(
                            'Rp ${product.price.toStringAsFixed(0)}/${product.unit}',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Stok',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                          Text(
                            '${product.stock} ${product.unit}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Description
                  _buildSection('Deskripsi', product.description),

                  // Nutrition
                  if (product.nutrition != null)
                    _buildSection('Kandungan Gizi', product.nutrition!),

                  // Storage Tips
                  if (product.storageTips != null)
                    _buildSection('Tips Penyimpanan', product.storageTips!),
                ],
              ),
            ),
          ),

          // Bottom Action Buttons
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      // Add to cart logic
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content:
                              Text('${product.name} ditambahkan ke keranjang'),
                          backgroundColor: freshnessColor,
                        ),
                      );
                    },
                    icon: const Icon(Icons.shopping_cart_outlined),
                    label: const Text('Keranjang'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: freshnessColor,
                      side: BorderSide(color: freshnessColor),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      // Buy now logic
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Melanjutkan ke pembayaran...'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    },
                    icon: const Icon(Icons.shopping_bag),
                    label: const Text('Beli Sekarang'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: freshnessColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          content,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[700],
            height: 1.5,
          ),
        ),
      ],
    );
  }
}
