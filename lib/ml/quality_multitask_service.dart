// lib/ml/quality_multitask_service.dart
// ignore_for_file: avoid_print

import 'dart:convert' show jsonDecode;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class QualityMultitaskService {
  final Interpreter _interpreter;
  final TensorType _inType;
  final List<int> _inShape; // [1,H,W,3]
  final int _h;
  final int _w;
  final bool _isQuant;
  final List<String>? _labels;

  QualityMultitaskService._(
    this._interpreter,
    this._inType,
    this._inShape,
    this._h,
    this._w,
    this._isQuant,
    this._labels,
  );

  // ===== LOAD =====
  static Future<QualityMultitaskService> load({
    // ✅ Default model multitask (bukan YOLO)
    String asset = 'assets/ml/ebuyur_multitask_fp16.tflite',
    List<String> modelCandidates = const [
      'assets/ml/ebuyur_multitask_fp16.tflite',
      // tambahkan kandidat lain di sini kalau ada model multitask lain
    ],
    // ✅ Pastikan label buah yang benar; sediakan fallback JSON/teks
    List<String> labelAssets = const [
      'assets/ml/labels_fruit.txt',
      'assets/ml/label_to_index.json',
      'assets/ml/labels.txt',
    ],
  }) async {
    // Pilih model pertama yang tersedia (hindari YOLO 'best_float16.tflite')
    Interpreter? itp;
    for (final m in <String>{asset, ...modelCandidates}) {
      try {
        itp = await Interpreter.fromAsset(m);
        debugPrint('[QM] Use model: $m');
        break;
      } catch (_) {}
    }
    if (itp == null) {
      throw Exception('TFLite model tidak ditemukan di assets/ml (multitask).');
    }

    // Siapkan input tensor & shape
    final inTensor = itp.getInputTensors().first;
    final inType = inTensor.type;
    final inShape = List<int>.from(inTensor.shape);
    final isQuant = (inType == TensorType.uint8 || inType == TensorType.int8);

    int h = 224, w = 224;
    if (inShape.length == 4) {
      h = inShape[1];
      w = inShape[2];
    } else {
      // Model aneh → paksa ke [1,224,224,3]
      h = 224;
      w = 224;
      itp.resizeInputTensor(0, [1, h, w, 3]);
    }

    // Pastikan tensor teralokasi sebelum cek outputs
    itp.allocateTensors();

    // Muat label bila ada (opsional) — dukung .txt & .json
    List<String>? labels;
    for (final path in labelAssets) {
      try {
        final txt = await rootBundle.loadString(path);

        if (path.toLowerCase().endsWith('.json')) {
          final d = jsonDecode(txt);
          if (d is List) {
            final arr = d
                .whereType<String>()
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
            if (arr.isNotEmpty) {
              labels = arr;
              debugPrint('[QM] Load labels (JSON array): $path (${labels.length})');
              break;
            }
          } else if (d is Map) {
            // asumsikan {label: index} → buat list terurut index
            final entries = d.entries
                .where((e) => e.key is String && (e.value is num || e.value is String))
                .map((e) => MapEntry(e.key.toString(), int.tryParse(e.value.toString()) ?? 0))
                .toList();
            entries.sort((a, b) => a.value.compareTo(b.value));
            final arr = entries.map((e) => e.key.trim()).where((e) => e.isNotEmpty).toList();
            if (arr.isNotEmpty) {
              labels = arr;
              debugPrint('[QM] Load labels (JSON map): $path (${labels.length})');
              break;
            }
          }
        } else {
          // .txt — satu label per baris
          final arr = txt
              .split(RegExp(r'\r?\n'))
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
          if (arr.isNotEmpty) {
            labels = arr;
            debugPrint('[QM] Load labels (TXT): $path (${labels.length})');
            break;
          }
        }
      } catch (_) {}
    }

    // === Sanity check: jumlah label harus == jumlah kelas output ===
    try {
      final outs = itp.getOutputTensors();
      final Tensor clsOut = outs.firstWhere(
        (t) => t.shape.fold<int>(1, (a, b) => a * b) > 4, // asumsi: vektor kelas > 4 elemen
        orElse: () => outs.first,
      );
      final numClasses = clsOut.shape.fold<int>(1, (a, b) => a * b);
      if (labels != null && labels!.length != numClasses) {
        debugPrint('[QM] Label count mismatch: labels=${labels!.length} vs classes=$numClasses → ignore labels');
        labels = null; // jangan pakai label yang salah
      }
    } catch (e) {
      // abaikan jika gagal membaca output tensor
      debugPrint('[QM] Sanity check labels skipped: $e');
    }

    return QualityMultitaskService._(
      itp,
      inType,
      [1, h, w, 3],
      h,
      w,
      isQuant,
      labels,
    );
  }

  void dispose() {
    try {
      _interpreter.close();
    } catch (_) {}
  }

  Future<Map<String, dynamic>> inferFromJpeg(Uint8List jpegBytes) async {
    final im = _decodeToModelInput(jpegBytes, _w, _h);
    final input = _buildInput(im);

    // Siapkan penampung output mengikuti shape tensor
    final outs = <int, Object>{};
    final outTensors = _interpreter.getOutputTensors();
    for (var i = 0; i < outTensors.length; i++) {
      outs[i] = _zerosForShape(outTensors[i].shape, outTensors[i].type);
    }

    _interpreter.runForMultipleInputs([input], outs);
    return _parseOutputs(outTensors, outs);
  }

  // --- image helpers
  static img.Image _centerCropSquare(img.Image src) {
    final s = math.min(src.width, src.height);
    final x = ((src.width - s) / 2).round();
    final y = ((src.height - s) / 2).round();
    return img.copyCrop(src, x: x, y: y, width: s, height: s);
  }

  static img.Image _decodeToModelInput(Uint8List jpeg, int w, int h) {
    final dec0 = img.decodeImage(jpeg);
    if (dec0 == null) {
      return img.Image(width: w, height: h, numChannels: 3, format: img.Format.uint8)
        ..clear(img.ColorUint8.rgb(127, 127, 127));
    }
    final dec = img.bakeOrientation(dec0);
    final sq = _centerCropSquare(dec);
    final rs = img.copyResize(
      sq,
      width: w,
      height: h,
      interpolation: img.Interpolation.cubic,
    );
    return rs.convert(numChannels: 3);
  }

  Object _buildInput(img.Image im) {
    final w = im.width, h = im.height;
    if (_inType == TensorType.float32) {
      final buf = List.generate(h, (_) => List.generate(w, (_) => List<double>.filled(3, 0.0)));
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final p = im.getPixel(x, y);
          buf[y][x][0] = (p.r as num).toDouble() / 255.0;
          buf[y][x][1] = (p.g as num).toDouble() / 255.0;
          buf[y][x][2] = (p.b as num).toDouble() / 255.0;
        }
      }
      return [buf];
    } else {
      final buf = List.generate(h, (_) => List.generate(w, (_) => List<int>.filled(3, 0)));
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final p = im.getPixel(x, y);
          buf[y][x][0] = (p.r as num).toInt();
          buf[y][x][1] = (p.g as num).toInt();
          buf[y][x][2] = (p.b as num).toInt();
        }
      }
      return [buf];
    }
  }

  Object _zerosForShape(List<int> shape, TensorType t) {
    final zero = (t == TensorType.float32) ? 0.0 : 0;
    Object build(List<int> s) => s.isEmpty ? zero : List.generate(s.first, (_) => build(s.sublist(1)));
    return build(shape);
  }

  static List<double> _softmax(List<double> x) {
    if (x.isEmpty) return const [];
    final m = x.reduce(math.max);
    final exps = x.map((e) => math.exp(e - m)).toList();
    final sum = exps.fold<double>(0, (a, b) => a + b);
    return sum == 0 ? List<double>.filled(x.length, 0) : exps.map((e) => e / sum).toList();
  }

  static List<double> _flattenToDoubles(Object data) {
    if (data is List) return data.expand((e) => _flattenToDoubles(e)).toList();
    if (data is num) return [data.toDouble()];
    if (data is Float32List) return data.map((e) => e.toDouble()).toList();
    if (data is Uint8List) return data.map((e) => e.toDouble()).toList();
    return const [];
  }

  static double _firstScalar(Object data) {
    final f = _flattenToDoubles(data);
    return f.isEmpty ? 0.0 : f.first;
  }

  Map<String, dynamic> _parseOutputs(List<Tensor> tensors, Map<int, Object> outs) {
    double? fresh01;
    List<double>? classVec;
    final rawShapes = <String, List<int>>{};

    for (var i = 0; i < tensors.length; i++) {
      final t = tensors[i];
      rawShapes['out_$i'] = List<int>.from(t.shape);
      final obj = outs[i]!;
      final numel = t.shape.fold<int>(1, (a, b) => a * b);

      if (numel == 1) {
        double v = _firstScalar(obj);
        if (v > 1.0) v /= 100.0; // jika model keluar 0..100
        fresh01 = v.clamp(0.0, 1.0);
      } else {
        classVec = _flattenToDoubles(obj);
      }
    }

    Map<String, double> probs = {};
    List<Map<String, dynamic>> top = [];

    if (classVec != null && classVec!.isNotEmpty) {
      final hasNeg = classVec!.any((e) => e < 0);
      final sum = classVec!.fold<double>(0, (a, b) => a + b);
      final p = (!hasNeg && sum > 0.95 && sum < 1.05) ? classVec! : _softmax(classVec!);

      for (int i = 0; i < p.length; i++) {
        final name = (_labels != null && i < _labels!.length) ? _labels![i] : 'cls_$i';
        probs[name] = p[i];
      }
      final idx = List<int>.generate(p.length, (i) => i)..sort((a, b) => p[b].compareTo(p[a]));
      final k = math.min(5, p.length);
      top = List.generate(k, (j) {
        final i = idx[j];
        final name = (_labels != null && i < _labels!.length) ? _labels![i] : 'cls_$i';
        return {'label': name, 'prob': p[i]};
      });

      fresh01 ??= p[idx.first];
    }

    final freshPercent = ((fresh01 ?? 0) * 100).clamp(0.0, 100.0);

    return {
      'fresh_percent': freshPercent,
      'probs': probs,
      'top': top,
      'raw_shapes': rawShapes,
    };
  }
}
