import 'package:isar/isar.dart';
part 'product_entity.g.dart';

/// Local cache for products (Isar)
@collection
class ProductEntity {
  Id id = Isar.autoIncrement;

  /// Business id (UUID/string) that matches Product.id on the app model
  late String productId;

  late String name;
  late double price;
  late String unit;
  late int stock;
  late String category;

  String? description;
  String? nutrition;
  String? storageTips;

  /// Local or remote urls. On mobile we save file paths.
  List<String> imageUrls = [];

  String? storeName;
  String? sellerId;

  /// ML score & label (0‒100)
  String freshnessLabel = "Segar";
  double freshnessPercentage = 80.0;

  int? soldCount;
  String? origin;
  String? harvestDate;
  String? expiryDate;

  List<String> benefits = [];

  String? idealTemp;
  String? idealHumidity;
  String? shelfLife;
  double? discount;

  DateTime createdAt = DateTime.now();
  DateTime updatedAt = DateTime.now();
}
