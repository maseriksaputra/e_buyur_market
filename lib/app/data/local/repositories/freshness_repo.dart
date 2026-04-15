import 'package:isar/isar.dart';
import '../local_init.dart';
import '../entities/freshness_entity.dart';

class FreshnessRepo {
  FreshnessRepo._();
  static final instance = FreshnessRepo._();
  Isar get _db => LocalDB.isar;

  Future<void> saveScore(FreshnessEntity e) async {
    await _db.writeTxn(() async {
      await _db.freshnessEntitys.put(e);
    });
  }

  Future<FreshnessEntity?> latestFor(String productId) async {
    final list = await _db.freshnessEntitys
        .filter()
        .productIdEqualTo(productId)
        .sortByComputedAtDesc()
        .findAll();
    return list.isEmpty ? null : list.first;
  }

  Future<List<FreshnessEntity>> history(String productId,
      {int limit = 50}) async {
    final list = await _db.freshnessEntitys
        .filter()
        .productIdEqualTo(productId)
        .sortByComputedAtDesc()
        .findAll();
    return list.take(limit).toList();
  }
}
