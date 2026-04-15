// lib/app/presentation/screens/seller/seller_scan_screen.dart
// ignore_for_file: use_build_context_synchronously, avoid_print

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:convert'; // (1) tambahan: pretty json

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';

// Tema
import 'package:e_buyur_market_flutter_5/app/core/theme/app_colors.dart';

// Cek HTTPS/localhost (hanya untuk web)
import 'package:e_buyur_market_flutter_5/app/core/web_secure_check.dart';

// ====== Provider & AI Services ======
import 'package:provider/provider.dart';
import 'package:e_buyur_market_flutter_5/app/presentation/providers/auth_provider.dart';
import 'package:e_buyur_market_flutter_5/ml/quality_multitask_service.dart';
import 'package:e_buyur_market_flutter_5/app/core/services/ai_api_service.dart';

// ✅ Paksa gunakan API.dio (base sudah /api/)
import 'package:e_buyur_market_flutter_5/app/core/network/api.dart';

// ✅ Import yang tidak bentrok
import 'package:e_buyur_market_flutter_5/ml/yolo_detector_service.dart'
    show YoloDetectorService; // ⇦ hanya class

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
  'rotten',
  'overripe',
  'over-ripe',
  'over ripe',
  'mold',
  'mould',
  'moldy',
  'bruise',
  'bruised',
  'damaged',
  'bad',
  'spoiled',
  'decay',
  'decayed',
  'soft spots',
  'discolor',
  'discolored',
  'blackened',
  'dark spots',
  'brown spots',
  'wrinkled',
  'shriveled',
  'dry',
  'slimy',
  // ID
  'busuk',
  'berjamur',
  'jamur',
  'bonyok',
  'memar',
  'cacat',
  'rusak',
  'terlalu matang',
  'kelewat matang',
  'bintik hitam',
  'keriput',
  'kisut',
  'berlendir'
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
  String? _clsLabel; // label top-1 dari QualityMultitaskService
  double _clsProb = 0; // 0..1 confidence top-1 (bukan YOLO)
  double _clsProbCal = 0.0; // (dipertahankan untuk kompatibilitas debug)

  // Prediksi jenis gabungan
  String? _finalKindLabel;
  double _finalKindConf = 0.0; // 0..1
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

  // ✅ Pakai API.dio agar base URL selalu .../api/
  final _aiApi = AiApiService(dio: API.dio);

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

  // 🔒 NEW: cegah setState setelah dispose
  bool _isDisposing = false;

  // Animations
  late final AnimationController _pulseC;
  late final AnimationController _scanLineC;
  late final AnimationController _progressC;
  late final Animation<double> _pulse;
  late final Animation<double> _scanLine;
  late final Animation<double> _progress;

  // Scroll controller untuk kartu proses & log (dipertahankan, boleh idle)
  late final ScrollController _stepsScrollC;
  late final ScrollController _analysisScrollC;

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
  bool get _inLLMBand => _yoloConf >= 0.50 && _yoloConf <= 0.70;
  bool get _lowYoloConfidence => _yoloConf < 0.55;
  bool get _lowClassConfidence => _clsProb > 0 ? _clsProb < 0.55 : false;
  bool get _veryLowQuality => _percent.value > 0 && _percent.value < 40;
  bool get _shouldAutoLLM =>
      _inLLMBand || _lowYoloConfidence || _lowClassConfidence || _veryLowQuality;

  // ====== Tambahan agar kompatibel dengan snippet _finish() ======
  double _suitabilityPct = 0; // mirror dari _score (0..100)
  String _scanLabel =
      ''; // nama/jenis hasil deteksi gabungan; 'Tidak Terdeteksi' jika kosong
  String? _filename; // nama file foto untuk argumen create

  // ==== (2b) Normalisasi & blacklist label untuk bias “olive” ====
  static const Set<String> _blockedMlLabels = {'olive'};

  static const Map<String, String> _aliases = {
    'pisang cavendish': 'pisang',
    'cavendish banana': 'pisang',
    'banana': 'pisang',
    'bellpepper': 'paprika',
    'soy_beans': 'kedelai',
  };

  String _unifyName(String? s) {
    final t = (s ?? '').trim().toLowerCase();
    if (t.isEmpty) return '';
    for (final e in _aliases.entries) {
      if (t == e.key || t.contains(e.key)) return e.value;
    }
    return t;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initAnims();
    _stepsScrollC = ScrollController();
    _analysisScrollC = ScrollController();
    _ensureSvcs();
  }

  @override
  void dispose() {
    _isDisposing = true;

    WidgetsBinding.instance.removeObserver(this);
    _safeDisposeCamera();

    try {
      _pulseC.dispose();
    } catch (_) {}
    try {
      _scanLineC.dispose();
    } catch (_) {}
    try {
      _progressC.dispose();
    } catch (_) {}
    try {
      _percent.dispose();
    } catch (_) {}
    try {
      _stepsScrollC.dispose();
    } catch (_) {}
    try {
      _analysisScrollC.dispose();
    } catch (_) {}
    try {
      _qualitySvc?.dispose();
    } catch (_) {}
    try {
      _yoloSvc?.dispose();
    } catch (_) {}

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

  // ===== (1) Helper baru =====
  String _prettyJson(Map<String, dynamic> m) =>
      const JsonEncoder.withIndent('  ').convert(m);

  T? _pick<T>(Map<String, dynamic>? m, String k) {
    if (m == null) return null;
    final v = m[k];
    if (v is T) return v;
    // fleksibel: string-number
    if (T == double) return (double.tryParse(v?.toString() ?? '') as T?);
    if (T == int) return (int.tryParse(v?.toString() ?? '') as T?);
    if (T == String) return (v?.toString() as T?);
    return null;
  }

  double _as01(dynamic x) {
    if (x == null) return 0;
    double? d = (x is num) ? x.toDouble() : double.tryParse(x.toString());
    if (d == null) return 0;
    if (d > 1.0) d = d / 100.0;
    return d.clamp(0.0, 1.0);
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
    if (mounted && !_isDisposing) setState(() {});
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
      if (mounted && !_isDisposing) setState(() {});
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
      if (!mounted || _isDisposing) {
        await ctrl.dispose().catchError((_) {});
        return;
      }
      setState(() {
        _cameraController = ctrl;
        _status = ScanStatus.scanning;
      });
    } catch (e) {
      _showErrorDialog('Gagal mengakses kamera: $e');
      if (mounted && !_isDisposing) setState(() => _status = ScanStatus.initial);
    } finally {
      _isInitializingCam = false;
    }
  }

  Future<void> _safeDisposeCamera() async {
    try {
      final cam = _cameraController;
      _cameraController = null;
      if (cam != null) {
        try {
          await cam.stopImageStream().catchError((_) {});
        } catch (_) {}
        try {
          await cam.dispose().catchError((_) {});
        } catch (_) {}
      }
    } catch (_) {}
    if (mounted && !_isDisposing) {
      setState(() {});
    }
  }

  Future<void> _resetScan() async {
    await _safeDisposeCamera();
    if (!mounted || _isDisposing) return;
    setState(() {
      _status = ScanStatus.initial;
      _imageFile = null;
      _imageBytes = null;
      _filename = null;
      _stepIndex = 0;
      _yoloLabel = null;
      _yoloConf = 0.0;
      _percent.value = 0;
      _score = 0;
      _suitabilityPct = 0;
      _labelText = '—';
      _scanLabel = '';
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
    if (cam == null || !cam.value.isInitialized) {
      _isTakingPicture = false;
      return;
    }

    try {
      if (mounted && !_isDisposing) {
        setState(() {
          _status = ScanStatus.processing;
          _stepIndex = 0;
        });
      }
      await cam.stopImageStream().catchError((_) {});
      await cam.pausePreview().catchError((_) {});
      final XFile image = await cam.takePicture();
      final Uint8List bytes = await image.readAsBytes();

      try {
        _filename = p.basename(image.path);
      } catch (_) {
        _filename = null;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await cam.dispose().catchError((_) {});
        } catch (_) {}
        if (mounted && !_isDisposing) setState(() => _cameraController = null);
      });

      if (mounted && !_isDisposing) {
        setState(() {
          _imageFile = image;
          _imageBytes = bytes;
          _yoloLabel = null;
          _yoloConf = 0.0;
        });
      }

      _runPipeline(bytes);
    } catch (e) {
      _showErrorDialog('Gagal mengambil gambar: $e');
    } finally {
      _isTakingPicture = false;
    }
  }

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

    String clean(String s) => s
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final ca = clean(sa);
    final cb = clean(sb);

    if (ca == cb) return true;
    if (ca.contains(cb) || cb.contains(ca)) return true;

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

          try {
            final dp = pix as dynamic;

            final rn = (dp.rNormalized as num?)?.toDouble();
            final gn = (dp.gNormalized as num?)?.toDouble();
            final bn = (dp.bNormalized as num?)?.toDouble();
            if (rn != null && gn != null && bn != null) {
              r = rn;
              g = gn;
              b = bn;
              filled = true;
            } else {
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
          } catch (_) {}

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
      final base = 35 + (brightness * 40); // 35..75
      final confBoost = (yoloConf.clamp(0, 1) * 30); // 0..30
      final score = (base + confBoost).clamp(20, 90);
      return score.round();
    } catch (_) {
      return (45 + (yoloConf.clamp(0, 1) * 40)).round().clamp(10, 85);
    }
  }

  Map<String, dynamic> _flattenGeminiPayload(Map<String, dynamic> payload) {
    try {
      Map<String, dynamic>? pick(Object? o) =>
          (o is Map) ? Map<String, dynamic>.from(o as Map) : null;

      final Map<String, dynamic> cur = Map<String, dynamic>.from(payload);

      final Map<String, dynamic> outer =
          pick(cur['raw']) ?? pick(cur['data']) ?? pick(cur['body']) ?? cur;

      Map<String, dynamic> node = Map<String, dynamic>.from(outer);
      int guard = 0;
      while (node['result'] is Map && guard < 5) {
        node = Map<String, dynamic>.from(node['result'] as Map);
        guard++;
      }

      if (!node.containsKey('is_fruit_or_veg') &&
          outer.containsKey('is_fruit_or_veg')) {
        node['is_fruit_or_veg'] = outer['is_fruit_or_veg'];
      }

      return node;
    } catch (_) {
      return payload;
    }
  }

  Map<String, dynamic> _extractLlmCore(Map<String, dynamic> payload) {
    Map<String, dynamic>? best;
    int bestScore = -1;

    final q = <Map<String, dynamic>>[payload];
    while (q.isNotEmpty) {
      final m = q.removeAt(0);
      int s = 0;

      double numv(String k) {
        final v = m[k];
        if (v is num) return v.toDouble();
        return double.tryParse(v?.toString() ?? '') ?? 0.0;
      }

      bool hasStr(String k) =>
          (m[k] != null && m[k].toString().trim().isNotEmpty);

      if (hasStr('detected_item') || hasStr('label') || hasStr('class') || hasStr('category')) s += 3;
      if (numv('suitability_percent') > 0) s += 3;
      if (numv('quality_percent') > 0 || numv('quality_score') > 0) s += 2;
      if (numv('confidence') > 0) s += 2;
      if (m['is_fruit_or_veg'] is bool) s += 1;

      if (s > bestScore) {
        bestScore = s;
        best = m;
      }

      for (final v in m.values) {
        if (v is Map) q.add(Map<String, dynamic>.from(v as Map));
      }
    }
    return best ?? <String, dynamic>{};
  }

  Uint8List _bestBytesForLLM(Uint8List original, {int maxSide = 640}) {
    try {
      final im0 = img.decodeImage(original);
      if (im0 == null) return original;
      final im2 = img.bakeOrientation(im0);
      final w = im2.width, h = im2.height;
      final longSide = w > h ? w : h;
      if (longSide <= maxSide) return original;
      final scale = maxSide / longSide;
      final nw = (w * scale).round().clamp(64, 4096);
      final nh = (h * scale).round().clamp(64, 4096);
      final rs = img.copyResize(
        im2,
        width: nw,
        height: nh,
        interpolation: img.Interpolation.cubic,
      );
      return Uint8List.fromList(img.encodeJpg(rs, quality: 82));
    } catch (_) {
      return original;
    }
  }

  void _updateFinalKind({
    String? llmLabel,
    double? llmConf,
    double? llmSuitPercent,
    String? yoloLabel,
    double? yoloConf,
    String? mlLabel,
    double? mlConf,
  }) {
    final llmL = _unifyName(llmLabel);
    final yoloL = _unifyName(yoloLabel);
    final mlL = _unifyName(mlLabel);

    if (mlL.isNotEmpty && _blockedMlLabels.contains(mlL)) {
      final disagree = _labelsAgreeLoose(mlL, llmL) == false &&
          _labelsAgreeLoose(mlL, yoloL) == false;
      if (disagree) {
        mlConf = 0.0;
      }
    }

    final llmC = (llmConf != null && llmConf > 0)
        ? llmConf!.clamp(0.0, 1.0)
        : (((llmSuitPercent ?? 0) / 100.0) * 0.95);

    final cand = <Map<String, dynamic>>[];

    void add(String src, String? lab, double? conf, double prior, double min) {
      final l = _unifyName(lab);
      if (l.isEmpty || conf == null) return;
      final c = conf.clamp(0.0, 1.0);
      if (c < min) return;
      cand.add({'src': src, 'lbl': l, 'c': c, 'p': prior});
    }

    add('llm', llmL, llmC, 1.00, 0.45);
    add('yolo', yoloL, yoloConf, 0.75, 0.45);
    add('ml', mlL, mlConf, 0.55, 0.50);

    if (cand.isEmpty) {
      _finalKindLabel = null;
      _finalKindConf = 0.0;
      _finalKindFromLLM = false;
      _scanLabel = 'Tidak Terdeteksi';
      if (mounted && !_isDisposing) setState(() {});
      return;
    }

    cand.sort((a, b) => ((b['c'] as double) * (b['p'] as double))
        .compareTo((a['c'] as double) * (a['p'] as double)));

    _finalKindLabel = cand.first['lbl'] as String;
    _finalKindConf = cand.first['c'] as double;
    _finalKindFromLLM = (cand.first['src'] == 'llm');
    _scanLabel = _finalKindLabel!;

    if (llmSuitPercent != null && llmSuitPercent > 0) {
      final guard = llmSuitPercent.clamp(0, 100).toDouble();
      if (_score < guard) {
        _score = guard;
        _percent.value = guard.round();
        _labelText = _labelForScore(_score);
        _suitabilityPct = _score.clamp(0, 100);
      }
    }

    if (mounted && !_isDisposing) setState(() {});
  }

  Future<Uint8List?> _tryYoloRoi(Uint8List original) async {
    final svc = _yoloSvc;
    if (svc == null) return null;
    try {
      final res = await svc.detectBestRoi224(original);
      if (res == null) {
        _roi224 = null;
        return null;
      }
      _yoloLabel = _sanitizeLabel(res.label);
      _yoloConf = res.conf;
      _roi224 = res.roi224;
      debugPrint('[YOLO] best="${res.label}" conf=${res.conf.toStringAsFixed(2)}');

      final shown = (_yoloLabel?.isEmpty ?? true) ? '-' : _yoloLabel!;
      _analysis.insert(0,
          'Deteksi (YOLO pelengkap): $shown (conf ${(res.conf * 100).toStringAsFixed(0)}%)');
      _autoScrollAnalysis();
      return res.roi224;
    } catch (e, st) {
      debugPrint('[YOLO] fail: $e\n$st');
      _roi224 = null;
      return null;
    }
  }

  Future<void> _analyzeBytes(Uint8List jpegBytes) async {
    final svc = _qualitySvc;
    if (svc == null) return;

    _llmResult = null;
    _lastJpeg = jpegBytes;
    _qualityOk = false;

    try {
      final t0 = DateTime.now();

      final res = await svc.inferFromJpeg(jpegBytes);
      _latQMs = DateTime.now().difference(t0).inMilliseconds;

      final freshPercent =
          _toDouble(res['fresh_percent'] ?? res['quality_percent'] ?? 0.0);
      final p = freshPercent.isNaN ? 0 : freshPercent.round();
      _percent.value = p.clamp(0, 100);
      _score = _percent.value.toDouble();

      final List<dynamic> topRaw = (res['top'] as List?) ?? const [];
      final Map<String, dynamic> probsRaw = (res['probs'] is Map)
          ? Map<String, dynamic>.from(res['probs'] as Map)
          : const {};

      final List<Map<String, dynamic>> top =
          topRaw.map<Map<String, dynamic>>((e) {
        if (e is Map) {
          return {
            'label': (e['label'] ?? '-').toString(),
            'prob': _toDouble(e['prob'] ?? e['score'] ?? e['value'] ?? 0.0),
          };
        }
        return {'label': '-', 'prob': 0.0};
      }).toList();

      _lastTopK = top;

      if (top.isNotEmpty) {
        final first = top.first;
        _clsLabel = (first['label'] ?? '').toString();
        _clsProb = _toDouble(first['prob'] ?? 0.0);

        if (probsRaw.isNotEmpty) {
          double sumTop = 0.0;
          double firstProb = 0.0;
          probsRaw.forEach((k, v) {
            final pv = _toDouble(v);
            sumTop += pv;
            if (_unifyName(k.toString()) == _unifyName(_clsLabel)) {
              firstProb = pv;
            }
          });
          _clsProbCal =
              sumTop > 0 ? (firstProb / sumTop).clamp(0.0, 1.0) : _clsProb;
        } else {
          _clsProbCal = _clsProb;
        }
      } else {
        _clsLabel = null;
        _clsProb = 0.0;
        _clsProbCal = 0.0;
      }

      _updateFinalKind(
        llmLabel: null,
        llmConf: null,
        yoloLabel: (_yoloLabel?.isNotEmpty == true) ? _yoloLabel : null,
        yoloConf: _yoloConf,
        mlLabel: null,
        mlConf: null,
      );

      _qualityOk = true;

      if (_shouldAutoLLM) {
        await _triggerLLM(_imageBytes ?? jpegBytes);
      }
    } catch (e, st) {
      debugPrint('[SCAN] inferFromJpeg error: $e\n$st');
      _qualityOk = false;
      _tfliteBrokenOnce = true;
    }
  }

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
    if (x <= 5.0) return (x / 5.0).clamp(0.0, 1.0);
    if (x <= 10.0) return (x / 10.0).clamp(0.0, 1.0);
    if (x <= 100.0) return (x / 100.0).clamp(0.0, 1.0);
    return (x / 100.0).clamp(0.0, 1.0);
  }

  Future<void> _triggerLLM(Uint8List jpegBytes, {bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _llmLastCall != null &&
        now.difference(_llmLastCall!) < _llmCooldown) {
      return;
    }
    if (!force && !_shouldAutoLLM) {
      debugPrint(
          '[LLM] Skip: not needed (yoloConf=${_yoloConf.toStringAsFixed(2)}, clsProb=${_clsProb.toStringAsFixed(2)}, band=$_inLLMBand).');
      return;
    }

    _llmLastCall = now;
    if (_llmLoading) return;
    _llmLoading = true;
    if (mounted && !_isDisposing) setState(() {});

    try {
      final auth = context.read<AuthProvider>();
      final token = auth.token;
      if (token == null || token.isEmpty) {
        _notify('Validasi LLM gagal: token login tidak ada/expired.');
        return;
      }

      final bytesForLlm = _bestBytesForLLM(jpegBytes);

      final t0 = DateTime.now();
      final resp = await _aiApi.validateImage(bytesForLlm, bearerToken: token);
      _latLLMMs = DateTime.now().difference(t0).inMilliseconds;

      if (resp is Map &&
          (resp['error_code'] == 429 ||
              resp['error'] == 'rate_limited' ||
              resp['error_code'] == 503 ||
              resp['error'] == 'service_busy' ||
              resp['error_code'] == 504 ||
              resp['error'] == 'timeout' ||
              resp['status'] == 'error')) {
        _analysis.insert(0, 'Validasi LLM di-skip (rate limit/busy/timeout).');
        _autoScrollAnalysis();

        _llmResult = Map<String, dynamic>.from(
          (resp['result'] is Map) ? resp['result'] as Map : {},
        );

        _updateFinalKind(
          llmLabel: null,
          llmConf: 0.0,
          llmSuitPercent: null,
          yoloLabel: (_yoloLabel?.isNotEmpty == true) ? _yoloLabel : null,
          yoloConf: _yoloConf,
          mlLabel: null,
          mlConf: null,
        );

        _llmLoading = false;
        if (mounted && !_isDisposing) setState(() {});
        return;
      }

      final Map<String, dynamic> respMap =
          (resp is Map) ? Map<String, dynamic>.from(resp) : <String, dynamic>{};
      final Map<String, dynamic> data = _extractLlmCore(respMap);

      final String? llmLabel = (data['detected_item'] ??
          data['label'] ??
          data['class'] ??
          data['category'])?.toString();

      double llmConf = _toDouble(data['confidence']);
      if (llmConf > 1.0) llmConf /= 100.0;

      double? llmSuitPercent;
      final sp = _toDouble(data['suitability_percent']);
      if (sp > 0) {
        llmSuitPercent = sp;
      } else if (data['quality_percent'] != null) {
        final qp = _toDouble(data['quality_percent']);
        llmSuitPercent = (qp > 0) ? (qp * (llmConf > 0 ? llmConf : 1.0)) : null;
      }

      _llmResult = {
        'detected_item': _unifyName(llmLabel),
        'confidence': llmConf,
        'suitability_percent': llmSuitPercent,
        'raw': data,
      };

      if (llmSuitPercent != null && llmSuitPercent > 0) {
        _percent.value = llmSuitPercent.clamp(0, 100).round();
        _score = _percent.value.toDouble();
        _labelText = _labelForScore(_score);
        _suitabilityPct = _score.clamp(0, 100);
      }

      _updateFinalKind(
        llmLabel: llmLabel,
        llmConf: llmConf,
        llmSuitPercent: llmSuitPercent,
        yoloLabel: _yoloLabel,
        yoloConf: _yoloConf,
        mlLabel: _clsLabel,
        mlConf: _clsProb,
      );

      final llmShown = _unifyName(llmLabel);
      _analysis.insert(
        0,
        'LLM: ${llmShown.isEmpty ? "-" : llmShown} '
        '(conf ${(llmConf * 100).toStringAsFixed(0)}% • suit ${llmSuitPercent?.toStringAsFixed(0) ?? "-"}%)',
      );
      _autoScrollAnalysis();

      debugPrint('[LLM] label=$llmLabel conf=${llmConf.toStringAsFixed(2)} suit=${llmSuitPercent ?? '-'}');
      debugPrint('[YOLO] label=${_yoloLabel ?? '-'} conf=${_yoloConf.toStringAsFixed(2)}');
    } catch (e, st) {
      debugPrint('[LLM] error: $e\n$st');
      _llmResult = {'error': e.toString()};
      _analysis.insert(0, 'Validasi LLM gagal (service busy/overloaded) — skip.');
      _autoScrollAnalysis();
      _notify('Validasi LLM gagal: ${e.toString().replaceAll(RegExp(r"Exception: ?"), "")}');
    } finally {
      _llmLoading = false;
      if (mounted && !_isDisposing) setState(() {});
    }
  }

  void _autoScrollSteps() {
    if (_stepsScrollC.hasClients) {
      final max = _stepsScrollC.position.maxScrollExtent;
      _stepsScrollC.animateTo(
        max,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    _autoScrollAnalysis();
  }

  void _autoScrollAnalysis() {
    if (!_analysisScrollC.hasClients) return;
    final max = _analysisScrollC.position.maxScrollExtent;
    _analysisScrollC.animateTo(
      max,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  // ---- Pipeline utama ----
  Future<void> _runPipeline(Uint8List original) async {
    await _ensureSvcs();

    _progressC
      ..reset()
      ..forward();

    _lastJpeg = original;

    for (var i = 0; i < _steps.length; i++) {
      if (!mounted || _isDisposing) return;
      setState(() => _stepIndex = i);
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoScrollSteps());
      await Future.delayed(const Duration(milliseconds: 750));
    }

    Uint8List? roi224 = await _tryYoloRoi(original);

    final bool roiGood = (_yoloConf >= 0.60) && (roi224 != null);
    final Uint8List bytesForQuality = roiGood ? roi224! : _prepSquareBytes(original, 224);

    await _analyzeBytes(bytesForQuality);

    if (!_qualityOk && !_tfliteBrokenOnce) {
      _analysis.insert(0, 'Retry quality (fallback center-crop 224)');
      _autoScrollAnalysis();
      final b2 = _prepSquareBytes(original, 224);
      await _analyzeBytes(b2);
    }

    if (!_qualityOk) {
      await _triggerLLM(original, force: true);
    }

    if (!_qualityOk && (_llmResult == null || _llmResult?['error'] != null)) {
      final h = _heuristicScoreFromImage(bytesForQuality, yoloConf: _yoloConf);
      _percent.value = h;
      _score = h.toDouble();
      _analysis.insert(0, 'Top-K quality: fallback heuristik (brightness + YOLO).');
      _autoScrollAnalysis();
    }

    _labelText = _labelForScore(_score);

    final jenisLine =
        (_qualityOk && _clsLabel != null && _clsLabel!.isNotEmpty)
            ? 'Jenis (ML): ${_unifyName(_clsLabel)} (conf ${(100 * _clsProb).toStringAsFixed(0)}%)'
            : 'Jenis (ML): -';

    // ========= OPSIONAL: koreksi bias “olive” bila LLM gagal =========
    if ((_finalKindLabel == null || _finalKindConf < 0.6) &&
        (_clsLabel?.toLowerCase() == 'olive') &&
        _looksBananaYellow(_lastJpeg ?? _imageBytes ?? Uint8List(0))) {
      _updateFinalKind(
        llmLabel: null,
        llmConf: 0.0,
        yoloLabel: 'banana',
        yoloConf: math.max(_yoloConf, 0.60),
        mlLabel: null,
        mlConf: null,
      );
    }
    // =================================================================

    _updateFinalKind(
      llmLabel: (_llmResult?['detected_item'] as String?),
      llmConf: _toDouble(_llmResult?['confidence']),
      llmSuitPercent: (_llmResult?['suitability_percent'] is num)
          ? (_llmResult?['suitability_percent'] as num).toDouble()
          : (double.tryParse(
              (_llmResult?['suitability_percent'])?.toString() ?? '')),
      yoloLabel: (_yoloLabel?.isNotEmpty == true) ? _yoloLabel : null,
      yoloConf: _yoloConf,
      mlLabel: null,
      mlConf: null,
    );

    final jenisGabungan =
        (_finalKindLabel != null && _finalKindLabel!.isNotEmpty)
            ? 'Prediksi jenis (gabungan): ${_unifyName(_finalKindLabel)} (conf ${(100 * _finalKindConf).toStringAsFixed(0)}%)'
            : 'Prediksi jenis (gabungan): -';

    _analysis = [
      'Skor kelayakan (final): ${_score.toStringAsFixed(1)}%',
      jenisGabungan,
      jenisLine,
      'Validasi LLM: otomatis bila YOLO conf di 50–70%, YOLO conf < 55%, atau skor kualitas sangat rendah.',
      ..._analysis,
    ];

    _eligibilityText = _score >= 70
        ? 'Produk layak untuk dijual. Kualitas baik dan masa simpan memadai.'
        : 'Produk belum layak dijual. Silakan ulangi atau pilih produk lain.';

    _suitabilityPct = _score.clamp(0, 100);
    final predictedCombined = (_finalKindLabel?.isNotEmpty == true)
        ? _finalKindLabel!
        : ((_clsLabel?.isNotEmpty == true)
            ? _clsLabel!
            : ((_yoloLabel?.isNotEmpty == true)
                ? _yoloLabel!
                : 'Tidak Terdeteksi'));
    _scanLabel = _unifyName(predictedCombined);

    if (!mounted || _isDisposing) return;
    setState(() => _status = ScanStatus.result);
  }

  String _labelForScore(double s) {
    if (s >= 90) return 'Sangat Layak';
    if (s >= 80) return 'Cukup Layak';
    if (s >= 65) return 'Layak';
    return 'Tidak Layak';
  }

  int _fuseScores({
    required int tflitePercent,
    required double yoloConf,
    double? geminiScore01,
    double? geminiConf01,
    bool? isFruitVeg,
    String? llmLabel,
  }) {
    final t01 = (tflitePercent / 100).clamp(0.0, 1.0);
    final y01 = yoloConf.clamp(0.0, 1.0);
    final gconf = (geminiConf01 ?? 0).clamp(0.0, 1.0);

    double g01 = (geminiScore01 ?? t01).clamp(0.0, 1.0);
    g01 = _penalizeGeminiQualityByKeywords(llmLabel, g01) ?? g01;

    final bool strongLLM = (isFruitVeg == true) && gconf >= 0.90;
    final bool llmGood = (isFruitVeg == true) && gconf >= 0.85 && g01 >= 0.72;
    final bool mlWeak = _clsProb <= 0.55;
    final bool agreeYolo =
        _labelsAgreeLoose(llmLabel, _yoloLabel) ||
            _labelsAgreeLoose(llmLabel, _clsLabel);

    double wT, wY, wG;
    if (llmGood) {
      wT = mlWeak ? 0.05 : 0.15;
      wY = agreeYolo ? 0.20 : 0.15;
      wG = 1.0 - (wT + wY);
    } else {
      wT = _qualityOk ? (0.35 + 0.25 * _clsProb).clamp(0.15, 0.60) : 0.10;
      wY = (0.10 + 0.20 * y01).clamp(0.10, 0.25);
      final minG = strongLLM ? 0.50 : 0.25;
      wG = (1.0 - (wT + wY)).clamp(minG, 0.70);
    }

    double fused01 = (t01 * wT) + (y01 * wY) + (g01 * gconf * wG);

    if (llmGood) {
      final guardMin = g01 * (0.85 + 0.10 * y01);
      fused01 = math.max(fused01, guardMin);
    }

    if (_hasDefectKeyword(llmLabel)) {
      fused01 = math.min(fused01, 0.45);
      if (t01 < 0.40) fused01 = math.min(fused01, 0.30);
    }
    if (isFruitVeg == false) fused01 = math.min(fused01, 0.35);

    return (fused01.clamp(0.0, 1.0) * 100).round();
  }

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
    if (!mounted || _isDisposing) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Error'),
        content: Text(msg),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'))
        ],
      ),
    );
  }

  void _notify(String msg) {
    if (!mounted || _isDisposing) return;
    String clean = msg.replaceAll(RegExp(r'https?://\S+'), '').trim();
    if (clean.length > 160) clean = '${clean.substring(0, 160)}…';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(clean)));
  }

  Uint8List? _bestCreateImageBytes() => _roi224 ?? _imageBytes;

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

    final predicted = (_finalKindLabel?.isNotEmpty == true)
        ? _finalKindLabel
        : (_clsLabel?.isNotEmpty == true ? _clsLabel : _yoloLabel);

    final double s = _score.clamp(0, 100).toDouble();
    final payload = <String, Object?>{
      'initialSuitabilityPercent': s,
      'predictedLabel': _unifyName(predicted),
      'capturedImageBytes': bytes,
      'freshness_score': s,
      'suitability_percent': s,
      'score': s,
      'label': _labelText,
      'analysis': _analysis,
      'imageBytes': bytes,
      'filename': filename,
      'eligible': s >= 70,
      'name': (_analysis.isNotEmpty && _analysis.first.startsWith('Deteksi'))
          ? _analysis.first.replaceFirst(
              RegExp(r'^Deteksi(\s\(LLM\)|\s\(YOLO pelengkap\))?:\s'), '')
          : (_unifyName(predicted) ?? 'Produk Hasil Scan'),
    };

    if (!mounted || _isDisposing) return;

    final routes = const ['/seller/create-from-scan', '/create-from-scan'];
    bool pushed = false;
    for (final r in routes) {
      try {
        await Navigator.pushNamed(context, r, arguments: payload);
        pushed = true;
        break;
      } catch (_) {}
    }
    if (!pushed) {
      _notify(
          'Route create-from-scan tidak ditemukan. Pastikan didaftarkan di routes.');
    }
  }

  Future<void> _finishLegacyPop() async {
    Navigator.of(context).maybePop({
      'score': _score,
      'label': _labelText,
      'imagePath': _imageFile?.path,
      'details': _analysis,
      'initialSuitabilityPercent': _score.clamp(0, 100),
      'predictedLabel': _unifyName(_finalKindLabel ?? _clsLabel ?? _yoloLabel),
    });
  }

  void _finish() {
    if (_imageBytes == null) {
      if (mounted && !_isDisposing) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Ambil foto dulu.')));
      }
      return;
    }

    final double s = _suitabilityPct.toDouble().clamp(0, 100);
    final args = <String, Object?>{
      'initialSuitabilityPercent': s,
      'predictedLabel':
          (_scanLabel.isEmpty || _scanLabel == 'Tidak Terdeteksi')
              ? null
              : _unifyName(_scanLabel),
      'capturedImageBytes': _imageBytes,
      'freshness_score': s,
      'suitability_percent': s,
      'score': s,
      'label': _unifyName(_scanLabel),
      'analysis': List<String>.from(_analysis),
      'imageBytes': _imageBytes,
      'filename': _filename ?? 'scan.jpg',
      'eligible': s >= 70,
      'name': _scanLabel.isEmpty ? 'Produk Hasil Scan' : _unifyName(_scanLabel),
    };

    if (!mounted || _isDisposing) return;
    Navigator.pushNamed(context, '/create-from-scan', arguments: args);
  }

  // =================== OPSIONAL: mitigasi bias “olive” ===================
  bool _looksBananaYellow(Uint8List bytes) {
    try {
      final im0 = img.decodeImage(bytes);
      if (im0 == null) return false;
      final im = img.copyResize(im0, width: 64, height: 64);
      double H = 0, S = 0, V = 0;
      int n = 0;
      for (var y = 0; y < im.height; y += 2) {
        for (var x = 0; x < im.width; x += 2) {
          final p = im.getPixel(x, y);
          final r = (p.r as num).toDouble() / 255.0;
          final g = (p.g as num).toDouble() / 255.0;
          final b = (p.b as num).toDouble() / 255.0;
          final mx = math.max(r, math.max(g, b));
          final mn = math.min(r, math.min(g, b));
          final d = mx - mn;
          double h = 0;
          if (d != 0) {
            if (mx == r) {
              h = ((g - b) / d) % 6;
            } else if (mx == g) {
              h = ((b - r) / d) + 2;
            } else {
              h = ((r - g) / d) + 4;
            }
          }
          h = (h * 60);
          if (h < 0) h += 360;
          final s = mx == 0 ? 0 : d / mx;
          final v = mx;
          H += h;
          S += s;
          V += v;
          n++;
        }
      }
      if (n == 0) return false;
      final hMean = H / n;
      final sMean = S / n;
      final vMean = V / n;
      // kisaran "kuning pisang" yang cukup selektif
      return (hMean >= 40 && hMean <= 70 && sMean >= 0.25 && vMean >= 0.35);
    } catch (_) {
      return false;
    }
  }
  // =======================================================================

  // =================== (2) Kartu ringkasan LLM ===================
  Widget _buildLlmSummaryCard() {
    if (_llmResult == null || _llmResult!.isEmpty) {
      return const SizedBox.shrink();
    }

    final result = _llmResult!;
    final detected = _pick<String>(result, 'detected_item') ??
        _pick<String>(result, 'label') ??
        _pick<String>(result, 'class') ??
        _pick<String>(result, 'category') ??
        '-';

    final conf01 = _as01(_pick(result, 'confidence'));
    final suitPct = (_pick<double>(result, 'suitability_percent') ?? 0)
        .clamp(0, 100)
        .toDouble();
    final maturity = _pick<String>(result, 'maturity_label');
    final isFV = _pick<bool>(result, 'is_fruit_or_veg');
    final notesRaw = result['notes'];
    final List<String> notes = notesRaw is List
        ? notesRaw.map((e) => e.toString()).toList()
        : (notesRaw is String && notesRaw.isNotEmpty ? [notesRaw] : const []);

    Color confColor() {
      if (conf01 >= 0.9) return const Color(0xFF1B5E20);
      if (conf01 >= 0.75) return const Color(0xFF2E7D32);
      if (conf01 >= 0.6) return const Color(0xFFFB8C00);
      return const Color(0xFFE53935);
    }

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified, color: Color(0xFF1E88E5)),
              const SizedBox(width: 8),
              const Text('Validasi LLM (Ringkasan)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (isFV != null)
                Chip(
                  label: Text(isFV ? 'Fruit/Vegetable' : 'Non FV'),
                  avatar: Icon(isFV ? Icons.eco : Icons.block,
                      size: 16, color: isFV ? Colors.green : Colors.red),
                  backgroundColor:
                      (isFV ? Colors.green : Colors.red).withOpacity(.08),
                  labelStyle: TextStyle(
                    color: isFV ? Colors.green[800] : Colors.red[800],
                    fontWeight: FontWeight.w600,
                  ),
                  shape: StadiumBorder(
                      side: BorderSide(color: Colors.grey.shade200)),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Detected item
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.local_florist, color: Colors.black54, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  detected,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Metrik
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Confidence',
                        style:
                            TextStyle(fontSize: 12, color: Colors.black54)),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: conf01,
                        minHeight: 10,
                        backgroundColor: Colors.grey.shade200,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(confColor()),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('${(conf01 * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                            fontSize: 12,
                            color: confColor(),
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Suitability',
                        style:
                            TextStyle(fontSize: 12, color: Colors.black54)),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: (suitPct / 100).clamp(0.0, 1.0),
                        minHeight: 10,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF43A047)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('${suitPct.toStringAsFixed(0)}%',
                        style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF2E7D32),
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),

          if (maturity != null && maturity.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: -6,
              children: [
                Chip(
                  label: Text('Maturity: $maturity'),
                  avatar: const Icon(Icons.insights,
                      size: 16, color: Colors.orange),
                  backgroundColor: Colors.orange.withOpacity(.08),
                  shape: StadiumBorder(
                      side: BorderSide(color: Colors.orange.withOpacity(.15))),
                  labelStyle: const TextStyle(
                      color: Colors.orange, fontWeight: FontWeight.w700),
                ),
                if (_finalKindLabel?.isNotEmpty == true)
                  Chip(
                    label: Text('Prediksi akhir: ${_finalKindLabel!}'),
                    avatar: const Icon(Icons.check_circle,
                        size: 16, color: Colors.green),
                    backgroundColor: Colors.green.withOpacity(.08),
                    shape: StadiumBorder(
                        side: BorderSide(color: Colors.green.withOpacity(.15))),
                    labelStyle: const TextStyle(
                        color: Colors.green, fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ],

          if (notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Catatan LLM',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            ...notes.map((n) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Icon(Icons.fiber_manual_record,
                            size: 8, color: Colors.black45),
                      ),
                      const SizedBox(width: 6),
                      Expanded(child: Text(n)),
                    ],
                  ),
                )),
          ],

          const SizedBox(height: 8),
          // Toggle JSON mentah
          Theme(
            data:
                Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Row(
                children: const [
                  Icon(Icons.code, size: 18, color: Colors.black54),
                  SizedBox(width: 6),
                  Text('Lihat JSON mentah',
                      style: TextStyle(
                          color: Colors.black54, fontWeight: FontWeight.w600)),
                ],
              ),
              children: [
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B1020),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(
                    _prettyJson(result),
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        color: Color(0xFFE8F1FF),
                        fontSize: 12,
                        height: 1.3),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =================== (3) Footer Insight ===================
// GANTI seluruh _buildScanInsightsFooter() dengan ini
Widget _buildScanInsightsFooter() {
  // Pakai guard: kalau _suitabilityPct sudah diisi, pakai itu; kalau belum pakai _score
  final double score =
      ((_suitabilityPct > 0 ? _suitabilityPct : _score).clamp(0, 100)).toDouble();
  final maturity =
      _pick<String>(_llmResult, 'maturity_label')?.toLowerCase() ?? '';

  String advice;
  if (score >= 85) {
    advice = 'Siap jual. Tampilkan di rak utama. Pastikan penyimpanan kering & sejuk.';
  } else if (score >= 70) {
    advice = 'Cukup layak. Jual cepat / bundling promo agar rotasi stok terjaga.';
  } else if (maturity.contains('matang')) {
    advice = 'Segera olah / diskon cepat. Masa simpan pendek karena matang.';
  } else {
    advice = 'Tunda penjualan. Periksa pencahayaan & ulangi scan untuk konfirmasi.';
  }

  // Tampilkan metrik yang tidak gampang "nge-clip" + aman di layar kecil
  Widget metric(String title, String value, IconData icon) {
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.black54, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w800),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
        ],
      ),
    );
  }

  // ——— LLM conf yang robust (tidak memaksa 0% kalau datanya belum ada) ———
  String _llmConfText() {
    if (_llmResult == null) return '-';
    // coba baca confidence (0..1 atau 0..100)
    final c01 = _as01(_pick(_llmResult, 'confidence'));
    if (c01 > 0) return '${(c01 * 100).toStringAsFixed(0)}%';

    // kalau ada error dari LLM, tampilkan tanda
    if (_llmResult?['error'] != null) return '— (err)';

    // kalau tidak ada confidence tapi ada suitability, tampilkan perkiraan
    final suit = _pick<double>(_llmResult, 'suitability_percent');
    if (suit != null && suit > 0) return '~${suit.clamp(0, 100).toStringAsFixed(0)}%';

    return '-';
  }

  return Container(
    margin: const EdgeInsets.only(top: 16, bottom: 8),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      border: Border.all(color: Colors.grey.shade100),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Insight & Tindakan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(score >= 70 ? Icons.shopping_bag : Icons.warning_amber_rounded,
                color: score >= 70 ? Colors.green : Colors.orange),
            const SizedBox(width: 8),
            Expanded(child: Text(advice)),
          ],
        ),
        const SizedBox(height: 12),

        // Wrap responsif (ganti GridView lama) → tidak ada clip di device kecil
        LayoutBuilder(
          builder: (context, c) {
            final double w = (c.maxWidth - 8) / 2; // 2 kolom, 8px spacing
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: w,
                  child: metric('Final label', (_finalKindLabel ?? '-'), Icons.local_florist),
                ),
                SizedBox(
                  width: w,
                  child: metric('Final conf', '${(100 * _finalKindConf).toStringAsFixed(0)}%', Icons.percent),
                ),
                SizedBox(
                  width: w,
                  child: metric('YOLO conf', '${(100 * _yoloConf).toStringAsFixed(0)}%', Icons.center_focus_strong),
                ),
                SizedBox(
                  width: w,
                  child: metric('LLM conf', _llmConfText(), Icons.verified),
                ),
              ],
            );
          },
        ),

        if (_latQMs != null || _latLLMMs != null) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: -6, children: [
            if (_latQMs != null)
              Chip(
                label: Text('TFLite ${_latQMs} ms'),
                avatar: const Icon(Icons.speed, size: 16, color: Colors.indigo),
                backgroundColor: Colors.indigo.withOpacity(.08),
                shape: StadiumBorder(side: BorderSide(color: Colors.indigo.withOpacity(.15))),
                labelStyle: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.w700),
              ),
            if (_latLLMMs != null)
              Chip(
                label: Text('LLM ${_latLLMMs} ms'),
                avatar: const Icon(Icons.cloud, size: 16, color: Colors.blueGrey),
                backgroundColor: Colors.blueGrey.withOpacity(.08),
                shape: StadiumBorder(side: BorderSide(color: Colors.blueGrey.withOpacity(.15))),
                labelStyle: const TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.w700),
              ),
          ]),
        ],
      ],
    ),
  );
}


  // ---- UI ----
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('AI Product Scanner',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: _status != ScanStatus.initial
            ? IconButton(
                icon: const Icon(Icons.arrow_back), onPressed: _resetScan)
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
        return _buildProcessingUI(); // versi scrollable (overflow fixed)
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
                style: TextStyle(
                    fontSize: 16, color: Colors.grey[600], height: 1.5),
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
                      subtitle:
                          'Model telah dikalibrasi dengan ribuan sampel',
                    ),
                    SizedBox(height: 16),
                    _FeatureItem(
                      icon: Icons.speed,
                      title: 'Analisis cepat < 10 detik',
                      subtitle:
                          'Proses deteksi real-time dengan teknologi terkini',
                    ),
                    SizedBox(height: 16),
                    _FeatureItem(
                      icon: Icons.verified_outlined,
                      title: 'Hasil terpercaya',
                      subtitle:
                          'Validasi multi-parameter untuk akurasi maksimal',
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

  // ---- Processing (overflow fixed: scrollable + elastis) ----
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
        child: LayoutBuilder(
          builder: (_, c) => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            physics: const BouncingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight - 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  // ==== preview gambar + scanline ====
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
                                    child:
                                        ColoredBox(color: Color(0xFFF0F0F0)),
                                  )),
                      ),
                      Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: AppColors.primaryGreen, width: 2),
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
                                    gradient: LinearGradient(colors: [
                                      AppColors.primaryGreen,
                                      _kPrimaryGreenLight
                                    ]),
                                    boxShadow: [
                                      BoxShadow(
                                          color: AppColors.primaryGreen,
                                          blurRadius: 10)
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
                  const SizedBox(height: 24),
                  const Text('Analyzing with AI',
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark)),
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
                                style: TextStyle(
                                    fontSize: 14, color: Colors.grey[700])),
                          )
                        : const SizedBox(height: 8),
                  ),
                  const SizedBox(height: 12),
                  // ==== progress bar ====
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
                              gradient: const LinearGradient(colors: [
                                AppColors.primaryGreen,
                                _kPrimaryGreenLight
                              ]),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ==== Kartu "Machine Learning Process" dengan scroll internal aman ====
                  Container(
                    constraints: const BoxConstraints(minHeight: 180),
                    padding: const EdgeInsets.all(20),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10)
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Machine Learning Process',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 160, // aman di device pendek
                          child: ListView.builder(
                            physics: const BouncingScrollPhysics(),
                            itemCount: _steps.length,
                            itemBuilder: (_, i) {
                              final done = i <= _stepIndex;
                              final cur = i == _stepIndex;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  children: [
                                    AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 250),
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: done
                                            ? AppColors.primaryGreen
                                            : Colors.grey[300],
                                      ),
                                      child: done
                                          ? const Icon(Icons.check,
                                              size: 16, color: Colors.white)
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _steps[i],
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: done
                                              ? AppColors.textDark
                                              : Colors.grey[400],
                                          fontWeight: cur
                                              ? FontWeight.w600
                                              : FontWeight.normal,
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
                                              AlwaysStoppedAnimation<Color>(
                                                  AppColors.primaryGreen),
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

                  const SizedBox(height: 12),

                  // ==== Log analisis ====
                  if (_analysis.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10)
                        ],
                      ),
                      child: Text(
                        'Log akan tampil di sini…',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10)
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final e in _analysis)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(top: 6),
                                    child: Icon(Icons.circle,
                                        size: 6,
                                        color: AppColors.primaryGreen),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      e,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          color: AppColors.textDark),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 20),

                  // Chip "Powered by ..."
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: const BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.all(Radius.circular(20))),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome,
                            color: Colors.amber, size: 16),
                        SizedBox(width: 8),
                        Text('Powered by TFLite + Gemini',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500))
                      ],
                    ),
                  ),
                ],
              ),
            ),
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
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
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
                  BoxShadow(
                      color: color.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10))
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
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.3)
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 12,
                      left: 12,
                      child: Builder(
                        builder: (_) {
                          final bestLabel =
                              _unifyName((_finalKindLabel?.isNotEmpty == true)
                                  ? _finalKindLabel!
                                  : ((_clsLabel?.isNotEmpty == true)
                                      ? _clsLabel!
                                      : (_yoloLabel?.isNotEmpty == true
                                          ? _yoloLabel!
                                          : '')));

                          return Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: ok
                                          ? AppColors.primaryGreen
                                          : _kErrorColor),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                        ok
                                            ? Icons.verified
                                            : Icons.error_outline,
                                        size: 16,
                                        color: ok
                                            ? AppColors.primaryGreen
                                            : _kErrorColor),
                                    const SizedBox(width: 6),
                                    Text(
                                      _labelText,
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (bestLabel.isNotEmpty)
                                Chip(
                                  label: Text(bestLabel),
                                  avatar: const Icon(
                                    Icons.local_florist,
                                    size: 16,
                                    color: AppColors.primaryGreen,
                                  ),
                                  backgroundColor:
                                      AppColors.primaryGreen.withOpacity(0.08),
                                  labelStyle: const TextStyle(
                                    color: AppColors.primaryGreen,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  shape: StadiumBorder(
                                    side: BorderSide(
                                      color: AppColors.primaryGreen
                                          .withOpacity(0.15),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
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
                        valueColor:
                            AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                    Column(
                      children: [
                        Icon(mood, size: 40, color: color),
                        const SizedBox(height: 8),
                        Text('${value.toStringAsFixed(1)}%',
                            style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: color)),
                        Text(_labelText,
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: color)),
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
                color: ok
                    ? AppColors.primaryGreen.withOpacity(0.08)
                    : _kErrorColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: ok ? AppColors.primaryGreen : _kErrorColor),
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
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDark),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // ===== Rincian Analisis =====
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10)
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Rincian Analisis',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),

                  for (final e in _analysis) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Icon(Icons.circle,
                            size: 8, color: AppColors.primaryGreen),
                        SizedBox(width: 8),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 16, bottom: 8),
                      child: Text(e,
                          style: const TextStyle(
                              fontSize: 14, color: AppColors.textDark)),
                    ),
                  ],

                  if (_llmResult != null) ...[
                    const SizedBox(height: 8),
                    Builder(builder: (_) {
                      final name = _unifyName(
                        (_llmResult!['detected_item'] ??
                                _llmResult!['label'] ??
                                _llmResult!['class'] ??
                                _llmResult!['category'] ??
                                '-')
                            .toString(),
                      );
                      final c = _toDouble(_llmResult!['confidence']);
                      final s =
                          _toDouble(_llmResult!['suitability_percent']);
                      return Text(
                          'LLM: $name (conf: ${c.toStringAsFixed(2)}, suit: ${s.toStringAsFixed(0)}%)',
                          style: const TextStyle(fontSize: 14));
                    }),
                  ],

                  if (_lastJpeg != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: (_llmLoading || onCooldown || _lastJpeg == null)
                          ? null
                          : () => _triggerLLM(_lastJpeg!, force: false),
                      onLongPress:
                          (_llmLoading || onCooldown || _lastJpeg == null)
                              ? null
                              : () => _triggerLLM(_lastJpeg!, force: true),
                      icon: _llmLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.verified),
                      label: Text(
                        onCooldown
                            ? 'Validasi LLM (tunggu ${((remainCooldownMs / 1000).ceil())}s)'
                            : _shouldAutoLLM
                                ? 'Validasi LLM sekarang'
                                : 'Validasi LLM (tahan untuk paksa)',
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ===== (4) Sisipan ringkasan LLM + Insight footer =====
            _buildLlmSummaryCard(),
            _buildScanInsightsFooter(),

            // ===== (4) Debug Scan (dipindah ke luar container rincian) =====
            if (_lastJpeg != null) ...[
              const SizedBox(height: 12),
              ExpansionTile(
                title: const Text('Debug Scan',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                childrenPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  if (_roi224 != null) ...[
                    const Text('ROI 224:'),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child:
                          Image.memory(_roi224!, height: 96, fit: BoxFit.cover),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                      'Jenis (gabungan overlay): ${_unifyName(_finalKindLabel)} (conf: ${(100 * _finalKindConf).toStringAsFixed(0)}%)'),
                  Text(
                      'Jenis (ML): ${_unifyName(_clsLabel)} (conf: ${(100 * _clsProb).toStringAsFixed(0)}%)'),
                  Text(
                      'YOLO: ${_unifyName(_yoloLabel).isEmpty ? "-" : _unifyName(_yoloLabel)} (conf: ${(100 * _yoloConf).toStringAsFixed(0)}%)'),
                  Text(
                      'q_quality: ${_latQMs ?? 0} ms${_latLLMMs != null ? ' • llm: ${_latLLMMs} ms' : ''}'),
                  const SizedBox(height: 8),
                  const Text('Top-K Quality (kelas):'),
                  ..._lastTopK.map((m) {
                    final lbl = _unifyName((m['label'] ?? '-').toString());
                    final v = (m['prob'] ?? m['score'] ?? m['value'] ?? 0);
                    final vv = (v is num) ? v : 0;
                    return Text('• $lbl : ${(100 * vv).toStringAsFixed(0)}%');
                  }),
                  const SizedBox(height: 8),
                  Text('LLM raw: ${_llmResult ?? '-'}'),
                  Text('Score akhir: ${_percent.value}% • Label: $_labelText'),
                ],
              ),
            ],

            const SizedBox(height: 24),

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
                    icon: const Icon(Icons.refresh,
                        color: AppColors.primaryGreen),
                    label: const Text('Scan Ulang',
                        style: TextStyle(
                            color: AppColors.primaryGreen,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _finish,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: AppColors.primaryGreen,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.check, color: Colors.white),
                    label: const Text('Selesai',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (ok) ...[
              TextButton.icon(
                onPressed: _finish,
                icon: const Icon(Icons.add_box_outlined),
                label: const Text('Buat Produk dari Hasil Scan'),
              ),
              TextButton.icon(
                onPressed: _finish,
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
          child:
              Transform.rotate(angle: -math.pi / 2, child: corner())),
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

  const _FeatureItem(
      {required this.icon, required this.title, required this.subtitle});

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
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppColors.textDark)),
              const SizedBox(height: 4),
              Text(subtitle,
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        ),
      ],
    );
  }
}
