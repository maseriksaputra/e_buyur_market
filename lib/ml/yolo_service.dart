// lib/app/core/services/yolo_service.dart
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class RectF {
  final double x, y, w, h;
  const RectF(this.x, this.y, this.w, this.h);
}

class YoloDet {
  final int cls;
  final String label;
  final double conf;
  final RectF box;
  YoloDet({
    required this.cls,
    required this.label,
    required this.conf,
    required this.box,
  });
}

/// YOLO runtime sederhana untuk model TFLite (YOLOv5/YOLOv8 export).
/// Input yang diharapkan: Float32 HWC 0..1 yang SUDAH di-letterbox ke [inputSize,inputSize].
class YoloService {
  final Interpreter _itp;
  final List<String> _labels;
  final int _input; // ordinal input tensor (kebanyakan 0)

  final int inputSize;
  final double confThr, iouThr;

  YoloService._(
    this._itp,
    this._labels,
    this._input,
    this.inputSize,
    this.confThr,
    this.iouThr,
  );

  /// Muat model + label.
  /// - [modelAsset] → path .tflite di pubspec assets
  /// - [labelsTxt]  → path file label per-baris (sesuai kelas model)
  static Future<YoloService> load({
    String modelAsset = 'assets/ml/best_float16.tflite',
    String labelsTxt = 'assets/ml/labels_fruit.txt',
    int inputSize = 640,
    double confThr = 0.25,
    double iouThr = 0.45,
  }) async {
    final itp = await Interpreter.fromAsset(modelAsset);
    final labels = await _readLabels(labelsTxt);
    return YoloService._(itp, labels, 0, inputSize, confThr, iouThr);
  }

  List<String> get labels => _labels;

  void close() => _itp.close();

  /// Deteksi objek.
  /// [inputRgb01] = Float32List HWC (H*W*3) 0..1 yang **sudah** di-letterbox ke [inputSize,inputSize].
  Future<List<YoloDet>> detect(Float32List inputRgb01) async {
    // 1) Samakan input shape dengan model
    final inTensor = _itp.getInputTensor(_input);
    final inShape = inTensor.shape; // contoh: [1,640,640,3]
    final H = inShape[1], W = inShape[2], C = inShape[3];

    _itp.resizeInputTensor(_input, [1, H, W, C]);
    _itp.allocateTensors();

    // 2) Siapkan input nested [1,H,W,3]
    final inputNested = _hwc01ToNested(inputRgb01, H, W);

    // 3) Siapkan output untuk semua head (pakai ordinal 0..n-1)
    final outTensors = _itp.getOutputTensors();
    final outputs = <int, Object>{};
    final shapeByOrd = <int, List<int>>{};
    for (var i = 0; i < outTensors.length; i++) {
      final shp = List<int>.from(outTensors[i].shape);
      outputs[i] = _zerosForShape(shp);
      shapeByOrd[i] = shp;
    }

    // 4) Inferensi: coba multiple-outputs dulu; jika gagal → fallback single-output buffer
    Object? raw;
    List<int> firstShape = const <int>[];

    try {
      _itp.runForMultipleInputs([inputNested], outputs);
      firstShape = shapeByOrd[0] ?? const <int>[];
      raw = outputs[0] ?? (outputs.values.isNotEmpty ? outputs.values.first : null);
    } catch (_) {
      // Fallback: single output
      if (outTensors.isEmpty) return <YoloDet>[];
      final shp = List<int>.from(outTensors[0].shape);
      final singleOut = _zerosForShape(shp);
      _itp.run(inputNested, singleOut);
      firstShape = shp;
      raw = singleOut;
    }

    if (raw == null) return <YoloDet>[];

    // 5) Ubah output jadi baris [cx,cy,w,h,obj, class1..classK]
    final K = _labels.length;
    final rows = _parseYoloRows(raw, firstShape, K);
    if (rows.isEmpty) return <YoloDet>[];

    // 6) Parse box & skor, filter conf, lalu NMS
    final results = <YoloDet>[];
    for (final r in rows) {
      if (r.length < 5) continue;
      final cx = r[0], cy = r[1], w = r[2], h = r[3], obj = r[4];
      if (obj < confThr) continue;

      double best = 0.0;
      int cls = 0;
      for (int k = 0; k < K && 5 + k < r.length; k++) {
        final p = r[5 + k] * obj; // joint score: obj * class
        if (p > best) {
          best = p;
          cls = k;
        }
      }
      if (best < confThr) continue;

      final box = RectF(cx - w / 2, cy - h / 2, w, h); // relatif 0..1

      // 🔒 Mapping label yang aman (fallback bila index out-of-range)
      final label = (cls >= 0 && cls < _labels.length) ? _labels[cls] : 'class_$cls';

      results.add(YoloDet(cls: cls, label: label, conf: best, box: box));
    }

    // NMS sederhana
    results.sort((a, b) => b.conf.compareTo(a.conf));
    final kept = <YoloDet>[];
    for (final det in results) {
      var keep = true;
      for (final k in kept) {
        final iou = _iou(det.box, k.box);
        if (iou > iouThr) {
          keep = false;
          break;
        }
      }
      if (keep) kept.add(det);
    }
    return kept;
  }

  // ==== helpers ====

  /// Muat label per-baris dari assets.
  static Future<List<String>> _readLabels(String labelsTxtAsset) async {
    final txt = await rootBundle.loadString(labelsTxtAsset);
    return txt
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// Float32List HWC (0..1) → nested List [1][H][W][3]
  List _hwc01ToNested(Float32List data, int h, int w) {
    final out = List.generate(
      1,
      (_) => List.generate(
        h,
        (_) => List.generate(w, (_) => List<double>.filled(3, 0.0)),
      ),
    );
    var i = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        out[0][y][x][0] = data[i++]; // R
        out[0][y][x][1] = data[i++]; // G
        out[0][y][x][2] = data[i++]; // B
      }
    }
    return out;
  }

  /// Nested List nol sesuai shape tensor (rekursif).
  Object _zerosForShape(List<int> shape) {
    if (shape.isEmpty) return 0.0;
    final n = shape.first;
    if (shape.length == 1) {
      return List<double>.filled(n, 0.0);
    }
    return List.generate(n, (_) => _zerosForShape(shape.sublist(1)));
  }

  /// Parse output YOLO → list baris [cx,cy,w,h,obj, class1..classK].
  /// Mendukung shape [1,N,5+K], [1,5+K,N], [N,5+K], atau [5+K,N].
  List<List<double>> _parseYoloRows(Object raw, List<int> shape, int K) {
    final flat = _flattenToDoubleList(raw);
    if (shape.isEmpty) return <List<double>>[];

    // buang leading 1
    var sh = List<int>.from(shape);
    if (sh.isNotEmpty && sh.first == 1) sh = sh.sublist(1);

    // ratakan ke 2D
    if (sh.length > 2) {
      final a = sh[0];
      final b = sh.sublist(1).fold<int>(1, (acc, v) => acc * v);
      sh = [a, b];
    }
    if (sh.length == 1) return <List<double>>[];

    final rows = sh[0], cols = sh[1];
    final want = 5 + K;

    if (cols == want) {
      return _reshape2D(flat, rows, cols);
    } else if (rows == want) {
      final m = _reshape2D(flat, rows, cols); // [5+K, N]
      return _transpose2D(m);                 // [N, 5+K]
    } else {
      // fallback: pilih konfigurasi paling mendekati 5+K
      final m = _reshape2D(flat, rows, cols);
      final dRows = (rows - want).abs();
      final dCols = (cols - want).abs();
      if (dRows < dCols) {
        return _transpose2D(m);
      }
      return m;
    }
  }

  List<List<double>> _reshape2D(List<double> flat, int rows, int cols) {
    final out = <List<double>>[];
    var i = 0;
    for (var r = 0; r < rows; r++) {
      out.add(flat.sublist(i, i + cols));
      i += cols;
    }
    return out;
  }

  List<List<double>> _transpose2D(List<List<double>> m) {
    if (m.isEmpty) return m;
    final rows = m.length;
    final cols = m[0].length;
    final out = List.generate(cols, (_) => List<double>.filled(rows, 0.0));
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        out[c][r] = m[r][c];
      }
    }
    return out;
  }

  List<double> _flattenToDoubleList(Object obj) {
    final out = <double>[];
    void rec(dynamic v) {
      if (v is List) {
        for (final e in v) rec(e);
      } else if (v is num) {
        out.add(v.toDouble());
      }
    }
    rec(obj);
    return out;
  }

  double _iou(RectF a, RectF b) {
    final ax2 = a.x + a.w, ay2 = a.y + a.h, bx2 = b.x + b.w, by2 = b.y + b.h;
    final ix1 = math.max(a.x, b.x), iy1 = math.max(a.y, b.y);
    final ix2 = math.min(ax2, bx2), iy2 = math.min(ay2, by2);
    final iw = math.max(0, ix2 - ix1), ih = math.max(0, iy2 - iy1);
    final inter = iw * ih;
    final union = a.w * a.h + b.w * b.h - inter;
    return union <= 0 ? 0 : inter / union;
  }
}
