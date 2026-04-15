// lib/app/presentation/screens/seller/seller_scan_screen.dart
// ignore_for_file: use_build_context_synchronously, avoid_print

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

// Tema
import 'package:e_buyur_market_flutter_5/app/core/theme/app_colors.dart';

// Cek HTTPS/localhost (hanya untuk web)
import 'package:e_buyur_market_flutter_5/app/core/web_secure_check.dart'
    if (dart.library.html) 'package:e_buyur_market_flutter_5/app/core/web_secure_check_web.dart';

// ====== Provider & AI Services ======
import 'package:provider/provider.dart';
import 'package:e_buyur_market_flutter_5/app/presentation/providers/auth_provider.dart';
import 'package:e_buyur_market_flutter_5/ml/quality_multitask_service.dart';
import 'package:e_buyur_market_flutter_5/app/core/services/ai_api_service.dart';

// ✅ Import yang tidak bentrok
import 'package:e_buyur_market_flutter_5/ml/roi_fallback.dart' as roi_fb; // ⇦ beri alias
import 'package:e_buyur_market_flutter_5/ml/yolo_detector_service.dart' show YoloDetectorService; // ⇦ hanya class

// Image utils
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

enum ScanStatus { initial, scanning, processing, result }

const _kErrorColor = Color(0xFFE53935);
const _kFreshnessVeryGood = Color(0xFF1B5E20);
const _kFreshnessGood = Color(0xFF2E7D32);
const _kFreshnessMedium = Color(0xFFFB8C00);
const _kPrimaryGreenLight = Color(0xFF66BB6A);

// Kata/frasas cacat/kerusakan untuk penalti kualitas
const List<String> _kDefectKeywords = [
  // EN
  'rotten','overripe','over-ripe','over ripe','mold','mould','moldy',
  'bruise','bruised','damaged','bad','spoiled','decay','decayed',
  'soft spots','discolor','discolored','blackened','dark spots','brown spots',
  'wrinkled','shriveled','dry','slimy',
  // ID
  'busuk','berjamur','jamur','bonyok','memar','cacat','rusak',
  'terlalu matang','kelewat matang','bintik hitam','keriput','kisut','berlendir'
];

class ScanScreen extends StatefulWidget {
  const ScanScreen({Key? key}) : super(key: key);

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ---- State ----
  ScanStatus _status = ScanStatus.initial;

  // Controller kamera
  CameraController? _cameraController;

  XFile? _imageFile;
  Uint8List? _imageBytes;

  // Hasil
  final ValueNotifier<int> _percent = ValueNotifier<int>(0);
  double _score = 0.0;
  String _labelText = '—';
  String _eligibilityText = '';
  List<String> _analysis = [];

  // ===== Tambahan: tracking jenis & confidence dari ML
  String? _clsLabel;    // label top-1 dari QualityMultitaskService
  double _clsProb = 0;  // 0..1 confidence top-1 (bukan YOLO)
  double _clsProbCal = 0.0; // (dipertahankan untuk kompatibilitas debug)

  // Prediksi jenis gabungan
  String? _finalKindLabel;
  double _finalKindConf = 0.0;   // 0..1
  bool _finalKindFromLLM = false;

  // Penanda apakah quality TFLite sukses dipakai (untuk fusing)
  bool _qualityOk = false;

  // 🔴 Tambahan: flag ketika TFLite error keras (alokasi tensor/shape)
  bool _tfliteBrokenOnce = false; // stop retry berulang kalau sudah rusak

  // ML services
  QualityMultitaskService? _qualitySvc;
  YoloDetectorService? _yoloSvc;
  bool _aiLoaded = false;
  bool _yoloLoaded = false;

  // LLM
  bool _llmLoading = false;
  Map<String, dynamic>? _llmResult;
  final _aiApi = AiApiService();

  // Cooldown LLM
  DateTime? _llmLastCall;
  static const Duration _llmCooldown = Duration(seconds: 6);

  // Deteksi YOLO (pelengkap)
  String? _yoloLabel;
  double _yoloConf = 0.0;

  // Simpan JPEG/ROI/topK/latency terakhir (untuk debug & tombol LLM)
  Uint8List? _lastJpeg;
  Uint8List? _roi224;
  List<Map<String, dynamic>> _lastTopK = const [];
  int? _latQMs;
  int? _latLLMMs;

  // Flags kamera
  bool _isInitializingCam = false;
  bool _isTakingPicture = false;

  // Animations
  late final AnimationController _pulseC;
  late final AnimationController _scanLineC;
  late final AnimationController _progressC;
  late final Animation<double> _pulse;
  late final Animation<double> _scanLine;
  late final Animation<double> _progress;

  // Steps
  final List<String> _steps = const [
    'Mendeteksi area produk…',
    'Menganalisis warna & tekstur…',
    'Menghitung tingkat kematangan…',
    'Evaluasi kesegaran…',
    'Menentukan kelayakan…',
    'Finalisasi hasil…',
  ];
  int _stepIndex = 0;

  // ===== helper: aturan LLM
  bool get _inLLMBand => _percent.value >= 50 && _percent.value <= 70;
  bool get _lowClassConfidence => _clsProb > 0 ? _clsProb < 0.55 : false;
  bool get _veryLowQuality => _percent.value > 0 && _percent.value < 40;
  bool get _shouldAutoLLM => _inLLMBand || _lowClassConfidence || _veryLowQuality;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initAnims();
    _ensureSvcs();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _safeDisposeCamera();
    _pulseC.dispose();
    _scanLineC.dispose();
    _progressC.dispose();
    _percent.dispose();
    _qualitySvc?.dispose();
    _yoloSvc?.dispose();
    super.dispose();
  }

  // ---- Lifecycle
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _safeDisposeCamera();
    }
  }

  void _initAnims() {
    _pulseC =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _scanLineC =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat();
    _progressC =
        AnimationController(vsync: this, duration: const Duration(seconds: 6));

    _pulse = Tween(begin: 1.0, end: 1.2)
        .animate(CurvedAnimation(parent: _pulseC, curve: Curves.easeInOut));
    _scanLine = Tween(begin: -1.0, end: 1.0)
        .animate(CurvedAnimation(parent: _scanLineC, curve: Curves.linear));
    _progress = Tween(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _progressC, curve: Curves.easeInOut));
  }

  // ===== ensure services =====
  Future<void> _ensureSvcs() async {
    if (_qualitySvc == null) {
      try {
        _qualitySvc = await QualityMultitaskService.load();
        _aiLoaded = true;
        debugPrint('[INIT] Quality service ready.');
      } catch (e, st) {
        _aiLoaded = false;
        debugPrint('[INIT] quality service error: $e\n$st');
      }
    }
    if (_yoloSvc == null) {
      try {
        _yoloSvc = await YoloDetectorService.load();
        _yoloLoaded = true;
        debugPrint('[INIT] YOLO ready (pelengkap).');
      } catch (e) {
        _yoloLoaded = false;
        debugPrint('[INIT] YOLO not ready (ignored): $e');
      }
    }
    if (mounted) setState(() {});
  }

  // ---- Camera ----
  Future<void> _startScan(BuildContext context) async {
    if (kIsWeb && !isSecureAndHasMedia()) {
      _showErrorDialog('Browser butuh HTTPS atau localhost untuk akses kamera.\n'
          'Buka dari https://domain-kamu atau http://localhost.');
      return;
    }
    await _initCamera();
  }

  Future<void> _initCamera() async {
    if (_isInitializingCam) return;
    _isInitializingCam = true;
    try {
      final old = _cameraController;
      _cameraController = null;
      if (mounted) setState(() {});
      if (old != null) await old.dispose().catchError((_) {});

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _showErrorDialog('Tidak ada kamera yang tersedia');
        return;
      }

      final ctrl = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await ctrl.initialize();
      if (!mounted) { await ctrl.dispose().catchError((_) {}); return; }
      setState(() { _cameraController = ctrl; _status = ScanStatus.scanning; });
    } catch (e) {
      _showErrorDialog('Gagal mengakses kamera: $e');
      if (mounted) setState(() => _status = ScanStatus.initial);
    } finally {
      _isInitializingCam = false;
    }
  }

  Future<void> _safeDisposeCamera() async {
    final cam = _cameraController;
    _cameraController = null;
    if (mounted) setState(() {});
    if (cam != null) {
      try { await cam.stopImageStream().catchError((_) {}); } catch (_) {}
      try { await cam.dispose().catchError((_) {}); } catch (_) {}
    }
  }

  Future<void> _resetScan() async {
    await _safeDisposeCamera();
    if (!mounted) return;
    setState(() {
      _status = ScanStatus.initial;
      _imageFile = null;
      _imageBytes = null;
      _stepIndex = 0;
      _yoloLabel = null;
      _yoloConf = 0.0;
      _percent.value = 0;
      _score = 0;
      _labelText = '—';
      _eligibilityText = '';
      _analysis = [];
      _llmResult = null;
      _lastJpeg = null;
      _roi224 = null;
      _lastTopK = const [];
      _latQMs = null;
      _latLLMMs = null;
      _clsLabel = null;
      _clsProb = 0.0;
      _clsProbCal = 0.0;
      _finalKindLabel = null;
      _finalKindConf = 0.0;
      _finalKindFromLLM = false;
      _qualityOk = false;
      _tfliteBrokenOnce = false;
    });
  }

  Future<void> _takePicture() async {
    if (_isTakingPicture) return;
    _isTakingPicture = true;

    final cam = _cameraController;
    if (cam == null || !cam.value.isInitialized) { _isTakingPicture = false; return; }

    try {
      if (mounted) {
        setState(() { _status = ScanStatus.processing; _stepIndex = 0; });
      }
      await cam.stopImageStream().catchError((_) {});
      await cam.pausePreview().catchError((_) {});
      final XFile image = await cam.takePicture();
      final Uint8List bytes = await image.readAsBytes();

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try { await cam.dispose().catchError((_) {}); } catch (_) {}
        if (mounted) setState(() => _cameraController = null);
      });

      setState(() { _imageFile = image; _imageBytes = bytes; _yoloLabel = null; _yoloConf = 0.0; });

      _runPipeline(bytes);
    } catch (e) {
      _showErrorDialog('Gagal mengambil gambar: $e');
    } finally {
      _isTakingPicture = false;
    }
  }

  // ====== Helpers ======
  String _sanitizeLabel(String? s) {
    if (s == null) return '';
    final t = s.trim().toLowerCase();
    if (t.isEmpty || t == '#-' || t == '#' || t.startsWith('#')) return '';
    return t;
  }

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  String _normLabel(String? s) => (s ?? '').trim().toLowerCase();

  bool _hasDefectKeyword(String? s) {
    if (s == null) return false;
    final n = s.toLowerCase();
    return _kDefectKeywords.any((k) => n.contains(k));
  }

  bool _labelsAgreeLoose(String? a, String? b) {
  final sa = _normLabel(a);
  final sb = _normLabel(b);
  if (sa.isEmpty || sb.isEmpty) return false;

  // hapus karakter non-alfanum & spasi ganda
  String clean(String s) =>
      s.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  final ca = clean(sa);
  final cb = clean(sb);

  if (ca == cb) return true;
  if (ca.contains(cb) || cb.contains(ca)) return true;

  // token minimal: jika ada token >=4 huruf yang sama → dianggap setuju
  final ta = ca.split(' ').where((t) => t.length >= 4).toSet();
  final tb = cb.split(' ').where((t) => t.length >= 4).toSet();
  return ta.intersection(tb).isNotEmpty;
}


  double? _penalizeGeminiQualityByKeywords(String? label, double? g01) {
    if (label == null) return g01;
    if (_hasDefectKeyword(label)) {
      return (g01 == null) ? 0.20 : math.min(g01, 0.25);
    }
    return g01;
  }

  // 🔴 Heuristik skor saat ML/LLM gagal total (kompatibel semua versi package:image)
  int _heuristicScoreFromImage(Uint8List imgBytes, {double yoloConf = 0.0}) {
    try {
      final im = img.decodeImage(imgBytes);
      if (im == null) {
        return (45 + (yoloConf.clamp(0, 1) * 40)).round().clamp(10, 85);
      }

      double sum = 0;
      int cnt = 0;

      for (int y = 0; y < im.height; y += 8) {
        for (int x = 0; x < im.width; x += 8) {
          final Object pix = im.getPixel(x, y);
          double r = 0.5, g = 0.5, b = 0.5;
          bool filled = false;

          // Coba akses properti via dynamic (v4.x biasanya punya r/g/b atau rNormalized/gNormalized/bNormalized)
          try {
            final dp = pix as dynamic;

            // coba normalized (0..1)
            final rn = (dp.rNormalized as num?)?.toDouble();
            final gn = (dp.gNormalized as num?)?.toDouble();
            final bn = (dp.bNormalized as num?)?.toDouble();
            if (rn != null && gn != null && bn != null) {
              r = rn; g = gn; b = bn;
              filled = true;
            } else {
              // coba 0..255
              final r255 = (dp.r as num?)?.toDouble();
              final g255 = (dp.g as num?)?.toDouble();
              final b255 = (dp.b as num?)?.toDouble();
              if (r255 != null && g255 != null && b255 != null) {
                r = r255 / 255.0;
                g = g255 / 255.0;
                b = b255 / 255.0;
                filled = true;
              }
            }
          } catch (_) {
            // abaikan — akan coba fallback int di bawah
          }

          // Fallback: versi lama getPixel() mengembalikan int 0xAARRGGBB
          if (!filled && pix is int) {
            final rr = (pix >> 16) & 0xFF;
            final gg = (pix >> 8) & 0xFF;
            final bb = (pix) & 0xFF;
            r = rr / 255.0;
            g = gg / 255.0;
            b = bb / 255.0;
            filled = true;
          }

          final luma = 0.299 * r + 0.587 * g + 0.114 * b;
          sum += luma;
          cnt++;
        }
      }

      final brightness = (cnt > 0 ? (sum / cnt) : 0.5).clamp(0.0, 1.0);
      final base = 30 + (brightness * 40);           // 30..70
      final confBoost = (yoloConf.clamp(0, 1) * 25); // 0..25
      final score = (base + confBoost).clamp(12, 88);
      return score.round();
    } catch (_) {
      return (45 + (yoloConf.clamp(0, 1) * 40)).round().clamp(10, 85);
    }
  }

  void _updateFinalKind({
    String? llmLabel, double? llmConf,
    String? yoloLabel, double? yoloConf,
    String? mlLabel, double? mlConf,
  }) {
    final cand = <Map<String, dynamic>>[];

    void add(String src, String? lab, double? conf, double prior) {
      if (lab == null || lab.trim().isEmpty || conf == null) return;
      cand.add({'src': src, 'lbl': lab.trim(), 'c': conf.clamp(0.0, 1.0), 'p': prior});
    }

    add('llm', llmLabel, llmConf, 1.0);
    add('yolo', yoloLabel, yoloConf, 0.7);
    add('ml',   mlLabel,   mlConf,   0.5);

    if (cand.isEmpty) { _finalKindLabel = null; _finalKindConf = 0; _finalKindFromLLM = false; if(mounted) setState((){}); return; }

    cand.sort((a,b) => ((b['c'] as double) * (b['p'] as double))
        .compareTo((a['c'] as double) * (a['p'] as double)));

    _finalKindLabel = cand.first['lbl'] as String;
    _finalKindConf  = cand.first['c']  as double;
    _finalKindFromLLM = (cand.first['src'] == 'llm');
    if (mounted) setState(() {});
  }

  // ===== YOLO attempt (pelengkap) =====
  Future<Uint8List?> _tryYoloRoi(Uint8List original) async {
    final svc = _yoloSvc;
    if (svc == null) return null;
    try {
      final res = await svc.detectBestRoi224(original);
      if (res == null) { _roi224 = null; return null; }
      _yoloLabel = _sanitizeLabel(res.label);
      _yoloConf  = res.conf;
      _roi224    = res.roi224;
      debugPrint('[YOLO] best="${res.label}" conf=${res.conf.toStringAsFixed(2)}');

      final shown = (_yoloLabel?.isEmpty ?? true) ? '-' : _yoloLabel!;
      _analysis.insert(0, 'Deteksi (YOLO pelengkap): $shown (conf ${(res.conf*100).toStringAsFixed(0)}%)');
      return res.roi224;
    } catch (e, st) {
      debugPrint('[YOLO] fail: $e\n$st');
      _roi224 = null;
      return null;
    }
  }

  // ===== Quality 224 + auto LLM bila perlu =====
  Future<void> _analyzeBytes(Uint8List jpegBytes) async {
    final svc = _qualitySvc;
    if (svc == null) return;

    _llmResult = null;
    _lastJpeg = jpegBytes;
    _qualityOk = false;

    try {
      final t0 = DateTime.now();
      final res = svc.infer(jpegBytes, topK: 3);
      _latQMs = DateTime.now().difference(t0).inMilliseconds;

      final p = (res['quality_percent'] as num).toInt();
      _percent.value = p.clamp(0, 100);
      _score = _percent.value.toDouble();

      final top = List<Map<String, dynamic>>.from(res['topk'] as List? ?? const []);
      _lastTopK = top;

      if (top.isNotEmpty) {
        final first = top.first;
        _clsLabel = (first['label'] ?? '').toString();
        _clsProb  = _toDouble(first['prob'] ?? first['score'] ?? first['value'] ?? 0.0);

        double sumTop = 0.0;
        for (final m in top) {
          sumTop += _toDouble(m['prob'] ?? m['score'] ?? m['value'] ?? 0.0);
        }
        _clsProbCal = sumTop > 0 ? (_clsProb / sumTop).clamp(0.0, 1.0) : _clsProb;
      } else {
        _clsLabel = null;
        _clsProb = 0.0;
        _clsProbCal = 0.0;
      }

      if ((_yoloLabel == null || _yoloLabel!.isEmpty) && (_clsLabel != null && _clsLabel!.isNotEmpty)) {
        _yoloLabel = _clsLabel;
      }

      _updateFinalKind(
        llmLabel: null, llmConf: null,
        yoloLabel: _yoloLabel, yoloConf: _yoloConf,
        mlLabel: _clsLabel, mlConf: _clsProb,
      );

      // quality OK
      _qualityOk = true;

      // Auto LLM bila perlu (band/low conf/very low)
      if (_shouldAutoLLM) {
        await _triggerLLM(_imageBytes ?? jpegBytes);
      }
    } catch (e, st) {
      // Catat error dan mark sebagai broken agar tidak retry terus
      debugPrint('[SCAN] infer error: $e\n$st');
      _qualityOk = false;
      _tfliteBrokenOnce = true; // 🔴 penting: jangan retry berulang
    }
  }

  // ====== Normalizer skor kualitas dari LLM (0..1) ======
  double? _normalizeGeminiQuality(dynamic raw) {
    if (raw == null) return null;
    double? x;
    if (raw is num) {
      x = raw.toDouble();
    } else {
      x = double.tryParse(raw.toString());
    }
    if (x == null || x.isNaN) return null;

    if (x <= 1.0) return x.clamp(0.0, 1.0);
    if (x <= 5.0)  return (x / 5.0).clamp(0.0, 1.0);
    if (x <= 10.0) return (x / 10.0).clamp(0.0, 1.0);
    if (x <= 100.0) return (x / 100.0).clamp(0.0, 1.0);
    return (x / 100.0).clamp(0.0, 1.0);
  }

  Future<void> _triggerLLM(Uint8List jpegBytes, {bool force = false}) async {
    // cooldown
    final now = DateTime.now();
    if (!force && _llmLastCall != null && now.difference(_llmLastCall!) < _llmCooldown) {
      return;
    }
    // guard kecuali force
    if (!force && !_shouldAutoLLM) {
      debugPrint('[LLM] Skip: not needed (band=${_percent.value}, clsProb=${_clsProb.toStringAsFixed(2)}).');
      return;
    }

    _llmLastCall = now;

    if (_llmLoading) return;
    _llmLoading = true; setState(() {});

    try {
      final auth = context.read<AuthProvider>();
      final token = auth.token;
      if (token == null || token.isEmpty) {
        _notify('Validasi LLM gagal: token login tidak ada/expired.');
        return;
      }

      // ROI 224 stabil
      final roi224 = await roi_fb.buildRoi224WithFallback(jpegBytes);

      final t0 = DateTime.now();
      final resp = await _aiApi.validateImage(roi224, bearerToken: token);
      _latLLMMs = DateTime.now().difference(t0).inMilliseconds;

      _llmResult = resp;

      final gScoreRaw = resp['quality_score'] ?? resp['quality'] ?? resp['quality_percent'];
      double? g01 = _normalizeGeminiQuality(gScoreRaw);

      final gconf = (resp['confidence'] as num?)?.toDouble() ?? 0.0;
      final isFV  = resp['is_fruit_or_veg'] as bool? ?? false;
      final lLab  = (resp['detected_item'] as String?)?.trim();

      if (g01 != null) {
        _analysis.insert(0, 'Validasi LLM (quality): ${(g01 * 100).round()}%');
      }
      if ((lLab ?? '').isNotEmpty) {
        _analysis.insert(0, 'Deteksi (LLM): $lLab');
      }

      g01 = _penalizeGeminiQualityByKeywords(lLab, g01);
      // ⬇️ Tambahkan snippet di sini
      final llmTrustBoost = (isFV && (gconf >= 0.85) && ((g01 ?? 0) >= 0.72));
      if (llmTrustBoost) {
        _analysis.insert(0, 'LLM trust boost aktif (skor disejajarkan dengan hasil LLM).');
      }

      // ===== Fusing: bila TFLite gagal, bobot LLM diperbesar =====
      final fused = _fuseScores(
        tflitePercent: _percent.value, // bisa 0 jika TFLite gagal
        yoloConf: _yoloConf,
        geminiScore01: g01,
        geminiConf01: gconf,
        isFruitVeg: isFV,
        llmLabel: lLab,
      );

      _percent.value = fused.clamp(0, 100);
      _score = _percent.value.toDouble();
      _labelText = _labelForScore(_score);

      // Override jenis bila ML lemah tapi LLM kuat
      final strongLLM = isFV && gconf >= 0.90;
      if ((_clsProb <= 0.20 || !_qualityOk) && strongLLM && (lLab ?? '').isNotEmpty) {
        _clsLabel = lLab;
        if ((_yoloLabel ?? '').isEmpty) _yoloLabel = lLab;
        _analysis.insert(0, 'Jenis (override LLM): $lLab (conf ${(100 * gconf).toStringAsFixed(0)}%)');
      }

      // Susun jenis gabungan utk overlay/rincian
      _updateFinalKind(
        llmLabel: lLab, llmConf: gconf,
        yoloLabel: _yoloLabel, yoloConf: _yoloConf,
        mlLabel: _clsLabel, mlConf: _clsProb,
      );
    } catch (e, st) {
      debugPrint('[SCAN] LLM error: $e\n$st');
      _llmResult = {'error': e.toString()};
      _analysis.insert(0, 'Validasi LLM gagal (service busy/overloaded) — skip.');
      _notify('Validasi LLM gagal: ${e.toString().replaceAll(RegExp(r"Exception: ?"), "")}');
    } finally {
      _llmLoading = false;
      if (mounted) setState(() {});
    }
  }

  // ---- Pipeline utama ----
  Future<void> _runPipeline(Uint8List original) async {
    await _ensureSvcs();

    _progressC..reset()..forward();

    // animasi UI
    for (var i = 0; i < _steps.length; i++) {
      if (!mounted) return;
      setState(() => _stepIndex = i);
      await Future.delayed(const Duration(milliseconds: 750));
    }

    // 1) Coba YOLO (pelengkap). Jika ada ROI, pakai ROI 224; jika tidak, center-crop 224.
    Uint8List? roi224 = await _tryYoloRoi(original);
    Uint8List bytesForQuality = roi224 ?? _prepSquareBytes(original, 224);

    // 2) Jalankan quality 224
    await _analyzeBytes(bytesForQuality);

    // 2b) Jika quality gagal dan BELUM pasti rusak, coba sekali lagi pakai center-crop
    if (!_qualityOk && !_tfliteBrokenOnce) {
      _analysis.insert(0, 'Retry quality (fallback center-crop 224)');
      final b2 = _prepSquareBytes(original, 224);
      await _analyzeBytes(b2);
    }

    // 2c) Jika masih gagal, paksa LLM sebagai pedoman
    if (!_qualityOk) {
      await _triggerLLM(bytesForQuality, force: true);
    }

    // 2d) Jika ML & LLM sama-sama gagal → pakai heuristik supaya tidak 0%
    if (!_qualityOk && (_llmResult == null || _llmResult?['error'] != null)) {
      final h = _heuristicScoreFromImage(bytesForQuality, yoloConf: _yoloConf);
      _percent.value = h;
      _score = h.toDouble();
      _analysis.insert(0, 'Top-K quality: fallback heuristik (brightness + YOLO).');
    }

    // 3) Kelar → siapkan teks & status
    _labelText = _labelForScore(_score);

    final jenisLine = (_qualityOk && _clsLabel != null && _clsLabel!.isNotEmpty)
        ? 'Jenis (ML): $_clsLabel (conf ${(100 * _clsProb).toStringAsFixed(0)}%)'
        : 'Jenis (ML): -';

    // Pastikan jenis gabungan terisi
    _updateFinalKind(
      llmLabel: (_llmResult?['detected_item'] as String?),
      llmConf:  (_llmResult?['confidence'] as num?)?.toDouble(),
      yoloLabel: _yoloLabel, yoloConf: _yoloConf,
      mlLabel: _clsLabel, mlConf: _clsProb,
    );

    final jenisGabungan = (_finalKindLabel != null && _finalKindLabel!.isNotEmpty)
        ? 'Prediksi jenis (gabungan): ${_finalKindLabel!} (conf ${(100*_finalKindConf).toStringAsFixed(0)}%)'
        : 'Prediksi jenis (gabungan): -';

    // Rangkuman analisis (pakai skor final)
    _analysis = [
      'Skor kelayakan (final): ${_score.toStringAsFixed(1)}%',
      jenisGabungan,
      jenisLine,
      'Validasi LLM: otomatis bila skor 50–70% atau confidence jenis < 55%.',
      ..._analysis,
    ];

    _eligibilityText = _score >= 70
        ? 'Produk layak untuk dijual. Kualitas baik dan masa simpan memadai.'
        : 'Produk belum layak dijual. Silakan ulangi atau pilih produk lain.';

    if (!mounted) return;
    setState(() => _status = ScanStatus.result);
  }

  // ---- Utils ----
  // ⇨ Ambang label: Layak minimal 70%
  String _labelForScore(double s) {
    if (s >= 90) return 'Sangat Layak';
    if (s >= 80) return 'Cukup Layak';
    if (s >= 70) return 'Layak';
    return 'Tidak Layak';
  }

  // ⇨ Fusing dinamis (robust, penalti kata cacat)
int _fuseScores({
  required int tflitePercent,
  required double yoloConf,
  double? geminiScore01,    // 0..1 setelah normalisasi
  double? geminiConf01,     // 0..1
  bool? isFruitVeg,
  String? llmLabel,
}) {
  final t01 = (tflitePercent / 100).clamp(0.0, 1.0);
  final y01 = yoloConf.clamp(0.0, 1.0);
  final gconf = (geminiConf01 ?? 0).clamp(0.0, 1.0);

  double g01 = (geminiScore01 ?? t01).clamp(0.0, 1.0);
  g01 = _penalizeGeminiQualityByKeywords(llmLabel, g01) ?? g01;

  final bool strongLLM = (isFruitVeg == true) && gconf >= 0.90;
  final bool llmGood   = (isFruitVeg == true) && gconf >= 0.85 && g01 >= 0.72;
  final bool mlWeak    = _clsProb <= 0.55;
  final bool agreeYolo = _labelsAgreeLoose(llmLabel, _yoloLabel) || _labelsAgreeLoose(llmLabel, _clsLabel);

  // Bobot dinamis
  double wT, wY, wG;
  if (llmGood) {
    // LLM dominan saat “good”, kurangi bobot TFLite terutama jika ML lemah.
    wT = mlWeak ? 0.05 : 0.15;
    wY = agreeYolo ? 0.20 : 0.15;
    wG = 1.0 - (wT + wY); // ≥ 0.65
  } else {
    // Mode biasa: TFLite proporsional dengan confidence; LLM tetap punya bobot berarti.
    wT = _qualityOk ? (0.35 + 0.25 * _clsProb).clamp(0.15, 0.60) : 0.10;
    wY = (0.10 + 0.20 * y01).clamp(0.10, 0.25);
    // Jika LLM “strong” (confidence tinggi) meski tak “good”, tetap ≥ 0.50
    final minG = strongLLM ? 0.50 : 0.25;
    wG = (1.0 - (wT + wY)).clamp(minG, 0.70);
  }

  // Hitung rata-rata berbobot
  double fused01 = (t01 * wT) + (y01 * wY) + (g01 * gconf * wG);

  // LLM guard: kalau LLM bagus, jangan biarkan skor jatuh jauh di bawah skor LLM.
  if (llmGood) {
    final guardMin = g01 * (0.85 + 0.10 * y01); // 0.85..0.95 dari skor LLM tergantung YOLO
    fused01 = math.max(fused01, guardMin);
  }

  // Penalti bila ada kata cacat atau bukan buah/sayur.
  if (_hasDefectKeyword(llmLabel)) {
    fused01 = math.min(fused01, 0.45);
    if (t01 < 0.40) fused01 = math.min(fused01, 0.30);
  }
  if (isFruitVeg == false) fused01 = math.min(fused01, 0.35);

  return (fused01.clamp(0.0, 1.0) * 100).round();
}


  // ⇨ Perbaiki orientasi EXIF & crop square 224
  Uint8List _prepSquareBytes(Uint8List src, int size) {
    final dec0 = img.decodeImage(src);
    if (dec0 == null) return src;
    final dec = img.bakeOrientation(dec0);

    final s = math.min(dec.width, dec.height);
    final x = ((dec.width - s) / 2).round();
    final y = ((dec.height - s) / 2).round();
    final crop = img.copyCrop(dec, x: x, y: y, width: s, height: s);
    final rs = img.copyResize(
      crop,
      width: size,
      height: size,
      interpolation: img.Interpolation.cubic,
    );
    return Uint8List.fromList(img.encodeJpg(rs, quality: 92));
  }

  void _showErrorDialog(String msg) => _err(msg);

  void _err(String msg) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Error'),
        content: Text(msg),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }

  void _notify(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Gambar terbaik untuk diserahkan ke halaman Create (ROI 224 jika ada, kalau tidak foto asli).
  Uint8List? _bestCreateImageBytes() => _roi224 ?? _imageBytes;

  /// Arahkan ke halaman Create Product From Scan,
  /// mengirim skor final & metadata **dalam kunci standar** + kunci kompatibel lama.
  Future<void> _goToCreateFromScan({bool allowBelowThreshold = true}) async {
    if (_score < 70 && !allowBelowThreshold) {
      _notify('Skor < 70%. Tidak bisa unggah/draft.');
      return;
    }

    Uint8List? bytes = _bestCreateImageBytes();
    String filename = 'scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
    try {
      if (_imageFile != null) {
        filename = p.basename(_imageFile!.path);
        bytes ??= await _imageFile!.readAsBytes();
      }
    } catch (_) {}

    // Tentukan label prediksi terbaik (gabungan → ML → YOLO)
    final predicted = (_finalKindLabel?.isNotEmpty == true)
        ? _finalKindLabel
        : (_clsLabel?.isNotEmpty == true ? _clsLabel : _yoloLabel);

    // === PAYLOAD (BARU + KOMPAT LAMA) ===
    final double s = _score.clamp(0, 100).toDouble();
    final payload = <String, Object?>{
      // BARU — WAJIB dipakai di halaman create:
      'initialSuitabilityPercent': s,
      'predictedLabel': predicted,
      'capturedImageBytes': bytes,

      // KOMPAT LAMA — biarkan tetap dikirim agar semua kode lama tetap jalan:
      'freshness_score': s,
      'suitability_percent': s,
      'score': s,
      'label': _labelText,
      'analysis': _analysis,
      'imageBytes': bytes,
      'filename': filename,
      'eligible': s >= 70,

      // (opsional) name auto dari deteksi atau fallback
      'name': (_analysis.isNotEmpty && _analysis.first.startsWith('Deteksi'))
          ? _analysis.first.replaceFirst(
              RegExp(r'^Deteksi(\s\(LLM\)|\s\(YOLO pelengkap\))?:\s'), '')
          : (predicted ?? 'Produk Hasil Scan'),
    };

    if (!mounted) return;

    // Coba rute seller dulu; jika tidak ada, fallback ke rute umum.
    final routes = const ['/seller/create-from-scan', '/create-from-scan'];
    bool pushed = false;
    for (final r in routes) {
      try {
        await Navigator.pushNamed(context, r, arguments: payload);
        pushed = true;
        break;
      } catch (_) {
        // lanjut coba rute berikutnya
      }
    }
    if (!pushed) {
      _notify('Route create-from-scan tidak ditemukan. Pastikan didaftarkan di routes.');
    }
  }

  // (Tetap tersedia bila ada flow lain yang mengandalkan return)
  Future<void> _finishLegacyPop() async {
    Navigator.of(context).maybePop({
      'score': _score,
      'label': _labelText,
      'imagePath': _imageFile?.path,
      'details': _analysis,
      // Sertakan juga kunci baru agar caller lama pun bisa baca nilai tepat:
      'initialSuitabilityPercent': _score.clamp(0, 100),
      'predictedLabel': (_finalKindLabel ?? _clsLabel ?? _yoloLabel),
    });
  }

  // ---- UI ----
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('AI Product Scanner', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: _status != ScanStatus.initial
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _resetScan)
            : null,
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    switch (_status) {
      case ScanStatus.initial:
        return _buildInitialUI();
      case ScanStatus.scanning:
        return _buildScanningUI();
      case ScanStatus.processing:
        return _buildProcessingUI();
      case ScanStatus.result:
        return _buildResultUI();
    }
  }

  // ---- Initial ----
  Widget _buildInitialUI() {
    final bottomPad =
        MediaQuery.of(context).padding.bottom + kBottomNavigationBarHeight + 16;

    return Container(
      key: const ValueKey('initial'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, AppColors.primaryGreen.withOpacity(0.05)],
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 24, 24, bottomPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 24),
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) {
                  return Transform.scale(
                    scale: _pulse.value,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.qr_code_scanner,
                        size: 60,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),
              const Text(
                'Scan Produk dengan AI',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Teknologi Machine Learning untuk\nmendeteksi kelayakan produk',
                style: TextStyle(fontSize: 16, color: Colors.grey[600], height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primaryGreen, AppColors.primaryGreenDark],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryGreen.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await _ensureSvcs();
                    await _startScan(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  icon: const Icon(Icons.camera_alt, color: Colors.white),
                  label: Text(
                    _aiLoaded ? 'Mulai Scanning' : 'Memuat AI…',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                    )
                  ],
                ),
                child: const Column(
                  children: [
                    _FeatureItem(
                      icon: Icons.psychology,
                      title: 'AI dengan akurasi 95%',
                      subtitle: 'Model telah dikalibrasi dengan ribuan sampel',
                    ),
                    SizedBox(height: 16),
                    _FeatureItem(
                      icon: Icons.speed,
                      title: 'Analisis cepat < 10 detik',
                      subtitle: 'Proses deteksi real-time dengan teknologi terkini',
                    ),
                    SizedBox(height: 16),
                    _FeatureItem(
                      icon: Icons.verified_outlined,
                      title: 'Hasil terpercaya',
                      subtitle: 'Validasi multi-parameter untuk akurasi maksimal',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Scanning ----
  Widget _buildScanningUI() {
    final cam = _cameraController;
    if (cam == null || !cam.value.isInitialized) return const SizedBox.shrink();

    return Stack(
      key: const ValueKey('scanning'),
      fit: StackFit.expand,
      children: [
        CameraPreview(cam),
        Container(color: Colors.black.withOpacity(0.3)),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Posisikan produk di tengah frame',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  ..._buildCornerIndicators(),
                  AnimatedBuilder(
                    animation: _scanLine,
                    builder: (_, __) {
                      return Positioned(
                        top: 140 + (_scanLine.value * 130),
                        child: Container(
                          width: 240,
                          height: 2,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(colors: [
                              Colors.transparent,
                              AppColors.primaryGreen,
                              AppColors.primaryGreen,
                              Colors.transparent
                            ]),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primaryGreen,
                                blurRadius: 10,
                                spreadRadius: 2,
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Pastikan pencahayaan cukup terang',
                  style: TextStyle(fontSize: 12, color: AppColors.textDark),
                ),
              ),
              GestureDetector(
                onTap: _takePicture,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(
                      color: AppColors.primaryGreen,
                      width: 4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      )
                    ],
                  ),
                  child: const Icon(
                    Icons.camera_alt,
                    color: AppColors.primaryGreen,
                    size: 32,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---- Processing ----
  Widget _buildProcessingUI() {
    return Container(
      key: const ValueKey('processing'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.primaryGreen.withOpacity(0.05), Colors.white],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              Stack(
                alignment: Alignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: _imageBytes != null
                        ? Image.memory(_imageBytes!,
                            width: 200, height: 200, fit: BoxFit.cover)
                        : (_imageFile != null && !kIsWeb
                            ? Image.file(File(_imageFile!.path),
                                width: 200, height: 200, fit: BoxFit.cover)
                            : const SizedBox(
                                width: 200,
                                height: 200,
                                child: ColoredBox(color: Color(0xFFF0F0F0)),
                              )),
                  ),
                  Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.primaryGreen, width: 2),
                    ),
                    child: AnimatedBuilder(
                      animation: _scanLine,
                      builder: (_, __) {
                        return Stack(children: [
                          Positioned(
                            top: 100 + (_scanLine.value * 90),
                            left: 10,
                            right: 10,
                            child: Container(
                              height: 2,
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                    colors: [AppColors.primaryGreen, _kPrimaryGreenLight]),
                                boxShadow: [
                                  BoxShadow(color: AppColors.primaryGreen, blurRadius: 10)
                                ],
                              ),
                            ),
                          ),
                        ]);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
              const Text('Analyzing with AI',
                  style: TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textDark)),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  _steps[_stepIndex],
                  key: ValueKey(_stepIndex),
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<int>(
                valueListenable: _percent,
                builder: (_, v, __) => v > 0
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('Skor AI sementara: $v%',
                            style: TextStyle(fontSize: 14, color: Colors.grey[700])),
                      )
                    : const SizedBox(height: 8),
              ),
              const SizedBox(height: 16),
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: AnimatedBuilder(
                  animation: _progress,
                  builder: (_, __) {
                    return FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: _progress.value,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [AppColors.primaryGreen, _kPrimaryGreenLight]),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 40),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Machine Learning Process',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _steps.length,
                          itemBuilder: (_, i) {
                            final done = i <= _stepIndex;
                            final cur = i == _stepIndex;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: done ? AppColors.primaryGreen : Colors.grey[300],
                                    ),
                                    child: done
                                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _steps[i],
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: done ? AppColors.textDark : Colors.grey[400],
                                        fontWeight:
                                            cur ? FontWeight.w600 : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  if (cur)
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(AppColors.primaryGreen),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: const BoxDecoration(
                    color: Colors.black, borderRadius: BorderRadius.all(Radius.circular(20))),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, color: Colors.amber, size: 16),
                    SizedBox(width: 8),
                    Text('Powered by TFLite + Gemini',
                        style:
                            TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500))
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Result ----
  Widget _buildResultUI() {
    final ok = _score >= 70;
    final color = ok ? AppColors.primaryGreen : _kErrorColor;

    final remainCooldownMs = _llmLastCall == null
        ? 0
        : _llmCooldown.inMilliseconds -
            DateTime.now().difference(_llmLastCall!).inMilliseconds;
    final onCooldown = remainCooldownMs > 0;

    return Container(
      key: const ValueKey('result'),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Colors.white, Colors.white],
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Container(
              height: 200,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: color.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_imageBytes != null)
                      Image.memory(_imageBytes!, fit: BoxFit.cover)
                    else if (!kIsWeb && _imageFile != null)
                      Image.file(File(_imageFile!.path), fit: BoxFit.cover)
                    else
                      const ColoredBox(color: Color(0xFFF0F0F0)),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black.withOpacity(0.3)],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 12,
                      left: 12,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: ok ? AppColors.primaryGreen : _kErrorColor),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(ok ? Icons.verified : Icons.error_outline,
                                    size: 16, color: ok ? AppColors.primaryGreen : _kErrorColor),
                                const SizedBox(width: 6),
                                Text(_labelText,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                          if ((_finalKindLabel ?? '').isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.92),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.black12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.local_florist, size: 16, color: Colors.black54),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${_finalKindLabel!} ${(100*_finalKindConf).round()}%',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.0, end: _score),
              duration: const Duration(milliseconds: 1500),
              curve: Curves.easeOutCubic,
              builder: (_, value, __) {
                IconData mood;
                if (value >= 90) {
                  mood = Icons.sentiment_very_satisfied;
                } else if (value >= 80) {
                  mood = Icons.sentiment_satisfied;
                } else if (value >= 70) {
                  mood = Icons.sentiment_neutral;
                } else {
                  mood = Icons.sentiment_dissatisfied;
                }
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 180,
                      height: 180,
                      child: CircularProgressIndicator(
                        value: value / 100,
                        strokeWidth: 12,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                    Column(
                      children: [
                        Icon(mood, size: 40, color: color),
                        const SizedBox(height: 8),
                        Text('${value.toStringAsFixed(1)}%',
                            style: TextStyle(
                                fontSize: 36, fontWeight: FontWeight.bold, color: color)),
                        Text(_labelText,
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w600, color: color)),
                      ],
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: ok ? AppColors.primaryGreen.withOpacity(0.08)
                          : _kErrorColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: ok ? AppColors.primaryGreen : _kErrorColor),
              ),
              child: Row(
                children: [
                  Icon(ok ? Icons.check_circle : Icons.cancel,
                      color: ok ? AppColors.primaryGreen : _kErrorColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _eligibilityText,
                      style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textDark),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Rincian Analisis',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),

                  for (final e in _analysis) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Icon(Icons.circle, size: 8, color: AppColors.primaryGreen),
                        SizedBox(width: 8),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 16, bottom: 8),
                      child: Text(e,
                        style: const TextStyle(fontSize: 14, color: AppColors.textDark)),
                    ),
                  ],

                  if (_llmResult != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'LLM: ${_llmResult!['detected_item'] ?? '-'}'
                      ' (conf: ${((_llmResult!['confidence'] ?? 0.0) as num).toStringAsFixed(2)})',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],

                  if (_lastJpeg != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: (_llmLoading || onCooldown || _lastJpeg == null)
                          ? null
                          : () => _triggerLLM(_lastJpeg!, force: false),
                      onLongPress: (_llmLoading || onCooldown || _lastJpeg == null)
                          ? null
                          : () => _triggerLLM(_lastJpeg!, force: true),
                      icon: _llmLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.verified),
                      label: Text(
                        onCooldown
                            ? 'Validasi LLM (tunggu ${((remainCooldownMs/1000).ceil())}s)'
                            : _shouldAutoLLM
                                ? 'Validasi LLM sekarang'
                                : 'Validasi LLM (tahan untuk paksa)',
                      ),
                    ),
                  ],

                  // ---- DEV ONLY: Panel Debug ----
                  if (_lastJpeg != null) ...[
                    const Divider(height: 24),
                    ExpansionTile(
                      title: const Text('Debug Scan', style: TextStyle(fontWeight: FontWeight.w600)),
                      childrenPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      children: [
                        if (_roi224 != null) ...[
                          const Text('ROI 224:'),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(_roi224!, height: 96, fit: BoxFit.cover),
                          ),
                          const SizedBox(height: 8),
                        ],
                        Text('Jenis (gabungan overlay): ${_finalKindLabel ?? "-"} (conf: ${(100*_finalKindConf).toStringAsFixed(0)}%)'),
                        Text('Jenis (ML): ${_clsLabel ?? "-"} (conf: ${(100*_clsProb).toStringAsFixed(0)}%)'),
                        Text('YOLO: ${_yoloLabel?.isEmpty == true ? "-" : _yoloLabel} (conf: ${(100*_yoloConf).toStringAsFixed(0)}%)'),
                        Text('q_quality: ${_latQMs ?? 0} ms${_latLLMMs != null ? ' • llm: ${_latLLMMs} ms' : ''}'),
                        const SizedBox(height: 8),
                        const Text('Top-K Quality (kelas):'),
                        ..._lastTopK.map((m) {
                          final lbl = (m['label'] ?? '-').toString();
                          final v = (m['prob'] ?? m['score'] ?? m['value'] ?? 0);
                          final vv = (v is num) ? v : 0;
                          return Text('• $lbl : ${(100*vv).toStringAsFixed(0)}%');
                        }),
                        const SizedBox(height: 8),
                        Text('LLM raw: ${_llmResult ?? '-'}'),
                        Text('Score akhir: ${_percent.value}% • Label: $_labelText'),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Aksi
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _resetScan,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppColors.primaryGreen),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.refresh, color: AppColors.primaryGreen),
                    label: const Text('Scan Ulang',
                        style: TextStyle(
                            color: AppColors.primaryGreen, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    // 🔴 PERUBAHAN PENTING: Selesai ⇒ push ke Create page membawa skor & ROI
                    onPressed: () => _goToCreateFromScan(allowBelowThreshold: true),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: AppColors.primaryGreen,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.check, color: Colors.white),
                    label: const Text('Selesai',
                        style:
                            TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (ok) ...[
              TextButton.icon(
                onPressed: _goToCreateFromScan,
                icon: const Icon(Icons.add_box_outlined),
                label: const Text('Buat Produk dari Hasil Scan'),
              ),
              TextButton.icon(
                onPressed: _goToCreateFromScan,
                icon: const Icon(Icons.save_alt),
                label: const Text('Simpan sebagai draft'),
              ),
            ],

            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  // ---- Corner indicators ----
  List<Widget> _buildCornerIndicators() {
    const size = 24.0;
    const thick = 4.0;

    Widget corner() => SizedBox(
          width: size,
          height: size,
          child: Stack(
            children: const [
              Positioned(
                left: 0,
                top: 0,
                right: size - thick,
                child: SizedBox(
                  height: thick,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: Colors.white),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: size - thick,
                child: SizedBox(
                  width: thick,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        );

    final halfWidth = (MediaQuery.of(context).size.width / 2);
    return [
      Positioned(top: 200 - 140, left: halfWidth - 140, child: corner()),
      Positioned(
          top: 200 - 140,
          right: halfWidth - 140,
          child: Transform.rotate(angle: math.pi / 2, child: corner())),
      Positioned(
          bottom: 200 - 140,
          left: halfWidth - 140,
          child: Transform.rotate(angle: -math.pi / 2, child: corner())),
      Positioned(
          bottom: 200 - 140,
          right: halfWidth - 140,
          child: Transform.rotate(angle: math.pi, child: corner())),
    ];
  }
}

// Reusable feature row
class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _FeatureItem({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primaryGreen.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppColors.primaryGreen, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textDark)),
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        ),
      ],
    );
  }
}
