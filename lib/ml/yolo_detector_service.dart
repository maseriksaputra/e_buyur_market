// lib/ml/yolo_detector_service.dart
// YOLO pelengkap untuk mengambil ROI terbaik (opsional).
// Asumsi model & config berada di folder assets yang terdaftar di pubspec.yaml:
//   - assets/ml/best_float16.tflite
//   - assets/ml/yolo_config.json
// Output bisa:
//  - CHW: [1, 5(+K), N]  (contoh: [1,5,8400])
//  - HWC: [1, N, 5(+K)]  (contoh: [1,8400,85])
// Koordinat dianggap di skala input (mis. 640) atau 0..1 (auto-adapt).

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as im;
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;
import 'package:flutter/foundation.dart';

// ✅ Tambahan sesuai instruksi 3)
import 'config.dart';
import 'vision_utils.dart';

class YoloDetection {
  final int classIndex;
  final String label;
  final double score; // obj * classProb (atau obj saja bila tak ada kelas)
  final double x1, y1, x2, y2; // koordinat pada kanvas input (mis. 640)

  const YoloDetection({
    required this.classIndex,
    required this.label,
    required this.score,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });
}

class _YoloCfg {
  final int input;      // default 640
  final double conf;    // default 0.25
  final double iou;     // default 0.45
  final int maxDet;     // default 20
  final bool sigmoidObj; // default true
  final bool sigmoidCls; // default true
  const _YoloCfg({
    required this.input,
    required this.conf,
    required this.iou,
    required this.maxDet,
    required this.sigmoidObj,
    required this.sigmoidCls,
  });
}

class YoloDetectorService {
  // ==========
  // ✅ KONSTANTA FOLDER ASET (sesuai pubspec.yaml)
  // ==========
  static const String kModelAsset  = 'assets/ml/best_float16.tflite';
  static const String kConfigJson  = 'assets/ml/yolo_config.json';

  // (opsional) label file di folder yang sama
  static const String _labelsTxt   = 'assets/ml/labels_fruit.txt';
  static const String _labelJson   = 'assets/ml/label_to_index.json';

  late final tfl.Interpreter _itp;
  late List<String> _labels;
  late final _YoloCfg _cfg;

  YoloDetectorService._(this._itp, this._labels, this._cfg);

  /// Memuat model + label mapping dengan fallback:
  /// - Prioritas `labelsTxt` (1 label per baris)
  /// - Jika kosong, coba `labelJson`:
  ///     a) {"banana":0,"strawberry":1,...} atau
  ///     b) {"0":"banana","1":"strawberry",...}
  /// - Jika tetap gagal, buat label generik `cls_i`
  static Future<YoloDetectorService> load({
    int threads = 2,
    String modelAsset = kModelAsset,
    String? labelsTxt = _labelsTxt,
    String? labelJson = _labelJson,
    String configAsset = kConfigJson,
  }) async {
    final opts = tfl.InterpreterOptions()..threads = threads;
    final itp  = await tfl.Interpreter.fromAsset(modelAsset, options: opts);

    // ====== Muat labels (txt dulu, lalu json, lalu fallback generik) ======
    List<String> labels = [];

    // 1) TXT
    if (labelsTxt != null) {
      try {
        final rawLabels = await rootBundle.loadString(labelsTxt);
        labels = rawLabels
            .split(RegExp(r'\r?\n'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      } catch (_) {}
    }

    // 2) JSON (dua skema populer)
    if (labels.isEmpty && labelJson != null) {
      try {
        final raw = await rootBundle.loadString(labelJson);
        final map = Map<String, dynamic>.from(jsonDecode(raw));

        // Bentuk (a) {"banana":0,...} atau (b) {"0":"banana",...}
        final byIdx = <int, String>{};
        map.forEach((k, v) {
          final idxFromKey = int.tryParse(k);
          if (idxFromKey != null && v is String) {
            byIdx[idxFromKey] = v;
          } else if (v is num) {
            byIdx[v.toInt()] = k;
          }
        });

        if (byIdx.isNotEmpty) {
          final maxK = byIdx.keys.fold<int>(0, (a, b) => a > b ? a : b);
          labels = List<String>.generate(
            maxK + 1,
            (i) => (byIdx[i] ?? 'cls_$i').trim(),
          );
        }
      } catch (_) {}
    }

    // 3) Fallback generik
    if (labels.isEmpty) {
      labels = List<String>.generate(200, (i) => 'cls_$i');
    }

    // ====== Config opsional (baca dari kConfigJson) ======
    _YoloCfg cfg;
    try {
      final rawCfg = await rootBundle.loadString(configAsset);
      final m = json.decode(rawCfg) as Map<String, dynamic>;
      cfg = _YoloCfg(
        input: (m['input'] ?? m['input_size'] ?? 640) as int,
        conf:  (m['conf_threshold'] ?? 0.25).toDouble(),
        iou:   (m['iou_threshold'] ?? 0.45).toDouble(),
        maxDet:(m['max_detections'] ?? 20) as int,
        sigmoidObj: (m['sigmoid_obj'] ?? true) as bool,
        sigmoidCls: (m['sigmoid_cls'] ?? true) as bool,
      );
    } catch (_) {
      cfg = const _YoloCfg(
        input: 640, conf: 0.25, iou: 0.45, maxDet: 20, sigmoidObj: true, sigmoidCls: true,
      );
    }

    debugPrint('[YOLO] model=$modelAsset labels=${labels.length} input=${cfg.input} cfg=$configAsset');
    return YoloDetectorService._(itp, labels, cfg);
  }

  // Future supaya bisa di-`await`
  Future<void> dispose() async {
    try { _itp.close(); } catch (_) {}
  }

  /// Deteksi & return ROI 224 JPEG dari gambar asli:
  /// - Center-square original -> resize ke input (mis. 640)
  /// - TFLite run (baca shape output dinamis)
  /// - Decode bbox, NMS, pilih terbaik -> crop dari square -> resize 224 -> JPEG bytes
  Future<({Uint8List roi224, String label, double conf})?> detectBestRoi224(
    Uint8List originalBytes,
  ) async {
    final src = im.decodeImage(originalBytes);
    if (src == null) return null;

    // Center square
    final s = math.min(src.width, src.height);
    final cx = ((src.width - s) / 2).round();
    final cy = ((src.height - s) / 2).round();
    final sq = im.copyCrop(src, x: cx, y: cy, width: s, height: s);

    // Resize square -> input
    final rgb = im.copyResize(
      sq,
      width: _cfg.input,
      height: _cfg.input,
      interpolation: im.Interpolation.average,
    );

    // Build input NHWC float32 0..1 — aman untuk image v3/v4
    final Float32List tensor = Float32List(_cfg.input * _cfg.input * 3);
    int i = 0;
    for (int y = 0; y < _cfg.input; y++) {
      for (int x = 0; x < _cfg.input; x++) {
        final dynamic px = rgb.getPixel(x, y); // dynamic penting
        int r, g, b;
        if (px is int) {
          // 0xAARRGGBB
          r = (px >> 16) & 0xFF;
          g = (px >> 8)  & 0xFF;
          b = (px)       & 0xFF;
        } else {
          final dyn = px as dynamic;
          r = (dyn.r as num).toInt();
          g = (dyn.g as num).toInt();
          b = (dyn.b as num).toInt();
        }
        tensor[i++] = r / 255.0;
        tensor[i++] = g / 255.0;
        tensor[i++] = b / 255.0;
      }
    }
    final input = tensor.reshape([1, _cfg.input, _cfg.input, 3]);

    // ====== BACA SHAPE OUTPUT DINAMIS ======
    final outTensor = _itp.getOutputTensors().first;
    final sOut = outTensor.shape; // contoh: [1, 5, 8400] ATAU [1, 8400, 85]
    if (sOut.length != 3) {
      throw StateError('Unexpected YOLO output rank: ${sOut.length}, shape=$sOut');
    }

    // Siapkan buffer output sesuai shape asli
    final List<List<List<double>>> out = List.generate(
      sOut[0],
      (_) => List.generate(sOut[1], (_) => List<double>.filled(sOut[2], 0.0)),
    );

    // Run inference
    _itp.run(input, out);

    // Normalisasi ke format [N, 5(+K?)] -> ambil x,y,w,h,conf + opsional kelas
    late final List<List<double>> preds; // [N, C], C>=5
    final b = sOut[0];
    final c = sOut[1];
    final n = sOut[2];

    if (b != 1) {
      debugPrint('[YOLO] Warning: batch!=1 (batch=$b), hanya pakai batch 0.');
    }

    if (c == 5 && n >= 1) {
      // CHW 5,N -> transpose ke [N,5]
      preds = List.generate(n, (i) => [
            out[0][0][i], // x
            out[0][1][i], // y
            out[0][2][i], // w
            out[0][3][i], // h
            out[0][4][i], // conf
          ]);
    } else if (c > 5 && n >= 1) {
      // CHW (5+K), N -> [N, 5+K]
      preds = List.generate(n, (i) {
        final row = List<double>.filled(c, 0.0);
        for (int ch = 0; ch < c; ch++) {
          row[ch] = out[0][ch][i];
        }
        return row;
      });
    } else if (c >= 1 && n >= 5) {
      // HWC: [1, N, 5(+K)]
      final nn = c; // N sebenarnya
      final cc = n; // C (5+K)
      preds = List.generate(nn, (i) {
        final row = List<double>.filled(cc, 0.0);
        for (int ch = 0; ch < cc; ch++) {
          row[ch] = out[0][i][ch];
        }
        return row;
      });
    } else {
      throw StateError('Unsupported YOLO output shape: $sOut');
    }

    // Tentukan apakah koordinat sudah normalized 0..1 atau piksel
    bool looksNormalized = true;
    final probe = math.min(10, preds.length);
    for (int j = 0; j < probe; j++) {
      final a = preds[j];
      if (a[0] > 1.5 || a[1] > 1.5 || a[2] > 2.0 || a[3] > 2.0) {
        looksNormalized = false; break;
      }
    }
    final double scale = looksNormalized ? _cfg.input.toDouble() : 1.0;

    // Decode -> candidates
    final cand = <YoloDetection>[];
    for (int j = 0; j < preds.length; j++) {
      final a = preds[j];
      if (a.length < 5) continue;

      double cx2 = a[0] * scale;
      double cy2 = a[1] * scale;
      double w2  = a[2] * scale;
      double h2  = a[3] * scale;

      double obj = a[4];
      if (_cfg.sigmoidObj) obj = _sigmoid(obj);

      int bestIdx = -1;
      double bestProb = 1.0; // default tanpa kelas
      String bestLabel = '#-';

      if (a.length > 5) {
        bestProb = 0.0;
        for (int cidx = 5; cidx < a.length; cidx++) {
          double p = a[cidx];
          if (_cfg.sigmoidCls) p = _sigmoid(p);
          if (p > bestProb) {
            bestProb = p;
            bestIdx = cidx - 5;
          }
        }
        // ✅ Pakai mapping label yang sudah dimuat
        bestLabel = (bestIdx >= 0 && bestIdx < _labels.length)
            ? _labels[bestIdx].trim().toLowerCase()
            : 'cls_$bestIdx';
      }

      final score = (a.length > 5) ? (obj * bestProb) : obj;
      if (score < _cfg.conf) continue;

      final x1 = (cx2 - w2 / 2).clamp(0.0, _cfg.input.toDouble());
      final y1 = (cy2 - h2 / 2).clamp(0.0, _cfg.input.toDouble());
      final x2 = (cx2 + w2 / 2).clamp(0.0, _cfg.input.toDouble());
      final y2 = (cy2 + h2 / 2).clamp(0.0, _cfg.input.toDouble());

      cand.add(YoloDetection(
        classIndex: bestIdx < 0 ? 0 : bestIdx,
        label: bestLabel,
        score: score,
        x1: x1, y1: y1, x2: x2, y2: y2,
      ));
    }

    if (cand.isEmpty) return null;

    final picks = _nms(cand, _cfg.iou, _cfg.maxDet);
    final best = picks.first;

    // =======================
    // AMBANG & ROI CERDAS
    // =======================
    final double detConf = best.score;
    final bool isConfident = detConf >= MlConfig.yoloMinConf;

    if (!isConfident) {
      try {
        final smart = pickBrightestRoi224(originalBytes);
        debugPrint('[ROI] Fallback SMART (brightest) luma=${smart.luma.toStringAsFixed(3)} '
            'at x=${smart.x},y=${smart.y},w=${smart.w},h=${smart.h}');
        return (roi224: smart.roi224, label: best.label, conf: detConf);
      } catch (e) {
        debugPrint('[ROI] SMART fallback gagal: $e, lanjut pakai YOLO bbox.');
      }
    }

    // Tambah margin agar tidak terlalu ketat
    const margin = 0.14;
    double bx1 = best.x1 - margin * (best.x2 - best.x1);
    double by1 = best.y1 - margin * (best.y2 - best.y1);
    double bx2 = best.x2 + margin * (best.x2 - best.x1);
    double by2 = best.y2 + margin * (best.y2 - best.y1);

    // Clamp di kanvas input
    bx1 = bx1.clamp(0.0, _cfg.input.toDouble());
    by1 = by1.clamp(0.0, _cfg.input.toDouble());
    bx2 = bx2.clamp(0.0, _cfg.input.toDouble());
    by2 = by2.clamp(0.0, _cfg.input.toDouble());

    // Map bbox -> koordinat square sumber (ukuran s x s)
    final double sqScale = s / _cfg.input;
    final int rx1 = (bx1 * sqScale).round();
    final int ry1 = (by1 * sqScale).round();
    final int rx2 = (bx2 * sqScale).round();
    final int ry2 = (by2 * sqScale).round();

    final int rw = (rx2 - rx1).clamp(1, s);
    final int rh = (ry2 - ry1).clamp(1, s);
    final int cx1f = rx1.clamp(0, s - 1);
    final int cy1f = ry1.clamp(0, s - 1);

    final im.Image crop = im.copyCrop(
      sq,
      x: cx1f,
      y: cy1f,
      width: math.min(rw, s - cx1f),
      height: math.min(rh, s - cy1f),
    );

    // Resize ROI -> 224 dan kirim balik bytes
    final im.Image roi224 = im.copyResize(
      crop,
      width: 224,
      height: 224,
      interpolation: im.Interpolation.cubic,
    );
    final bytes = Uint8List.fromList(im.encodeJpg(roi224, quality: 92));

    return (roi224: bytes, label: best.label, conf: best.score);
  }

  static double _sigmoid(double x) => 1.0 / (1.0 + math.exp(-x));

  static List<YoloDetection> _nms(List<YoloDetection> dets, double iouTh, int maxKeep) {
    dets.sort((a, b) => b.score.compareTo(a.score));
    final kept = <YoloDetection>[];
    final removed = List<bool>.filled(dets.length, false);

    for (int i = 0; i < dets.length; i++) {
      if (removed[i]) continue;
      final di = dets[i];
      kept.add(di);
      if (kept.length >= maxKeep) break;

      for (int j = i + 1; j < dets.length; j++) {
        if (removed[j]) continue;
        final dj = dets[j];
        if (_iou(di, dj) > iouTh) removed[j] = true;
      }
    }
    return kept;
  }

  static double _iou(YoloDetection a, YoloDetection b) {
    final xx1 = math.max(a.x1, b.x1);
    final yy1 = math.max(a.y1, b.y1);
    final xx2 = math.min(a.x2, b.x2);
    final yy2 = math.min(a.y2, b.y2);
    final w = math.max(0.0, xx2 - xx1);
    final h = math.max(0.0, yy2 - yy1);
    final inter = w * h;

    final double areaA = (a.x2 - a.x1) * (a.y2 - a.y1);
    final double areaB = (b.x2 - b.x1) * (b.y2 - b.y1);

    final denom = areaA + areaB - inter + 1e-6;
    return inter / denom;
  }
}

// ======================================================================
// OPTIONAL HELPER: YOLO opsional + fallback aman ke center-crop 224
// Aktifkan YOLO ROI di compile-time:
//   flutter run --dart-define=USE_YOLO_ROI=true
// Default: false (langsung pakai center-crop 224 untuk kecepatan/keandalan).
// ======================================================================

const bool kUseYoloRoi = bool.fromEnvironment('USE_YOLO_ROI', defaultValue: false);

/// Membangun ROI 224:
/// - Jika `USE_YOLO_ROI=true`, coba pakai YOLO → jika gagal/nihil → fallback center-crop.
/// - Jika `USE_YOLO_ROI=false`, langsung center-crop 224.
Future<Uint8List> buildRoi224WithFallback(
  Uint8List jpeg, {
  int threads = 2,
}) async {
  // 1) Coba YOLO jika di-enable
  if (kUseYoloRoi) {
    try {
      final yolo = await YoloDetectorService.load(threads: threads);
      final res = await yolo.detectBestRoi224(jpeg);
      await yolo.dispose();
      if (res != null) {
        debugPrint('[ROI] YOLO OK: ${res.label} conf=${(res.conf * 100).toStringAsFixed(1)}%');
        return res.roi224;
      }
      debugPrint('[ROI] YOLO tidak menemukan bbox, fallback ke center-crop.');
    } catch (e) {
      debugPrint('[ROI] YOLO gagal: $e – fallback center-crop.');
    }
  }

  // 2) Fallback: center-crop → 224
  final src = im.decodeImage(jpeg);
  if (src == null) {
    throw Exception('Gambar tidak valid');
  }
  final s = src.width < src.height ? src.width : src.height;
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

// Catatan untuk pipeline (di file screen/pipeline kamu):
// - Pastikan LLM hanya dipicu pada zona 50–70% (guard keras).
// - Gunakan `buildRoi224WithFallback(originalJpeg)` untuk selalu dapat ROI 224 aman.
