import 'product_model.dart';

// Field opsional untuk buah/sayur. Aman walau model belum punya field ini.
extension ProductCompat on Product {
  String? get origin => null; // contoh: "Bandung"
  String? get harvestDate => null; // contoh: "2 hari yang lalu"
  String? get expiryDate => null; // contoh: "5 hari lagi"
  List<String>? get benefits => null; // contoh: ["Tinggi Vit C", "Antioksidan"]
  String? get idealTemp => null; // contoh: "4-10"
  String? get idealHumidity => null; // contoh: "85-95"
  String? get shelfLife => null; // contoh: "3-5"
  double? get discount => null; // contoh: 10 (persen)
}
