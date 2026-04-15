// lib/ml/suitability_service.dart
import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;
import 'package:image/image.dart' as img;

/// Service sederhana untuk inferensi TFLite.
/// - Mendukung dua cara input: fitur numerik & gambar (bytes)
/// - Tidak bergantung pada tflite_flutter_helper (hindari konflik versi)
class SuitabilityService {
  tfl.Interpreter? _interpreter;
  static final SuitabilityService _i = SuitabilityService._internal();
  factory SuitabilityService() => _i;
  SuitabilityService._internal();

  Future<void> init({String assetPath = 'assets/ml/ebuyur_multitask_fp16.tflite'}) async {
    _interpreter ??= await tfl.Interpreter.fromAsset(assetPath);
  }

  /// Jalankan inferensi dari fitur numerik (urutan sesuai model).
  /// Mengembalikan 0..100 (dibulatkan).
  Future<int> computePercent(List<double> features) async {
    if (_interpreter == null) await init();

    // Bentuk input 1xN
    final input = [features];

    // Siapkan output 1x1 (hindari List.filled + reuse reference)
    final output = List.generate(1, (_) => List.generate(1, (_) => 0.0));

    _interpreter!.run(input, output);
    final score01 =
        (output[0][0] is num) ? (output[0][0] as num).toDouble() : 0.0;
    return (score01 * 100).clamp(0.0, 100.0).round();
  }

  /// Jalankan inferensi dari gambar bytes (RGB).
  /// - `inputSize`: sisi gambar model (default 224)
  /// - `mean` & `std`: normalisasi per channel (default 127.5/127.5 → [-1,1])
  /// Catatan:
  /// - Asumsi model menerima float32 [1, H, W, 3] dengan skala (x-mean)/std.
  ///   Jika model kamu quantized (uint8) atau skala lain, sesuaikan bagian normalisasi.
  Future<int> computePercentFromImage(
    Uint8List imageBytes, {
    int inputSize = 224,
    List<double> mean = const [127.5, 127.5, 127.5],
    List<double> std = const [127.5, 127.5, 127.5],
  }) async {
    if (_interpreter == null) await init();

    // 1) Decode
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      throw StateError('Gagal decode gambar');
    }

    // 2) Resize ke inputSize x inputSize
    final resized = img.copyResize(
      decoded,
      width: inputSize,
      height: inputSize,
      // Jika 'average' tidak ada di versi image kamu, ganti ke linear:
      interpolation: img.Interpolation.linear,
    );

    // 3) Bentuk tensor [1, H, W, 3] bertipe double
    final input = List.generate(
      1,
      (_) => List.generate(
        inputSize,
        (y) => List.generate(
          inputSize,
          (x) {
            // ✅ API image baru: getPixel() -> Pixel dengan kanal r/g/b
            final px = resized.getPixel(x, y);
            final r = px.r.toDouble();
            final g = px.g.toDouble();
            final b = px.b.toDouble();

            // Normalisasi: (val - mean) / std  → default kira-kira [-1, +1]
            final nr = (r - mean[0]) / std[0];
            final ng = (g - mean[1]) / std[1];
            final nb = (b - mean[2]) / std[2];
            return <double>[nr, ng, nb];
          },
        ),
      ),
    );

    // 4) Output 1x1
    final output = List.generate(1, (_) => List.generate(1, (_) => 0.0));

    // 5) Run
    _interpreter!.run(input, output);

    // 6) Ambil skor 0..1 → 0..100
    final score01 =
        (output[0][0] is num) ? (output[0][0] as num).toDouble() : 0.0;
    return (score01 * 100).clamp(0.0, 100.0).round();
  }

  /// Tutup interpreter (sinkron).
  Future<void> close() async {
    _interpreter?.close(); // ✅ jangan di-await; method ini sinkron
    _interpreter = null;
  }
}
