import 'package:isar/isar.dart';
import '../local_init.dart';
import '../entities/user_entity.dart';

class UserRepo {
  UserRepo._();
  static final instance = UserRepo._();
  Isar get _db => LocalDB.isar;

  Future<void> upsert(UserEntity u) async {
    final existing =
        await _db.userEntitys.filter().userIdEqualTo(u.userId).findFirst();
    u.id = existing?.id ?? Isar.autoIncrement;
    await _db.writeTxn(() async {
      await _db.userEntitys.put(u);
    });
  }

  Future<UserEntity?> getById(String userId) async {
    return await _db.userEntitys.filter().userIdEqualTo(userId).findFirst();
  }

  Future<List<UserEntity>> byRole(String role) async {
    return await _db.userEntitys.filter().roleEqualTo(role).findAll();
  }
}
