// lib/app/presentation/screens/seller/add_product_screen.dart
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:dio/dio.dart'; // NEW: Dio for multipart
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:e_buyur_market_flutter_5/app/core/network/api.dart'; // NEW: API.dio base

import '../../../core/services/product_api_service.dart';
import '../../providers/auth_provider.dart';

// === NEW: import service ML ===
import '../../../../ml/suitability_service.dart';

class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});
  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  XFile? _xfile;
  bool _isUploading = false;

  late final ProductApiService _api;

  @override
  void initState() {
    super.initState();
    _api = ProductApiService();
    // suntik token agar Authorization terkirim
    // (AuthProvider sudah ada di widget tree)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final token = context.read<AuthProvider>().token;
      _api.setAuthToken(token);
      API.setBearer(token); // NEW: sekalian set ke Dio
    });
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final x =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x != null) setState(() => _xfile = x);
  }

  // NEW: helper untuk MultipartFile (Dio)
  Future<MultipartFile> _dioFileFromXFile(XFile x) async {
    final fileName = x.name.isNotEmpty ? x.name : 'product.jpg';
    if (kIsWeb) {
      final bytes = await x.readAsBytes();
      return MultipartFile.fromBytes(bytes, filename: fileName);
    } else {
      return await MultipartFile.fromFile(x.path, filename: fileName);
    }
  }

  // Label kesegaran berdasarkan percent (0..100)
  String _freshnessLabelFrom(int percent) {
    if (percent < 60) return 'Tidak Layak';
    if (percent < 75) return 'Layak';
    if (percent < 88) return 'Cukup Layak';
    return 'Sangat Layak';
  }

  Future<void> _openCreateSheet() async {
    final name = TextEditingController();
    final price = TextEditingController();
    final unit = TextEditingController(text: 'kg');
    final stock = TextEditingController(text: '1');
    final desc = TextEditingController();
    // NEW: nutrition
    final kalori = TextEditingController();
    final protein = TextEditingController();
    final vitaminC = TextEditingController();
    final serat = TextEditingController();
    // NEW: storage method + notes
    String? storageMethod;
    final storageNotes = TextEditingController();
    // NEW: category (buah/sayur) — default buah
    String category = 'buah';

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tambah Produk',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 12),
                TextField(
                    controller: name,
                    decoration:
                        const InputDecoration(labelText: 'Nama Produk')),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: price,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Harga (Rp)'))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: TextField(
                          controller: unit,
                          decoration: const InputDecoration(
                              labelText: 'Satuan (kg, ikat, dll)'))),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: stock,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Stok'))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: TextField(
                          controller: desc,
                          decoration:
                              const InputDecoration(labelText: 'Deskripsi'))),
                ]),
                const SizedBox(height: 12),
                // NEW: kategori
                DropdownButtonFormField<String>(
                  value: category,
                  items: const [
                    DropdownMenuItem(value: 'buah', child: Text('Buah')),
                    DropdownMenuItem(value: 'sayur', child: Text('Sayur')),
                  ],
                  onChanged: (v) => category = v ?? 'buah',
                  decoration:
                      const InputDecoration(labelText: 'Kategori (buah/sayur)'),
                ),
                const SizedBox(height: 16),
                const Text('Informasi Gizi (opsional)',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: kalori,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Kalori (kcal)'))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: TextField(
                          controller: protein,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Protein (g)'))),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: vitaminC,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Vitamin C (mg)'))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: TextField(
                          controller: serat,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Serat (g)'))),
                ]),
                const SizedBox(height: 16),
                const Text('Cara Simpan',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: storageMethod,
                  items: const [
                    DropdownMenuItem(value: 'room', child: Text('Suhu ruang')),
                    DropdownMenuItem(
                        value: 'chiller', child: Text('Kulkas / Chiller')),
                    DropdownMenuItem(value: 'freezer', child: Text('Freezer')),
                    DropdownMenuItem(
                        value: 'dry', child: Text('Tempat sejuk & kering')),
                    DropdownMenuItem(
                        value: 'other', child: Text('Lainnya (isi manual)')),
                  ],
                  onChanged: (v) => storageMethod = v,
                  decoration:
                      const InputDecoration(labelText: 'Pilih cara simpan'),
                ),
                const SizedBox(height: 8),
                TextField(
                    controller: storageNotes,
                    decoration: const InputDecoration(
                        labelText: 'Catatan penyimpanan (opsional)')),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(ctx, false),
                        icon: const Icon(Icons.close),
                        label: const Text('Batal'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pop(ctx, true),
                        icon: const Icon(Icons.check),
                        label: const Text('Simpan'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (ok != true) return;

    if (_xfile == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pilih gambar produk dulu')));
      }
      return;
    }

    // validasi simple
    if (name.text.trim().isEmpty || price.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nama & harga wajib diisi')),
        );
      }
      return;
    }

    // pastikan angka valid
    final priceInt = int.tryParse(price.text.trim());
    final stockInt = int.tryParse(stock.text.trim());
    if (priceInt == null || stockInt == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Harga/Stok harus angka yang valid')),
        );
      }
      return;
    }

    setState(() => _isUploading = true);
    try {
      final imgPart = await _dioFileFromXFile(_xfile!);

      // === NEW: HITUNG KELAYAKAN TFLite (sebelum membangun fields) ===
      int? suitabilityPercent;
      try {
        // Ambil fitur numerik dari form nutrisi
        final cal = double.tryParse(kalori.text.trim());
        final prot = double.tryParse(protein.text.trim());
        final vitc = double.tryParse(vitaminC.text.trim());
        final fib = double.tryParse(serat.text.trim());

        // Normalisasi sederhana 0..1 (sesuaikan dengan modelmu)
        final features = <double>[
          (cal ?? 0) / 1000.0,
          (prot ?? 0) / 100.0,
          (vitc ?? 0) / 1000.0,
          (fib ?? 0) / 100.0,
        ];

        suitabilityPercent =
            await SuitabilityService().computePercent(features);
      } catch (_) {
        suitabilityPercent = null; // fallback bila gagal inferensi
      }

      // Gunakan percent utk freshness_score & label
      final int percent = (suitabilityPercent ?? 0).clamp(0, 100);
      final String freshnessLabel = _freshnessLabelFrom(percent);

      // === BUILD FORM DATA (Dio) ===
      final form = FormData.fromMap({
        'name': name.text.trim(),
        'category': category, // 'buah' | 'sayur'
        'price': priceInt,
        'unit': unit.text.trim(),
        'stock': stockInt,
        'description': desc.text.trim(),
        // status publik & aktif
        'status': 'published',
        'is_active': true,
        // freshness & suitability
        'freshness_score': percent.toDouble(),
        'freshness_label': freshnessLabel,
        if (suitabilityPercent != null) 'suitability_percent': suitabilityPercent,
        // nutrisi (opsional - backend boleh abaikan)
        if ((kalori.text).trim().isNotEmpty) 'calories_kcal': kalori.text.trim(),
        if ((protein.text).trim().isNotEmpty) 'protein_g': protein.text.trim(),
        if ((vitaminC.text).trim().isNotEmpty) 'vitamin_c_mg': vitaminC.text.trim(),
        if ((serat.text).trim().isNotEmpty) 'fiber_g': serat.text.trim(),
        // penyimpanan (opsional)
        if ((storageMethod ?? '').isNotEmpty) 'storage_method': storageMethod!,
        if ((storageNotes.text).trim().isNotEmpty)
          'storage_notes': storageNotes.text.trim(),
        // file
        'image': imgPart,
      });

      // === KIRIM (CREATE) via Dio ===
      final res = await API.dio.post('seller/products', data: form);

      if (res.statusCode != null && res.statusCode! >= 200 && res.statusCode! < 300) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Produk berhasil diupload!')),
        );
        Navigator.pop(context, true);
      } else {
        throw Exception('Gagal upload (${res.statusCode}): ${res.data}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tambah Produk (Seller)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AspectRatio(
            aspectRatio: 1.6,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF4F6F8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E8EB)),
              ),
              alignment: Alignment.center,
              child: _xfile == null
                  ? const Text('Belum ada gambar')
                  // NB: di Web, _xfile.path adalah blob url -> aman dipakai Image.network
                  : Image.network(_xfile!.path, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.photo),
                  label: const Text('Pilih Gambar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isUploading ? null : _openCreateSheet,
                  icon: _isUploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.cloud_upload),
                  label: Text(_isUploading ? 'Mengunggah…' : 'Upload'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
