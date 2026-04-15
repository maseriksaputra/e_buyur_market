import '../../common/models/product_model.dart';
import 'entities/product_entity.dart';

extension ProductToEntity on Product {
  ProductEntity toEntity({String? forcedId}) {
    final e = ProductEntity()
      ..productId = forcedId ?? id
      ..name = name
      ..price = price
      ..unit = unit
      ..stock = stock
      ..category = category
      ..description = description.isEmpty ? null : description
      ..nutrition = nutrition
      ..storageTips = storageTips
      ..imageUrls = List.of(imageUrls)
      ..storeName = storeName
      ..sellerId = sellerId
      ..freshnessLabel = freshnessLabel
      ..freshnessPercentage = freshnessPercentage
      ..soldCount = soldCount
      ..createdAt = createdAt
      ..updatedAt = updatedAt;
    return e;
  }
}

extension ProductEntityToModel on ProductEntity {
  Product toModel() {
    return Product(
      id: productId,
      name: name,
      description: (description ?? ''),
      price: price,
      unit: unit,
      imageUrls: List.of(imageUrls),
      category: category,
      sellerId: sellerId ?? '',
      storeName: storeName,
      stock: stock,
      freshnessPercentage: freshnessPercentage,
      freshnessLabel: freshnessLabel,
      nutrition: nutrition,
      storageTips: storageTips,
      soldCount: soldCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
