// lib/ml/calibration.dart
// Util & kalibrasi sederhana untuk head klasifikasi multitask.
// - softmaxTemp / sharpenProbs
// - class priors (untuk menekan bias "olive")
// - color context adjust (pakai hue & saturation rata-rata dari ROI 224)
// - debiasPairs (nudge ringan antar pasangan kelas yang sering ketukar)
// - meanHSV(reader)
// - Fusing skor lokal + LLM + guard ROI (baru)
//
// Dependensi: image: ^4.x

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

// NEW: konfigurasi terpusat (pastikan ada di lib/ml/config.dart)
import 'config.dart';

/// ====== KONFIGURASI GLOBAL YANG BISA KAMU TUNING ======

/// Temperature default untuk menajamkan distribusi kelas.
/// 0.5–0.8: tajam, 1.0: apa adanya (netral), >1: melembutkan.
const double kTemp = 0.65;

/// Priors untuk beberapa kelas yang sering “menang tanpa alasan”.
/// Nilai >1.0 menaikkan, <1.0 menurunkan.
/// (Boleh kamu ubah sesuai dataset; nama harus match labels.txt)
const Map<String, double> kClassPriors = {
  'olive': 0.55,
  'banana': 1.35,
  'orange': 1.15,
  'mango': 1.10,
  'apple': 1.10,
  'rotten': 0.75,
  'rotten orange': 0.60,
  'rotten oranges': 0.60,
  'blueberry': 0.80,
};

/// ====== MATH / PROB UTILS ======

List<double> softmaxTemp(List<double> logits, double temp) {
  final t = temp <= 0 ? 1e-6 : temp;
  final n = logits.length;
  if (n == 0) return const [];
  // stabilkan
  double maxLogit = -double.infinity;
  for (final v in logits) {
    if (v > maxLogit) maxLogit = v;
  }
  final exps = List<double>.filled(n, 0.0);
  double sum = 0.0;
  for (int i = 0; i < n; i++) {
    final z = (logits[i] - maxLogit) / t;
    final e = math.exp(z);
    exps[i] = e;
    sum += e;
  }
  if (sum <= 0) {
    return List<double>.filled(n, 1.0 / n);
  }
  return [for (final e in exps) e / sum];
}

/// Menajamkan probabilitas yang sudah di [0..1] dengan “temperatur”:
/// p_i' = p_i^(1/temp) / sum(p_j^(1/temp))
List<double> sharpenProbs(List<double> probs, double temp) {
  final n = probs.length;
  if (n == 0) return const [];
  final g = 1.0 / (temp <= 0 ? 1e-6 : temp);
  final raised = List<double>.filled(n, 0.0);
  double sum = 0.0;
  for (int i = 0; i < n; i++) {
    final p = probs[i].clamp(0.0, 1.0);
    final r = math.pow(p <= 1e-9 ? 1e-9 : p, g).toDouble();
    raised[i] = r;
    sum += r;
  }
  if (sum <= 0) return List<double>.filled(n, 1.0 / n);
  return [for (final r in raised) r / sum];
}

Map<String, double> _renorm(Map<String, double> m) {
  double s = 0.0;
  for (final v in m.values) s += math.max(0.0, v);
  if (s <= 0) {
    final k = m.length == 0 ? 1 : m.length;
    return {for (final e in m.keys) e: 1.0 / k};
  }
  return {for (final e in m.entries) e.key: math.max(0.0, e.value) / s};
}

/// ====== PRIORS ======

Map<String, double> applyClassPriors(
  Map<String, double> probs,
  Map<String, double> priors,
) {
  if (probs.isEmpty) return probs;
  final out = <String, double>{};
  for (final e in probs.entries) {
    final w = priors[e.key] ?? 1.0;
    out[e.key] = e.value * w;
  }
  return _renorm(out);
}

/// ====== WARNA / KONTEKS ======

class HSVMean {
  final double h; // 0..360
  final double s; // 0..1
  final double v; // 0..1
  const HSVMean(this.h, this.s, this.v);
}

/// Rata-rata HSV dari JPEG 224 (sampling per-`step` pixel agar cepat).
HSVMean meanHSV(Uint8List jpeg224, {int step = 4}) {
  final im = img.decodeImage(jpeg224);
  if (im == null) return const HSVMean(0, 0, 0);
  final w = im.width, h = im.height;
  double sumH = 0, sumS = 0, sumV = 0;
  int cnt = 0;

  double _hue(double r, double g, double b) {
    final maxc = math.max(r, math.max(g, b));
    final minc = math.min(r, math.min(g, b));
    final d = maxc - minc;
    double hh;
    if (d == 0) {
      hh = 0;
    } else if (maxc == r) {
      hh = 60 * (((g - b) / d) % 6);
    } else if (maxc == g) {
      hh = 60 * (((b - r) / d) + 2);
    } else {
      hh = 60 * (((r - g) / d) + 4);
    }
    if (hh < 0) hh += 360;
    return hh;
  }

  for (int y = 0; y < h; y += step) {
    for (int x = 0; x < w; x += step) {
      final px = im.getPixel(x, y);
      // image 4.x: px.r/g/b sudah tersedia
      final r = px.r / 255.0, g = px.g / 255.0, b = px.b / 255.0;
      final mx = math.max(r, math.max(g, b));
      final mn = math.min(r, math.min(g, b));
      final v = mx;
      final s = mx == 0 ? 0.0 : (mx - mn) / mx;
      final hh = _hue(r, g, b);
      sumH += hh;
      sumS += s;
      sumV += v;
      cnt++;
    }
  }
  if (cnt == 0) return const HSVMean(0, 0, 0);
  return HSVMean(sumH / cnt, sumS / cnt, sumV / cnt);
}

/// Heuristik: kurangi “olive/blueberry” saat hue dominan oranye/merah,
/// dan naikkan kelas hangat (banana/orange/mango). Lalu renormalisasi.
Map<String, double> colorContextAdjust(
  Map<String, double> probs, {
  required double hue, // 0..360
  required double sat, // 0..1
}) {
  var out = Map<String, double>.from(probs);
  final s = sat.clamp(0.0, 1.0);

  bool inRange(double h, double a, double b) {
    if (a <= b) return (h >= a && h <= b);
    // rentang melingkar (misal 350..20)
    return (h >= a || h <= b);
  }

  // Zona oranye/kuning (pisang, jeruk)
  if (inRange(hue, 15, 50) && s > 0.25) {
    for (final k in ['banana', 'orange', 'mango']) {
      if (out.containsKey(k)) out[k] = out[k]! * 1.15;
    }
    for (final k in ['olive', 'blueberry']) {
      if (out.containsKey(k)) out[k] = out[k]! * 0.70;
    }
  }

  // Zona merah (apel/delima/tomat)
  if ((inRange(hue, 350, 360) || inRange(hue, 0, 15)) && s > 0.25) {
    for (final k in ['apple', 'pomegranate', 'tomato']) {
      if (out.containsKey(k)) out[k] = out[k]! * 1.15;
    }
    if (out.containsKey('olive')) {
      out['olive'] = out['olive']! * 0.75;
    }
  }

  // Zona hijau: jangan terlalu boost olive (bias), tapi beri nudge ringan
  if (inRange(hue, 90, 150) && s > 0.25) {
    for (final k in ['avocado', 'cucumber']) {
      if (out.containsKey(k)) out[k] = out[k]! * 1.08;
    }
    if (out.containsKey('olive')) {
      out['olive'] = out['olive']! * 1.03; // sangat kecil
    }
  }

  return _renorm(out);
}

/// ====== DEBIAS PAIRS (tanpa konteks warna) ======
/// Nudge ringan agar “olive” tidak selalu menang ketika selisih tipis.
Map<String, double> debiasPairs(Map<String, double> probs) {
  if (probs.isEmpty) return probs;
  final out = Map<String, double>.from(probs);

  void nudge(String a, String b,
      {double whenClose = 0.20, double factor = 0.90}) {
    if (!out.containsKey(a) || !out.containsKey(b)) return;
    final pa = out[a]!;
    final pb = out[b]!;
    // kalau pa top dan pb beda < 20%, turunkan pa dikit, naikkan pb
    if (pa > pb && (pa - pb) < whenClose) {
      final delta = pa * (1.0 - factor); // 10% dari a
      out[a] = pa * factor;
      out[b] = pb + delta;
    }
  }

  // olive vs (banana/orange/apple)
  nudge('olive', 'banana');
  nudge('olive', 'orange');
  nudge('olive', 'apple');

  // apple vs pomegranate (sering mirip)
  nudge('apple', 'pomegranate');

  return _renorm(out);
}

/// =====================================================================
/// ====== FUSING SKOR LOKAL + LLM + GUARD ROI (BARU) ===================
/// =====================================================================

class FuseResult {
  final double finalPercent;  // 0..100
  final bool llmTriggered;
  final bool llmForcedByRoi;
  final String reason;        // penjelasan singkat
  FuseResult({
    required this.finalPercent,
    required this.llmTriggered,
    required this.llmForcedByRoi,
    required this.reason,
  });
}

bool _isBorderline(num pct) =>
    pct >= MlConfig.borderlineMin && pct <= MlConfig.borderlineMax;

/// Tentukan apakah LLM dipaksa karena ROI gelap tapi full-frame terang
bool shouldForceLlmByRoi({
  required double? roiLuma,   // 0..1
  required double? fullLuma,  // 0..1
}) {
  if (roiLuma == null || fullLuma == null) return false;
  return (roiLuma < MlConfig.roiDarkThresh) && (fullLuma >= MlConfig.fullBrightThresh);
}

/// Hitung bobot LLM berdasar konteks (borderline/non-borderline) & confidence LLM
double _llmWeight({required bool borderline, required double llmConf}) {
  final c = llmConf.clamp(0.0, 1.0);
  if (borderline) {
    return (MlConfig.fuseBorderlineLlmBase +
            MlConfig.fuseBorderlineLlmGain * c)
        .clamp(0.0, 0.9);
  } else {
    return (MlConfig.fuseNonBorderlineLlmBase +
            MlConfig.fuseNonBorderlineLlmGain * c)
        .clamp(0.0, 0.9);
  }
}

// ====== Fusing skor kelayakan (0..100) ======
FuseResult fuseSuitability({
  required double localPct,           // dari TFLite (0..100)
  double? llmPct,                     // dari server (0..100)
  double llmConf = 0.0,               // 0..1
  double? roiLuma,                    // 0..1
  double? fullLuma,                   // 0..1
  bool yoloConfident = false,
}) {
  // pastikan benar2 double setelah clamp
  final double lp = localPct.clamp(0.0, 100.0).toDouble();
  final bool borderline = _isBorderline(lp);
  final bool roiForce = shouldForceLlmByRoi(roiLuma: roiLuma, fullLuma: fullLuma);

  // Kapan LLM dipakai:
  final bool needLlm = roiForce || borderline || (!yoloConfident && lp < MlConfig.ambangLayak);

  if (!needLlm || llmPct == null) {
    return FuseResult(
      finalPercent: lp,          // sudah double
      llmTriggered: false,
      llmForcedByRoi: false,
      reason: 'LLM tidak diperlukan (final=local)',
    );
  }

  final double lmp = llmPct.clamp(0.0, 100.0).toDouble();
  final double wLlm = _llmWeight(borderline: borderline || roiForce, llmConf: llmConf);
  final double wLocal = 1.0 - wLlm;

  // Jika ROI force → jangan biarkan hasil jatuh dari local (anti false negative)
  final double fused = (wLocal * lp + wLlm * lmp);
  double finalPct = roiForce ? math.max(lp, fused) : fused;

  // ====== OPSIONAL FIX: pastikan clamp bertipe double ======
  finalPct = (finalPct.clamp(0.0, 100.0)) as double;

  final String reason = roiForce
      ? 'LLM di-force (ROI gelap, full terang) → final=max(local, fused)'
      : (borderline ? 'LLM diaktifkan (borderline)' : 'LLM diaktifkan (low conf/under-threshold)');

  return FuseResult(
    finalPercent: finalPct,
    llmTriggered: true,
    llmForcedByRoi: roiForce,
    reason: reason,
  );
}
