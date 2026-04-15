// lib/app/presentation/screens/seller/scan/scan_seller_screen.dart
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../ml/suitability_service.dart';

class ScanSellerScreen extends StatefulWidget {
  const ScanSellerScreen({super.key});

  @override
  State<ScanSellerScreen> createState() => _ScanSellerScreenState();
}

class _ScanSellerScreenState extends State<ScanSellerScreen> {
  // === STATE & CONTROLLERS ===
  int _tflitePercent = 0; // skor cepat dari TFLite
  int? _hybridPercent;    // skor layer-2 (opsional; mis. validasi server/Gemini)
  final _percentNotifier = ValueNotifier<double>(0); // 0..1 untuk animasi gauge
  bool _isProcessing = false;

  Uint8List? _lastImageBytes; // untuk pratinjau hasil scan

  final _picker = ImagePicker();

  @override
  void dispose() {
    _percentNotifier.dispose();
    super.dispose();
  }

  // === Ambil gambar dari kamera/galeri ===
  Future<void> _pickFromCamera() async {
    final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    await _onImageScanned(bytes);
  }

  Future<void> _pickFromGallery() async {
    final x = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    await _onImageScanned(bytes);
  }

  // === Callback saat ada gambar hasil scan ===
  Future<void> _onImageScanned(Uint8List imageBytes) async {
    if (!mounted) return;
    setState(() {
      _isProcessing = true;
      _lastImageBytes = imageBytes;
      _hybridPercent = null; // reset hasil layer-2
    });

    try {
      // 1) skor cepat dari TFLite (langsung isi animasi)
      _tflitePercent = await SuitabilityService().computePercentFromImage(imageBytes);
      _animateTo(_tflitePercent.toDouble());

      // 2) kirim ke server untuk validasi layer-2 (opsional, non-blocking)
      //    Implementasikan sesuai backend kamu. Contoh stub:
      _triggerGeminiValidation(imageBytes);
    } catch (e) {
      // fallback aman: biarkan 0% dan tampilkan info ringan
      _animateTo(0);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menganalisis gambar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // === Animasi halus menuju target persen ===
  void _animateTo(double targetPercent) {
    final start = _percentNotifier.value; // 0..1
    final end = (targetPercent / 100.0).clamp(0.0, 1.0);
    const steps = 20;
    final step = (end - start) / steps;

    for (int i = 1; i <= steps; i++) {
      Future.delayed(Duration(milliseconds: 12 * i), () {
        if (mounted) {
          _percentNotifier.value = (start + step * i).clamp(0.0, 1.0);
        }
      });
    }
  }

  // === Stub validasi layer-2 (opsional) ===
  // Ganti implementasi ini untuk panggil endpoint kamu (misal upload image
  // ke server, server panggil Gemini, lalu server mengembalikan percent final).
  Future<void> _triggerGeminiValidation(Uint8List imageBytes) async {
    // Contoh: delay imitasi panggilan jaringan, lalu hasil "hybrid"
    await Future.delayed(const Duration(milliseconds: 600));
    final hybrid = (_tflitePercent * 0.9 + 5).clamp(0, 100).round(); // contoh racikan
    if (!mounted) return;
    setState(() {
      _hybridPercent = hybrid;
    });
    // Jika kamu ingin gauge mengikuti hybrid, jalankan lagi animasinya:
    _animateTo(_hybridPercent!.toDouble());
  }

  // === Widget gauge sederhana pakai ValueListenableBuilder ===
  Widget buildGauge() {
    return ValueListenableBuilder<double>(
      valueListenable: _percentNotifier,
      builder: (_, v, __) {
        final p = (v * 100).round();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 160,
              height: 160,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 160,
                    height: 160,
                    child: CircularProgressIndicator(
                      value: v,
                      strokeWidth: 12,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$p%',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _hybridPercent == null
                            ? 'Analisis cepat (TFLite)'
                            : 'Hybrid: ${_hybridPercent}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _descFromPercent(_hybridPercent ?? _tflitePercent),
              style: const TextStyle(fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        );
      },
    );
  }

  String _descFromPercent(int p) {
    if (p >= 85) return 'Sangat layak dijual';
    if (p >= 70) return 'Layak dijual';
    if (p >= 50) return 'Perlu dipertimbangkan';
    return 'Kurang layak — cek ulang';
    // Sesuaikan batas sesuai kebutuhanmu
  }

  // === UI ===
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Seller')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Preview gambar terakhir (jika ada)
          Container(
            height: 180,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E8EB)),
              color: const Color(0xFFF4F6F8),
            ),
            alignment: Alignment.center,
            child: _lastImageBytes == null
                ? const Text('Belum ada gambar')
                : ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      _lastImageBytes!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          // Gauge kelayakan
          Center(child: buildGauge()),
          const SizedBox(height: 16),
          // Tombol aksi
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isProcessing ? null : _pickFromCamera,
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Kamera'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isProcessing ? null : _pickFromGallery,
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.photo_library),
                  label: Text(_isProcessing ? 'Memproses…' : 'Galeri'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Tips: ambil foto produk dengan pencahayaan baik, fokus jelas, dan latar bersih untuk hasil analisis lebih akurat.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }
}
