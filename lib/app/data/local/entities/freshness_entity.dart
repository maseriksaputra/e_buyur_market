import 'package:isar/isar.dart';
part 'freshness_entity.g.dart';

@collection
class FreshnessEntity {
  Id id = Isar.autoIncrement;
  late String productId;
  late double percentage;
  String label = "Segar";
  double? confidence;
  String? modelVersion;
  String? featuresJson;
  DateTime computedAt = DateTime.now();
}
