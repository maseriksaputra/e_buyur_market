// lib/app/presentation/screens/scan/scan_screen.dart
// ignore_for_file: use_build_context_synchronously
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:e_buyur_market_flutter_5/app/core/theme/app_colors.dart';
import 'package:e_buyur_market_flutter_5/app/common/widgets/primary_app_bar.dart';
import 'package:e_buyur_market_flutter_5/app/core/routes.dart';
import 'package:e_buyur_market_flutter_5/app/core/network/api.dart';

import 'package:e_buyur_market_flutter_5/app/presentation/providers/auth_provider.dart';

// ✅ Perbaikan import (hapus segmen `lib/`)
import 'package:e_buyur_market_flutter_5/ml/hybrid_ai_service.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({Key? key}) : super(key: key);

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  CameraController? _cam;
  bool _busy = false;

  Uint8List? _imageBytes;
  String _filename = 'scan.jpg';

  // ——— state hasil analisis (ditampilkan di UI) ———
  String _scanLabel = 'Tidak Terdeteksi';
  String _scanConf = '0.0%';
  String _scanQuality = '0%';
  int _suitabilityPct = 0; // untuk progress ring / label kelayakan
  String _suitabilityText = 'Tidak Layak';
  List<String> _analysis = const [];

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cams = await availableCameras();
    final cam = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cams.first,
    );
    _cam = CameraController(
      cam,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await _cam!.initialize();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cam?.dispose();
    super.dispose();
  }

  // ——— tombol “Ambil Foto” ———
  Future<void> _takePicture() async {
    if (_cam == null || !_cam!.value.isInitialized) return;
    if (_busy) return;

    setState(() => _busy = true);
    try {
      final file = await _cam!.takePicture();
      _filename = 'scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final bytes = await file.readAsBytes();
      _imageBytes = bytes;

      await _analyze(bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengambil foto: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ——— panggil on-device ML + fallback Gemini jika perlu ———
  Future<void> _analyze(Uint8List bytes) async {
    // 1) ON-DEVICE (YOLO + quality)
    String? yoloLabel;
    double yoloConf = 0.0;
    double qualityScore01 = 0; // 0..1

    try {
      final hybrid = HybridAIService.instance; // pastikan ada singleton
      final out = await hybrid.runOnBytes(bytes); // <- method kamu

      // asumsi struktur umum:
      // out.top?.label (String?), out.top?.conf (0..1), out.quality (0..1)
      yoloLabel = out.top?.label;
      yoloConf = out.top?.conf ?? 0;
      qualityScore01 = (out.quality ?? 0).clamp(0, 1);
    } catch (_) {
      // biarin kosong, nanti coba fallback
    }

    // 2) Fallback LLM jika YOLO konf rendah / label null
    bool usedLLM = false;
    if ((yoloLabel == null || yoloLabel.trim().isEmpty) || yoloConf < 0.25) {
      try {
        final token = context.read<AuthProvider>().token;
        API.setBearer(token); // penting: hindari UNAUTHENTICATED

        final form = FormData.fromMap({
          'image': MultipartFile.fromBytes(bytes, filename: _filename),
        });
        final res = await API.dio.post('ai/gemini/validate-image', data: form);

        if (res.statusCode == 200 && res.data is Map) {
          final js = res.data as Map;
          final llmLabel = (js['detected_item'] as String?)?.trim();
          final llmConf = (js['confidence'] as num?)?.toDouble() ?? 0.0;
          final llmQuality01 =
              (js['quality_score'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 0.0;

          if ((llmLabel != null && llmLabel.isNotEmpty) || llmConf > 0) {
            usedLLM = true;
            yoloLabel = llmLabel?.isEmpty ?? true ? yoloLabel : llmLabel;
            // pakai angka terbaik yang tersedia
            yoloConf = math.max(yoloConf, llmConf);
            qualityScore01 = math.max(qualityScore01, llmQuality01);
          }
        }
      } catch (_) {
        // kalau gagal, biarkan hasil device saja
      }
    }

    // 3) hitung tampilan persentase & label kelayakan
    final confPct = (yoloConf * 100).clamp(0, 100);
    final qPct = (qualityScore01 * 100).clamp(0, 100).round();

    final suitability = qPct; // kamu bisa ubah rumus, mis: min(qPct, confPct)
    final suitText = suitability < 60
        ? 'Tidak Layak'
        : (suitability < 75
            ? 'Layak'
            : (suitability < 88 ? 'Cukup Layak' : 'Sangat Layak'));

    // 4) setState -> inilah yang dipakai badge & UI
    setState(() {
      _scanLabel = (yoloLabel == null || yoloLabel.isEmpty)
          ? 'Tidak Terdeteksi'
          : yoloLabel;
      _scanConf = '${confPct.toStringAsFixed(1)}%';
      _scanQuality = '$qPct%';
      _suitabilityPct = suitability;
      _suitabilityText = suitText;
      _analysis = [
        'Confidence deteksi: ${confPct.toStringAsFixed(1)}%',
        'Skor kelayakan (ML): $qPct%',
        if (usedLLM)
          'Validasi LLM: otomatis (low conf / grey zone / konflik).',
      ];
    });
  }

  // ——— kirim ke halaman CreateProductFromScanPage ———
  void _finish() {
    if (_imageBytes == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Ambil foto dulu.')));
      return;
    }

    final args = {
      'name': _scanLabel,
      'imageBytes': _imageBytes,
      'filename': _filename,
      'score': _suitabilityPct, // 0..100
      'label': _scanLabel,
      'analysis': _analysis,
    };

    Navigator.of(context).pushNamed(
      AppRoutes.createProductFromScan, // pastikan route ini ada
      arguments: args,
    );
  }

  @override
  Widget build(BuildContext context) {
    final camReady = _cam?.value.isInitialized ?? false;

    return Scaffold(
      appBar: const PrimaryAppBar(title: 'Scan Produk'),
      body: Column(
        children: [
          // ——— preview + badge label ———
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              children: [
                Positioned.fill(
                  child: _imageBytes == null
                      ? (camReady
                          ? CameraPreview(_cam!)
                          : Container(color: Colors.black12))
                      : Image.memory(_imageBytes!, fit: BoxFit.cover),
                ),
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.verified_rounded,
                            size: 16, color: Colors.green),
                        const SizedBox(width: 6),
                        // ⬇️ bind ke label deteksi
                        Text(_scanLabel,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ——— ring + status ———
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Column(
              children: [
                SizedBox(
                  width: 144,
                  height: 144,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 144,
                        height: 144,
                        child: CircularProgressIndicator(
                          value: _suitabilityPct / 100,
                          strokeWidth: 10,
                          color: _ringColor(_suitabilityPct.toDouble()),
                          backgroundColor:
                              _ringColor(_suitabilityPct.toDouble())
                                  .withOpacity(0.15),
                        ),
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${_suitabilityPct.toStringAsFixed(0)}%',
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(_suitabilityText,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _analysisCard(),
              ],
            ),
          ),

          const Spacer(),

          // ——— tombol ———
          SafeArea(
            top: false,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _takePicture,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label:
                          Text(_imageBytes == null ? 'Ambil Foto' : 'Scan Ulang'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryGreen),
                      onPressed: _busy ? null : _finish,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Selesai'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _analysisCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Rincian Analisis',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          for (final s in _analysis) _dotLine(s),
        ],
      ),
    );
  }

  Widget _dotLine(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 8, color: Colors.green),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Color _ringColor(double pct) {
    if (pct >= 90) return const Color(0xFF16A34A);
    if (pct >= 80) return const Color(0xFF22C55E);
    if (pct >= 70) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }
}
