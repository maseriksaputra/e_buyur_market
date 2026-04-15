// lib/ml/vision_utils.dart
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// Hasil ROI cerdas (brightest region)
class SmartRoiResult {
  final Uint8List roi224;
  final int x, y, w, h;    // lokasi ROI pada gambar square sumber
  final double luma;       // 0..1 (rata-rata luminance ROI)
  SmartRoiResult({
    required this.roi224,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.luma,
  });
}

// ---------- helpers aman untuk pixel int 0xAARRGGBB ----------
int _rFromInt(int p) => (p >> 16) & 0xFF;
int _gFromInt(int p) => (p >> 8)  & 0xFF;
int _bFromInt(int p) => (p)       & 0xFF;

/// Hitung luma rata-rata gambar (0..1) — BT.601 approx: 0.299R + 0.587G + 0.114B
double meanLuma(img.Image im, {int stride = 2}) {
  final int w = im.width, h = im.height;
  double sum = 0.0;
  int cnt = 0;

  for (int y = 0; y < h; y += stride) {
    for (int x = 0; x < w; x += stride) {
      // Penting: gunakan Object? agar type test bisa promote
      Object? pxAny = im.getPixel(x, y);

      int r, g, b;
      if (pxAny is int) {
        // image 3.x path (0xAARRGGBB)
        r = _rFromInt(pxAny);
        g = _gFromInt(pxAny);
        b = _bFromInt(pxAny);
      } else {
        // image 4.x path: objek dengan field r/g/b
        final dyn = pxAny as dynamic;
        r = (dyn.r as num).toInt();
        g = (dyn.g as num).toInt();
        b = (dyn.b as num).toInt();
      }

      final y601 = 0.299 * r + 0.587 * g + 0.114 * b;
      sum += y601;
      cnt++;
    }
  }
  if (cnt == 0) return 0.0;
  return (sum / cnt) / 255.0;
}

/// Pilih ROI paling terang dari grid NxN pada center-square gambar,
/// lalu resize ke 224 dan kembalikan JPEG bytes.
SmartRoiResult pickBrightestRoi224(
  Uint8List jpeg, {
  int grid = 3,
  int roiSize = 224,
  int sampleStride = 2,
}) {
  final src = img.decodeImage(jpeg);
  if (src == null) {
    throw Exception('Gambar tidak valid');
  }

  // Center-square
  final int s = math.min(src.width, src.height);
  final int cx = ((src.width - s) / 2).round();
  final int cy = ((src.height - s) / 2).round();
  final img.Image sq = img.copyCrop(src, x: cx, y: cy, width: s, height: s);

  // Grid NxN: pilih tile dengan luma rata-rata tertinggi
  final int tile = (s / grid).floor().clamp(1, s);
  double bestLuma = -1.0;
  int bx = 0, by = 0, bw = tile, bh = tile;

  for (int gy = 0; gy < grid; gy++) {
    for (int gx = 0; gx < grid; gx++) {
      final int x = (gx * tile).clamp(0, s - 1);
      final int y = (gy * tile).clamp(0, s - 1);
      final int w = (x + tile <= s) ? tile : (s - x);
      final int h = (y + tile <= s) ? tile : (s - y);
      final img.Image tileIm = img.copyCrop(sq, x: x, y: y, width: w, height: h);
      final double l = meanLuma(tileIm, stride: sampleStride);
      if (l > bestLuma) {
        bestLuma = l;
        bx = x; by = y; bw = w; bh = h;
      }
    }
  }

  // Crop terbaik → resize → JPEG
  final img.Image roi = img.copyResize(
    img.copyCrop(sq, x: bx, y: by, width: bw, height: bh),
    width: roiSize,
    height: roiSize,
    interpolation: img.Interpolation.cubic,
  );
  final bytes = Uint8List.fromList(img.encodeJpg(roi, quality: 92));

  return SmartRoiResult(
    roi224: bytes,
    x: bx, y: by, w: bw, h: bh,
    luma: math.max(0.0, math.min(1.0, bestLuma)),
  );
}
