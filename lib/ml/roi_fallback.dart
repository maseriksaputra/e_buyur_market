// lib/ml/roi_fallback.dart
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as im;

// ⬇️ PENTING: pakai import relative, bukan `package:your_app/...`
import 'yolo_detector_service.dart';

/// Aktifkan YOLO ROI saat run:
/// flutter run --dart-define=USE_YOLO_ROI=true
const bool kUseYoloRoi = bool.fromEnvironment('USE_YOLO_ROI', defaultValue: false);

/// Selalu return JPEG 224x224 untuk pipeline kualitas.
/// - Jika YOLO aktif & sukses → pakai ROI dari YOLO
/// - Jika gagal / dimatikan → fallback center-crop 224
Future<Uint8List> buildRoi224WithFallback(
  Uint8List jpeg, {
  int threads = 2,
}) async {
  if (kUseYoloRoi) {
    try {
      final yolo = await YoloDetectorService.load(threads: threads);
      final res  = await yolo.detectBestRoi224(jpeg);
      await yolo.dispose();
      if (res != null) {
        return res.roi224;
      }
    } catch (_) {
      // diam aja → lanjut ke fallback
    }
  }

  // Fallback: center-crop → 224
  final src = im.decodeImage(jpeg);
  if (src == null) {
    throw Exception('Gambar tidak valid');
  }
  final s  = math.min(src.width, src.height);
  final cx = ((src.width - s) / 2).round();
  final cy = ((src.height - s) / 2).round();
  final sq = im.copyCrop(src, x: cx, y: cy, width: s, height: s);
  final roi = im.copyResize(
    sq,
    width: 224,
    height: 224,
    interpolation: im.Interpolation.cubic,
  );
  return Uint8List.fromList(im.encodeJpg(roi, quality: 92));
}
