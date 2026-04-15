// lib/app/presentation/pages/search_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/product_provider.dart';
import '../../common/widgets/product_card.dart';
import '../../common/models/product_model.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({Key? key}) : super(key: key);

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'Semua';
  bool _isGridView = true;

  final List<String> _categories = [
    'Semua',
    'Sayuran',
    'Buah',
    'Organik',
    'Diskon',
  ];

  final List<String> _popularSearches = [
    'Apel',
    'Pisang',
    'Wortel',
    'Tomat',
    'Jeruk',
    'Bayam',
    'Brokoli',
    'Kentang',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Product> _getFilteredProducts(ProductProvider provider) {
    List<Product> products = provider.products;

    // Filter by search query
    if (_searchController.text.isNotEmpty) {
      products = products.where((product) {
        final searchLower = _searchController.text.toLowerCase();
        return product.name.toLowerCase().contains(searchLower) ||
            (product.storeName?.toLowerCase().contains(searchLower) ?? false) ||
            product.description.toLowerCase().contains(searchLower);
      }).toList();
    }

    // Filter by category
    switch (_selectedCategory) {
      case 'Sayuran':
        products = products.where((p) => p.category == 'Sayuran').toList();
        break;
      case 'Buah':
        products = products.where((p) => p.category == 'Buah').toList();
        break;
      case 'Organik':
        products = products
            .where((p) => p.description.toLowerCase().contains('organik'))
            .toList();
        break;
      case 'Diskon':
        products = products.where((p) => p.freshnessPercentage < 60).toList();
        break;
    }

    return products;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Column(
          children: [
            // Custom App Bar with Search
            Container(
              color: Colors.white,
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: const Icon(
                            Icons.arrow_back,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Cari Produk',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(
                            _isGridView ? Icons.view_list : Icons.grid_view,
                            color: const Color(0xFF1A1A1A),
                          ),
                          onPressed: () {
                            setState(() {
                              _isGridView = !_isGridView;
                            });
                          },
                        ),
                      ],
                    ),
                  ),

                  // Search Bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: Row(
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(left: 16),
                            child: Icon(
                              Icons.search,
                              color: Color(0xFF9E9E9E),
                              size: 20,
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              onChanged: (value) => setState(() {}),
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF1A1A1A),
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Cari buah dan sayur segar...',
                                hintStyle: TextStyle(
                                  color: Color(0xFF9E9E9E),
                                  fontSize: 14,
                                ),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                          if (_searchController.text.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _searchController.clear();
                                });
                              },
                              child: const Padding(
                                padding: EdgeInsets.only(right: 16),
                                child: Icon(
                                  Icons.close_rounded,
                                  color: Color(0xFF9E9E9E),
                                  size: 20,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Categories
                  Container(
                    height: 40,
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: Color(0xFFE0E0E0),
                          width: 1,
                        ),
                      ),
                    ),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _categories.length,
                      itemBuilder: (context, index) {
                        final category = _categories[index];
                        final isSelected = _selectedCategory == category;

                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 6),
                          child: Material(
                            color: isSelected
                                ? Theme.of(context).primaryColor
                                : const Color(0xFFF5F5F5),
                            borderRadius: BorderRadius.circular(20),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () {
                                setState(() {
                                  _selectedCategory = category;
                                });
                              },
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                alignment: Alignment.center,
                                child: Text(
                                  category,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: isSelected
                                        ? Colors.white
                                        : const Color(0xFF616161),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: Consumer<ProductProvider>(
                builder: (context, provider, child) {
                  final filteredProducts = _getFilteredProducts(provider);

                  // Show search results
                  if (_searchController.text.isNotEmpty) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Results header
                        Container(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            '${filteredProducts.length} hasil untuk "${_searchController.text}"',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF757575),
                            ),
                          ),
                        ),

                        // Products or No Results
                        Expanded(
                          child: filteredProducts.isEmpty
                              ? _buildNoResults()
                              : _buildProductsGrid(filteredProducts),
                        ),
                      ],
                    );
                  }

                  // Show default content when not searching
                  return SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Popular Searches
                        if (_searchController.text.isEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 20, 16, 12),
                            child: Text(
                              'Pencarian Populer',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _popularSearches.map((term) {
                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _searchController.text = term;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF5F5F5),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Text(
                                      term,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF616161),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],

                        // Recommended Products
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
                          child: Text(
                            'Rekomendasi Produk',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                        ),

                        // Products Grid
                        _buildProductsGrid(filteredProducts),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          const Text(
            'Tidak ada hasil',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Coba kata kunci lain atau jelajahi kategori yang tersedia',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _searchController.clear();
                _selectedCategory = 'Semua';
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text(
              'Reset Pencarian',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductsGrid(List<Product> products) {
    if (_isGridView) {
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        shrinkWrap: _searchController.text.isEmpty,
        physics: _searchController.text.isEmpty
            ? const NeverScrollableScrollPhysics()
            : const AlwaysScrollableScrollPhysics(),
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
            onTap: () {
              // Navigate to product detail
              Navigator.pushNamed(
                context,
                '/product-detail',
                arguments: products[index],
              );
            },
            onAddToCart: () {
              // Add to cart logic
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content:
                      Text('${products[index].name} ditambahkan ke keranjang'),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 2),
                  action: SnackBarAction(
                    label: 'LIHAT',
                    textColor: Colors.white,
                    onPressed: () {
                      // Navigate to cart
                      Navigator.pushNamed(context, '/cart');
                    },
                  ),
                ),
              );
            },
          );
        },
      );
    } else {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        shrinkWrap: _searchController.text.isEmpty,
        physics: _searchController.text.isEmpty
            ? const NeverScrollableScrollPhysics()
            : const AlwaysScrollableScrollPhysics(),
        itemCount: products.length,
        itemBuilder: (context, index) {
          return ListProductCard(
            product: products[index],
            onTap: () {
              // Navigate to product detail
              Navigator.pushNamed(
                context,
                '/product-detail',
                arguments: products[index],
              );
            },
            onAddToCart: () {
              // Add to cart logic
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content:
                      Text('${products[index].name} ditambahkan ke keranjang'),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 2),
                  action: SnackBarAction(
                    label: 'LIHAT',
                    textColor: Colors.white,
                    onPressed: () {
                      // Navigate to cart
                      Navigator.pushNamed(context, '/cart');
                    },
                  ),
                ),
              );
            },
          );
        },
      );
    }
  }
}
