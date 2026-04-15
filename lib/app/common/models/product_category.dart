// lib/app/common/models/product_category.dart
enum ProductCategory { buah, sayur }

extension ProductCategoryX on ProductCategory {
  String get slug => switch (this) {
        ProductCategory.buah => 'buah',
        ProductCategory.sayur => 'sayur',
      };

  String get label => switch (this) {
        ProductCategory.buah => 'Buah',
        ProductCategory.sayur => 'Sayur',
      };

  static ProductCategory? fromAny(dynamic v) {
    final s = (v ?? '').toString().trim().toLowerCase();
    if (s == 'buah') return ProductCategory.buah;
    if (s == 'sayur') return ProductCategory.sayur;
    return null;
  }
}
