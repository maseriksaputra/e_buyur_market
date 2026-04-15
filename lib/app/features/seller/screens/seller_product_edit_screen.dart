// lib/app/presentation/screens/seller/seller_product_edit_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart'; // NEW: for FormData/Multipart
import '../../../core/network/api.dart'; // NEW: API.dio base

import '../../../common/models/product_model.dart';
import '../../providers/seller_products_provider.dart';
// NEW: ML service
import '../../../../ml/suitability_service.dart';

class SellerProductEditScreen extends StatefulWidget {
  final int productId;
  const SellerProductEditScreen({super.key, required this.productId});

  @override
  State<SellerProductEditScreen> createState() => _SellerProductEditScreenState();
}

class _SellerProductEditScreenState extends State<SellerProductEditScreen> {
  final _formKey = GlobalKey<FormState>();
  Product? _p;

  final _name = TextEditingController();
  final _price = TextEditingController();
  final _stock = TextEditingController();
  final _desc  = TextEditingController();
  final _fresh = TextEditingController();
  final _nutri = TextEditingController(); // dipisah koma

  bool _active = true;
  bool _loading = true;
  bool _saving = false; // NEW: agar tombol disable saat submit

  Future<void> _load() async {
    final prov = context.read<SellerProductsProvider>();
    final d = await prov.loadDetail(widget.productId);
    setState(() {
      _p = d;
      _name.text  = d.name ?? '';
      _price.text = (d.price ?? 0).toString();
      _stock.text = (d.stock ?? 0).toString();
      _desc.text  = d.description ?? '';
      _fresh.text = (d.freshnessScore ?? 0).toString();
      _nutri.text = (d.nutrition ?? []).join(', ');
      _active     = d.isActive ?? true;
      _loading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _freshnessLabelFrom(int percent) {
    if (percent < 60) return 'Tidak Layak';
    if (percent < 75) return 'Layak';
    if (percent < 88) return 'Cukup Layak';
    return 'Sangat Layak';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Produk')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nama produk'),
              validator: (v)=> v==null||v.trim().length<2 ? 'Minimal 2 karakter' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _price,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Harga'),
              validator: (v)=> (double.tryParse(v??'')==null) ? 'Isi angka' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _stock,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Stok'),
              validator: (v)=> (int.tryParse(v??'')==null) ? 'Isi angka' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _fresh,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Freshness (%)'),
              validator: (v) {
                final x = double.tryParse(v??'');
                if (x==null) return 'Isi angka';
                if (x<0 || x>100) return '0..100';
                return null;
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _desc,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Deskripsi'),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nutri,
              decoration: const InputDecoration(labelText: 'Nutrisi (pisahkan dengan koma, contoh: Vitamin C, Serat, Kalium)'),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Aktif ditampilkan'),
              value: _active,
              onChanged: (v){ setState(()=>_active=v); },
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _saving ? null : () async {
                if (!_formKey.currentState!.validate()) return;

                // === HITUNG KELAYAKAN TFLite (contoh fitur dari fresh/price/stock) ===
                int? suitabilityPercent;
                try {
                  final fresh = double.tryParse(_fresh.text);
                  final p = double.tryParse(_price.text);
                  final s = double.tryParse(_stock.text);

                  final features = <double>[
                    (fresh ?? 0) / 100.0, // normalisasi 0..1
                    (p ?? 0) / 1e7,       // asumsi skala harga (sesuaikan)
                    (s ?? 0) / 1000.0,    // asumsi stok max ~1000
                  ];
                  suitabilityPercent = await SuitabilityService().computePercent(features);
                } catch (_) {
                  suitabilityPercent = null; // biarkan null jika gagal inferensi
                }

                final int percent = (suitabilityPercent ?? 0).clamp(0, 100);
                final String freshnessLabel = _freshnessLabelFrom(percent);

                // === BANGUN FORM MULTIPART & KIRIM KE /seller/products/{id} ===
                setState(()=>_saving = true);
                try {
                  final form = FormData.fromMap({
                    'name': _name.text.trim(),
                    'price': int.parse(_price.text),
                    'stock': int.parse(_stock.text),
                    'description': _desc.text.trim(),
                    'status': 'published',
                    'is_active': _active,
                    // gunakan hasil AI hybrid/TFLite untuk penilaian mutu:
                    'freshness_score': percent.toDouble(),
                    'freshness_label': freshnessLabel,
                    if (suitabilityPercent != null)
                      'suitability_percent': suitabilityPercent,
                    // kirim nutrisi sebagai string koma (backend bisa parsing/abaikan)
                    if (_nutri.text.trim().isNotEmpty)
                      'nutrition': _nutri.text
                          .split(',')
                          .map((e) => e.trim())
                          .where((e) => e.isNotEmpty)
                          .join(','),
                    // NOTE: tidak ada upload gambar di layar ini; kalau mau:
                    // 'image': await MultipartFile.fromFile(imagePath, filename: 'product.jpg'),
                  });

                  final res = await API.dio.post('seller/products/${widget.productId}', data: form);
                  if ((res.statusCode ?? 500) >= 400) {
                    throw Exception('Gagal menyimpan (${res.statusCode})');
                  }

                  // (opsional) sinkronkan ulang provider: list & summary
                  try {
                    await context.read<SellerProductsProvider>().loadProducts();
                    await context.read<SellerProductsProvider>().loadSummary();
                  } catch (_) {}

                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Produk disimpan')),
                  );
                  Navigator.pop(context, true);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Gagal menyimpan: $e')),
                  );
                } finally {
                  if (mounted) setState(()=>_saving = false);
                }
              },
              child: _saving
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }
}
