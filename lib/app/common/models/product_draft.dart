// lib/app/common/models/product_draft.dart
import 'dart:typed_data';

/// Draft produk yang diisi dari hasil scan + input penjual.
/// Dipakai untuk mem‐pre-fill form “Buat Produk dari Hasil Scan”.
class ProductDraft {
  String name;
  String category;
  String unit;
  double price;
  int stock;
  String description;

  double? freshnessScore; // 0..100
  String? freshnessLabel; // "Sangat Layak", dst
  String? nutrition; // teks bebas
  String? storageTips; // teks bebas

  /// Untuk Flutter Web: bytes + nama file akan di-upload
  Uint8List? imageBytes;
  String? imageFilename;

  /// Simpan sebagai String supaya gampang dibanding dengan Product.sellerId
  String? sellerId;

  ProductDraft({
    this.name = '',
    this.category = '',
    this.unit = 'kg',
    this.price = 0,
    this.stock = 0,
    this.description = '',
    this.freshnessScore,
    this.freshnessLabel,
    this.nutrition,
    this.storageTips,
    this.imageBytes,
    this.imageFilename,
    this.sellerId,
  });
}
