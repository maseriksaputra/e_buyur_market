import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class QualityResult {
  final int percent;                 // 0..100
  final List<Map<String, dynamic>> top3; // [{'label':..., 'prob':...}]
  QualityResult(this.percent, this.top3);
}

class QualityService {
  final Interpreter _itp;
  final List<String> _labels;
  final int inputSize;

  QualityService._(this._itp, this._labels, this.inputSize);

  static Future<QualityService> load({
    String modelAsset = 'assets/ml/ebuyur_multitask_fp16.tflite',
    String labelsTxt = 'assets/ml/labels_fruit.txt',
    String modelSummary = 'assets/ml/model_summary.json',
  }) async {
    final itp = await Interpreter.fromAsset(modelAsset);
    final labels = (await rootBundle.loadString(labelsTxt))
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final js = jsonDecode(await rootBundle.loadString(modelSummary)) as Map<String, dynamic>;
    final sz = (js['img_size'] is List && (js['img_size'] as List).isNotEmpty)
        ? ((js['img_size'] as List).first as num).toInt()
        : 224;
    return QualityService._(itp, labels, sz);
  }

  void close() => _itp.close();

  /// cropRgb01 adalah Float32List HWC (H*W*3), nilai 0..1, ukuran inputSize x inputSize.
  Future<QualityResult> inferFromRgb01(Float32List cropRgb01) async {
    final H = inputSize, W = inputSize, C = 3;

    // 1) Siapkan input nested [1,H,W,3]
    final inputNested = _hwc01ToNested(cropRgb01, H, W);

    // 2) Resize & allocate
    _itp.resizeInputTensor(0, [1, H, W, C]);
    _itp.allocateTensors();

    // 3) Siapkan kontainer output sesuai shape tiap head
    final outTensors = _itp.getOutputTensors();
    final outputs = <int, Object>{};
    final outShapes = <List<int>>[];

    for (var i = 0; i < outTensors.length; i++) {
      final shp = List<int>.from(outTensors[i].shape); // contoh [1,N] atau [1,1]
      outShapes.add(shp);
      outputs[i] = _zerosForShape(shp);
    }

    // 4) Jalankan inferensi (API kompatibel versi umum tflite_flutter)
    _itp.runForMultipleInputs([inputNested], outputs);

    // 5) Pilih head klasifikasi (type) dan freshness (fresh)
    int typeI = 0, freshI = outTensors.length > 1 ? 1 : 0;
    var maxLast = -1;
    for (var i = 0; i < outShapes.length; i++) {
      final shp = outShapes[i];
      final last = shp.isNotEmpty ? shp.last : 1;
      if (last > maxLast) {
        maxLast = last;
        typeI = i;
      }
    }
    if (outShapes.length > 1) {
      final idx1 = List<int>.generate(outShapes.length, (i) => i).firstWhere(
        (i) => i != typeI && (outShapes[i].isNotEmpty ? outShapes[i].last == 1 : false),
        orElse: () => (typeI == 0 && outShapes.length > 1) ? 1 : 0,
      );
      freshI = idx1;
    }

    // 6) Ambil vektor output sebagai List<double>
    final typeRaw = _flattenToDoubleList(outputs[typeI]);   // ← perbaikan: handle nullable di helper
    final freshRaw = _flattenToDoubleList(outputs[freshI]); // ← perbaikan: handle nullable di helper

    // 7) Softmax/sigmoid adaptif
    List<double> probs;
    final tmin = typeRaw.reduce(math.min);
    final tmax = typeRaw.reduce(math.max);
    if (tmin >= 0.0 && tmax <= 1.0) {
      probs = typeRaw.map((e) => e.clamp(0.0, 1.0)).toList();
    } else {
      final shift = tmax; // stabilitas numerik
      final exps = typeRaw.map((x) => math.exp(x - shift)).toList();
      final sum = exps.fold<double>(0.0, (a, b) => a + b);
      probs = exps.map((e) => e / (sum == 0 ? 1.0 : sum)).toList();
    }

    // 8) Top-3 label
    final idx = List<int>.generate(probs.length, (i) => i);
    idx.sort((a, b) => probs[b].compareTo(probs[a]));
    final k = math.min(3, idx.length);
    final top3 = [
      for (int i = 0; i < k; i++)
        {'label': (i < _labels.length) ? _labels[idx[i]] : 'cls_${idx[i]}', 'prob': probs[idx[i]]}
    ];

    // 9) Freshness 0..1 → 0..100
    double fresh;
    if (freshRaw.isEmpty) {
      fresh = 0.0;
    } else if (freshRaw.length == 1) {
      fresh = freshRaw.first;
    } else {
      fresh = freshRaw.reduce((a, b) => a + b) / freshRaw.length;
    }
    if (!(fresh >= 0 && fresh <= 1)) {
      fresh = 1.0 / (1.0 + math.exp(-fresh)); // sigmoid
    }
    final percent = (fresh * 100).clamp(0, 100).round();

    return QualityResult(percent, top3);
  }

  // ---- helpers ----

  /// Ubah Float32List HWC (0..1) → nested List [1][H][W][3]
  List _hwc01ToNested(Float32List data, int h, int w) {
    final out = List.generate(1, (_) => List.generate(h, (_) => List.generate(w, (_) => List<double>.filled(3, 0.0))));
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

  /// Buat nested List berisi nol sesuai shape Tensor (rekursif).
  Object _zerosForShape(List<int> shape) {
    if (shape.isEmpty) return 0.0;
    final n = shape.first;
    if (shape.length == 1) {
      return List<double>.filled(n, 0.0);
    }
    return List.generate(n, (_) => _zerosForShape(shape.sublist(1)));
  }

  /// Flatten nested List menjadi List<double>. Aman untuk input nullable.
  List<double> _flattenToDoubleList(Object? obj) {
    if (obj == null) return <double>[];
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
}
