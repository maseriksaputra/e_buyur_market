// lib/ml/hybrid_ai_service.dart
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:convert'; // jsonDecode
import 'package:flutter/foundation.dart' show kDebugMode; // print debug
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as im;
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;

// ====== Tambahan integrasi (poin 4) ======
import 'vision_utils.dart' as vu;        // meanLuma(), pickBrightestRoi224()
import 'calibration.dart';               // shouldForceLlmByRoi(), fuseSuitability()
import 'config.dart';                    // MlConfig.yoloMinConf

// ---------- Model outputs ----------
class YoloDet {
  final String label;
  final double conf; // 0..1
  YoloDet(this.label, this.conf);
  @override
  String toString() => '$label (${(conf * 100).toStringAsFixed(1)}%)';
}

// Helpers baca channel (menerima im.Pixel atau int)
double _rf(dynamic p) {
  if (p is im.Pixel) return p.r.toDouble();
  if (p is int) return ((p >> 16) & 0xFF).toDouble();
  return 0.0;
}
double _gf(dynamic p) {
  if (p is im.Pixel) return p.g.toDouble();
  if (p is int) return ((p >> 8) & 0xFF).toDouble();
  return 0.0;
}
double _bf(dynamic p) {
  if (p is im.Pixel) return p.b.toDouble();
  if (p is int) return (p & 0xFF).toDouble();
  return 0.0;
}

// ================= QUALITY HEAD =================
class _QualityHead {
  final tfl.Interpreter _itp;
  final int _size;
  final List<double> _mean;
  final List<double> _std;

  _QualityHead(
    this._itp, {
    required int inputSize,
    required List<double> mean,
    required List<double> std,
  })  : _size = inputSize,
        _mean = mean,
        _std = std;

  /// Loader yang membaca interpreter & konfigurasi normalisasi dari JSON
  static Future<_QualityHead> fromAsset(String modelPath, String cfgPath) async {
    final itp = await _loadInterpreter(modelPath);

    // Baca config
    final raw = await rootBundle.loadString(cfgPath);
    final cfg = Map<String, dynamic>.from(jsonDecode(raw) as Map);

    final size = (cfg['input_size'] as num?)?.toInt() ?? 224;
    final mean = (cfg['mean'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        const [127.5, 127.5, 127.5];
    final std = (cfg['std'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        const [127.5, 127.5, 127.5];

    return _QualityHead(itp, inputSize: size, mean: mean, std: std);
  }

  // ---------- JPEG/PNG ----------
  Future<int> percentFromBytes(Uint8List jpegBytes) async {
    final img = im.decodeImage(jpegBytes);
    if (img == null) return 0;
    final rgb = im.copyResize(
      img,
      width: _size,
      height: _size,
      interpolation: im.Interpolation.linear,
    );
    return _runScalar01(rgb);
  }

  // ---------- Kamera YUV420 ----------
  Future<int> percentFromYuv420({
    required int width,
    required int height,
    required Uint8List planeY,
    required Uint8List planeU,
    required Uint8List planeV,
    required int strideY,
    required int strideU,
    required int strideV,
    required int pixelStrideU,
    required int pixelStrideV,
  }) async {
    final rgb = _imFromYuv420(
      width: width,
      height: height,
      y: planeY,
      u: planeU,
      v: planeV,
      rowStrideY: strideY,
      rowStrideU: strideU,
      rowStrideV: strideV,
      pixelStrideU: pixelStrideU,
      pixelStrideV: pixelStrideV,
    );
    final resized = im.copyResize(
      rgb,
      width: _size,
      height: _size,
      interpolation: im.Interpolation.linear,
    );
    return _runScalar01(resized);
  }

  /// Jalankan inferensi: normalisasi [-1,1] pakai (x-mean)/std, ambil out-0 elemen pertama sebagai skalar 0..1
  Future<int> _runScalar01(im.Image rgb) async {
    // (x - mean)/std  → umumnya ke [-1,1] bila mean=std=127.5
    final input = List.generate(_size, (y) {
      return List.generate(_size, (x) {
        final px = rgb.getPixel(x, y);
        final r = (_rf(px) - _mean[0]) / _std[0];
        final g = (_gf(px) - _mean[1]) / _std[1];
        final b = (_bf(px) - _mean[2]) / _std[2];
        return [r, g, b];
      });
    });
    final wrapped = [input];

    final outs = <int, Object>{};
    final shapes = <List<int>>[];
    for (var i = 0; i < _itp.getOutputTensors().length; i++) {
      final shape = _itp.getOutputTensors()[i].shape;
      shapes.add(shape);
      outs[i] = _zeroListForShape(shape);
    }

    _itp.resizeInputTensor(0, [1, _size, _size, 3]);
    _itp.allocateTensors();
    _itp.runForMultipleInputs([wrapped], outs);

    // Ambil out-0 elemen pertama sebagai skalar 0..1
    double scalar = 0.0;
    try {
      dynamic o = outs[0];
      // flatten sampai ketemu angka
      while (o is List && o.isNotEmpty) {
        o = o[0];
      }
      if (o is num) scalar = o.toDouble();
    } catch (_) {
      // noop
    }

    if (kDebugMode) {
      // ignore: avoid_print
      print('[QUALITY] out shapes=$shapes scalar0=${scalar.toStringAsFixed(4)}');
    }

    final pct = (scalar.clamp(0.0, 1.0) * 100).round();
    return pct < 0 ? 0 : (pct > 100 ? 100 : pct);
  }
}

// ---------- YOLO HEAD ----------
class _YoloHead {
  final tfl.Interpreter _itp;
  final List<String> _labels;
  final double confThr;
  _YoloHead(this._itp, this._labels, {this.confThr = 0.25});

  double _sigmoid(num x) => 1.0 / (1.0 + math.exp(-x.toDouble()));

  Future<List<YoloDet>> detectFromBytes(Uint8List jpegBytes, {int topK = 1}) async {
    final img = im.decodeImage(jpegBytes);
    if (img == null) return const [];
    return _detectFromImage(img, topK: topK);
  }

  Future<List<YoloDet>> detectFromYuv420({
    required int width,
    required int height,
    required Uint8List planeY,
    required Uint8List planeU,
    required Uint8List planeV,
    required int strideY,
    required int strideU,
    required int strideV,
    required int pixelStrideU,
    required int pixelStrideV,
    int topK = 1,
  }) async {
    final rgb = _imFromYuv420(
      width: width,
      height: height,
      y: planeY,
      u: planeU,
      v: planeV,
      rowStrideY: strideY,
      rowStrideU: strideU,
      rowStrideV: strideV,
      pixelStrideU: pixelStrideU,
      pixelStrideV: pixelStrideV,
    );
    return _detectFromImage(rgb, topK: topK);
  }

  Future<List<YoloDet>> _detectFromImage(im.Image img, {int topK = 1}) async {
    final inShape = _itp.getInputTensors().first.shape; // [1,H,W,3] umumnya
    final h = inShape.length >= 4 ? inShape[1] : 320;
    final w = inShape.length >= 4 ? inShape[2] : 320;

    final rgb = im.copyResize(img, width: w, height: h, interpolation: im.Interpolation.linear);

    final input = List.generate(h, (y) {
      return List.generate(w, (x) {
        final px = rgb.getPixel(x, y);
        return [_rf(px) / 255.0, _gf(px) / 255.0, _bf(px) / 255.0];
      });
    });
    final wrapped = [input];

    final outs = <int, Object>{};
    final shapes = <List<int>>[];
    for (var i = 0; i < _itp.getOutputTensors().length; i++) {
      final shape = _itp.getOutputTensors()[i].shape;
      shapes.add(shape);
      outs[i] = _zeroListForShape(shape);
    }

    _itp.resizeInputTensor(0, [1, h, w, 3]);
    _itp.allocateTensors();
    _itp.runForMultipleInputs([wrapped], outs);

    final nClass = _labels.length;

    // Case A: Single output [1, N, 5+K]
    if (outs.length == 1) {
      final shape = shapes.first;
      if (shape.length == 3 && shape[0] == 1 && shape[2] >= 5) {
        final arr = outs.values.first as List; // [1][N][5+K]
        final dets = _decodeSingleNx(arr[0] as List, nClass, topK: topK);
        return dets;
      }
    }

    // Case B: Multi-head [1, gh, gw, A*(5+K)]
    final combined = <YoloDet>[];
    outs.forEach((_, v) {
      final fm = v as List; // [1][gh][gw][last]
      final gh = (fm[0] as List).length;
      final gw = ((fm[0] as List)[0] as List).length;
      final lastVec = (((fm[0] as List)[0] as List)[0]) as List; // length = A*(5+K)
      final last = lastVec.length;
      final a = (last / (5 + nClass)).floor();
      if (a <= 0) return;

      for (int y = 0; y < gh; y++) {
        final row = (fm[0] as List)[y] as List;
        for (int x = 0; x < gw; x++) {
          final cell = row[x] as List; // length = A*(5+K)
          for (int i = 0; i < a; i++) {
            final off = i * (5 + nClass);
            final obj = _sigmoid(cell[off + 4] as num);
            if (obj < confThr) continue;

            double bestP = 0.0;
            int bestIdx = 0;
            for (int c = 0; c < nClass && off + 5 + c < cell.length; c++) {
              final p = _sigmoid(cell[off + 5 + c] as num);
              if (p > bestP) {
                bestP = p;
                bestIdx = c;
              }
            }
            final conf = obj * bestP;
            if (conf >= confThr) {
              final label = (bestIdx >= 0 && bestIdx < _labels.length)
                  ? _labels[bestIdx]
                  : 'class_$bestIdx';
              combined.add(YoloDet(label, conf));
            }
          }
        }
      }
    });

    if (combined.isEmpty) return const [];
    combined.sort((a, b) => b.conf.compareTo(a.conf));
    return combined.take(topK).toList();
  }

  List<YoloDet> _decodeSingleNx(List nx, int nClass, {int topK = 1}) {
    final out = <YoloDet>[];
    for (final row in nx) {
      final r = row as List;
      if (r.length < 5) continue;
      final obj = _sigmoid(r[4] as num);
      if (obj < confThr) continue;

      double bestP = 0.0;
      int bestIdx = 0;
      const clsStart = 5;
      for (int c = 0; c < nClass && clsStart + c < r.length; c++) {
        final p = _sigmoid(r[clsStart + c] as num);
        if (p > bestP) {
          bestP = p;
          bestIdx = c;
        }
      }
      final conf = obj * bestP;
      if (conf >= confThr) {
        final label = (bestIdx >= 0 && bestIdx < _labels.length)
            ? _labels[bestIdx]
            : 'class_$bestIdx';
        out.add(YoloDet(label, conf));
      }
    }
    if (out.isEmpty) return out;
    out.sort((a, b) => b.conf.compareTo(a.conf));
    return out.take(topK).toList();
  }
}

// ---------- Fasad lama (biarkan) ----------
class HybridAI {
  final _QualityHead quality;
  final _YoloHead yolo;
  HybridAI._(this.quality, this.yolo);

  static Future<HybridAI> load() async {
    final labels = await _loadLabels('assets/ml/labels_fruit.txt');

    // QUALITY: baca model + config normalisasi dari JSON
    final qHead = await _QualityHead.fromAsset(
      'assets/ml/ebuyur_multitask_fp16.tflite',
      'assets/ml/quality_config.json',
    );

    // YOLO tetap diload (meski tidak dipakai di halaman tertentu)
    final itpY = await _loadInterpreter('assets/ml/best_float16.tflite');

    return HybridAI._(
      qHead,
      _YoloHead(itpY, labels, confThr: 0.25),
    );
  }

  Future<Map<String, dynamic>> runSelfTest() async {
    final bytes =
        await rootBundle.load('assets/test/selftest_apple.jpg').catchError((_) => null);
    if (bytes == null) return {'error': 'no selftest image'};
    final jpg = bytes.buffer.asUint8List();
    final q = await quality.percentFromBytes(jpg);
    final dets = await yolo.detectFromBytes(jpg, topK: 1);
    return {
      'quality.percent': q,
      'yolo.det': dets.isEmpty ? 'none' : dets.first.toString(),
    };
  }
}

// ---------- Utils ----------
Future<tfl.Interpreter> _loadInterpreter(String assetPath) async {
  final opt = tfl.InterpreterOptions()..threads = 2;
  return tfl.Interpreter.fromAsset(assetPath, options: opt);
}

Future<List<String>> _loadLabels(String path) async {
  final raw = await rootBundle.loadString(path);
  return raw
      .split(RegExp(r'\r?\n'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

Object _zeroListForShape(List<int> shape) {
  Object build(int dim) {
    final len = shape[dim];
    if (dim == shape.length - 1) {
      return List<double>.filled(len, 0.0, growable: false);
    } else {
      return List.generate(len, (_) => build(dim + 1), growable: false);
    }
  }
  return build(0);
}

// ---------- YUV420 → im.Image (RGB) ----------
im.Image _imFromYuv420({
  required int width,
  required int height,
  required Uint8List y,
  required Uint8List u,
  required Uint8List v,
  required int rowStrideY,
  required int rowStrideU,
  required int rowStrideV,
  required int pixelStrideU,
  required int pixelStrideV,
}) {
  final img = im.Image(width: width, height: height); // RGBA8888
  for (int yy = 0; yy < height; yy++) {
    final pY = yy * rowStrideY;
    final pUrow = (yy >> 1) * rowStrideU;
    final pVrow = (yy >> 1) * rowStrideV;
    for (int xx = 0; xx < width; xx++) {
      final yVal = y[pY + xx];
      final uIndex = pUrow + (xx >> 1) * pixelStrideU;
      final vIndex = pVrow + (xx >> 1) * pixelStrideV;
      final uVal = u[uIndex];
      final vVal = v[vIndex];

      final yyf = yVal.toDouble();
      final uf = (uVal - 128).toDouble();
      final vf = (vVal - 128).toDouble();

      double r = yyf + 1.402 * vf;
      double g = yyf - 0.344136 * uf - 0.714136 * vf;
      double b = yyf + 1.772 * uf;

      final ri = r.clamp(0, 255).toInt();
      final gi = g.clamp(0, 255).toInt();
      final bi = b.clamp(0, 255).toInt();

      img.setPixelRgb(xx, yy, ri, gi, bi);
    }
  }
  return img;
}

// ===================================================================
// ====================  HYBRID AI SERVICE (baru)  ====================
// ===================================================================

typedef RoiBuilder = Future<Uint8List> Function(Uint8List fullJpeg);

// ✅ Callback untuk memanggil API server-mu (mengganti AiApiService.instance)
typedef ValidateImageFn = Future<Map<String, dynamic>?> Function(
  Uint8List imageBytes, {
  required String bearerToken,
});

class HybridAiService {
  /// Analisis satu pintu:
  /// - Tentukan ROI: YOLO yakin → ROI YOLO; kalau tidak → ROI cerdas (brightest)
  /// - Hitung luma ROI & FULL, skor lokal (TFLite),
  /// - Putuskan gambar untuk LLM (paksa FULL jika ROI gelap),
  /// - Fusing hasil lokal + LLM via calibration.
  Future<Map<String, dynamic>> analyze({
    required Uint8List fullJpeg,
    required String? bearerToken,
    double? yoloConf,
    required Future<double> Function(Uint8List roi224) inferLocalPercent,
    RoiBuilder? buildRoiFromYoloPadded224, // opsional; kalau null → pakai smart ROI
    ValidateImageFn? validateImageCall,     // ⬅️ injeksi fungsi panggil server
  }) async {
    // ---------------- 1) ROI & luma ----------------
    final bool yoloOk = (yoloConf ?? 0) >= MlConfig.yoloMinConf;

    // ROI 224
    late Uint8List roi224;
    // Luma
    double fullLuma = _lumaFromJpeg(fullJpeg);
    double roiLuma;

    if (yoloOk && buildRoiFromYoloPadded224 != null) {
      // Pakai ROI dari YOLO (builder milikmu)
      roi224 = await buildRoiFromYoloPadded224(fullJpeg);
      roiLuma = _lumaFromJpeg(roi224);
    } else {
      // Pakai ROI cerdas (brightest)
      final smart = vu.pickBrightestRoi224(fullJpeg);
      roi224 = smart.roi224;
      roiLuma = _lumaFromJpeg(roi224);
    }

    // ---------------- 2) Skor lokal (TFLite) ----------------
    final localPct = await inferLocalPercent(roi224); // 0..100 (double/num)

    // ---------------- 3) Keputusan LLM (force FULL jika ROI gelap) ----------------
    bool roiForce = false;
    try {
      roiForce = shouldForceLlmByRoi(roiLuma: roiLuma, fullLuma: fullLuma);
    } catch (_) {
      roiForce = false;
    }

    // ---------------- 4) Panggil LLM (opsional) ----------------
    double? llmPct;
    double llmConf = 0.0;
    if (bearerToken != null && validateImageCall != null) {
      final imageForLlm = roiForce ? fullJpeg : roi224;
      try {
        final res = await validateImageCall(
          imageForLlm,
          bearerToken: bearerToken,
        );
        llmPct = (res?['suitabilityPercent'] as num?)?.toDouble();
        llmConf = (res?['confidence'] as num?)?.toDouble() ?? 0.0;
      } catch (_) {
        // biarkan null
      }
    }

    // ---------------- 5) Fusing via calibration ----------------
    final fused = fuseSuitability(
      localPct: localPct,
      llmPct: llmPct,
      llmConf: llmConf,
      roiLuma: roiLuma,
      fullLuma: fullLuma,
      yoloConfident: yoloOk,
    );

    if (kDebugMode) {
      // ignore: avoid_print
      print('[HYBRID] local=$localPct llm=$llmPct conf=$llmConf '
            'roiLuma=${roiLuma.toStringAsFixed(3)} fullLuma=${fullLuma.toStringAsFixed(3)} '
            'yoloOk=$yoloOk roiForce=$roiForce '
            '=> final=${fused.finalPercent} reason=${fused.reason}');
    }

    return {
      'finalPercent': fused.finalPercent,
      'localPercent': localPct,
      'llmPercent': llmPct,
      'llmConf': llmConf,
      'roiLuma': roiLuma,
      'fullLuma': fullLuma,
      'llmTriggered': fused.llmTriggered,
      'llmForcedByRoi': fused.llmForcedByRoi,
      'reason': fused.reason,
    };
  }

  // ---- helper: luma dari JPEG (0..1) ----
  double _lumaFromJpeg(Uint8List jpeg) {
    final img = im.decodeImage(jpeg);
    if (img == null) return 0.0;
    return vu.meanLuma(img);
    // kalau kamu mau sampling lebih cepat: vu.meanLuma(img, stride: 2/3)
  }
}
