import 'package:isar/isar.dart';
part 'user_entity.g.dart';

/// Local user profile (buyer/seller)
@collection
class UserEntity {
  Id id = Isar.autoIncrement;

  /// Business id (string) that matches User.id or external auth id
  late String userId;

  /// 'buyer' | 'seller'
  late String role;

  late String name;
  String? email;
  String? phone;
  String? address;

  double? lat;
  double? lng;

  String? avatarUrl;
  String? storeName;
  String? storeBannerUrl;

  double rating = 4.8;

  DateTime createdAt = DateTime.now();
  DateTime updatedAt = DateTime.now();
}
