import 'package:isar/isar.dart';
import '../local_init.dart';
import '../entities/product_entity.dart';
import '../mappers.dart';
import '../../../common/models/product_model.dart';

class ProductRepo {
  ProductRepo._();
  static final instance = ProductRepo._();

  Isar get _db => LocalDB.isar;

  Future<List<Product>> getAll() async {
    final items =
        await _db.productEntitys.where().sortByUpdatedAtDesc().findAll();
    return items.map((e) => e.toModel()).toList();
  }

  Future<Product?> getById(String id) async {
    final e =
        await _db.productEntitys.filter().productIdEqualTo(id).findFirst();
    return e?.toModel();
  }

  Future<void> upsert(Product p) async {
    await _db.writeTxn(() async {
      final col = _db.productEntitys;
      final existing = await col.filter().productIdEqualTo(p.id).findFirst();
      final entity = p.toEntity(forcedId: p.id);
      entity.id = existing?.id ?? Isar.autoIncrement;
      await col.put(entity);
    });
  }

  Future<void> deleteById(String id) async {
    await _db.writeTxn(() async {
      final col = _db.productEntitys;
      final existing = await col.filter().productIdEqualTo(id).findFirst();
      if (existing != null) {
        await col.delete(existing.id);
      }
    });
  }

  /// Simple client-side search by name and/or category.
  Future<List<Product>> search({String q = '', String category = 'all'}) async {
    final items = await _db.productEntitys.where().findAll();
    final queryLower = q.trim().toLowerCase();
    final filtered = items.where((e) {
      final matchesQ =
          queryLower.isEmpty || e.name.toLowerCase().contains(queryLower);
      final matchesCat = (category == 'all') || e.category == category;
      return matchesQ && matchesCat;
    }).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return filtered.map((e) => e.toModel()).toList();
  }

  /// Recommend products from the same category or the same seller, excluding itself.
  Future<List<Product>> recommendations(Product base, {int take = 10}) async {
    final results = await _db.productEntitys.where().findAll();
    final recs = results
        .where((e) =>
            e.productId != base.id &&
            (e.category == base.category || e.sellerId == base.sellerId))
        .take(take)
        .map((e) => e.toModel())
        .toList();
    return recs;
  }
}
