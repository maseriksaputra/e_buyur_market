import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart' as pp;
import 'entities/product_entity.dart';
import 'entities/user_entity.dart';
import 'entities/freshness_entity.dart';

class LocalDB {
  static Isar? _isar;
  static Isar get isar {
    final db = _isar;
    assert(db != null,
        'LocalDB not initialized. Call LocalDB.ensureInitialized() first.');
    return db!;
  }

  static Future<void> ensureInitialized() async {
    if (_isar != null) return;
    final dir = await pp.getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      schemas: [ProductEntitySchema, UserEntitySchema, FreshnessEntitySchema],
      directory: dir.path,
      inspector: false,
    );
  }
}
