// lib/app/presentation/screens/seller/seller_edit_product_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'app_colors.dart';

final _idr = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

String _s(dynamic v) => (v ?? '').toString();
T _coerce<T>(dynamic v, T fallback) {
  if (v is T) return v;
  if (T == int)    return (int.tryParse('$v') ?? fallback) as T;
  if (T == double) return (double.tryParse('$v') ?? fallback) as T;
  return fallback;
}

class SellerEditProductScreen extends StatefulWidget {
  final dynamic prefill;
  /// Kembalikan map produk terbaru; lempar exception kalau gagal biar Snackbar muncul.
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> body) onSubmit;

  const SellerEditProductScreen({
    Key? key,
    required this.prefill,
    required this.onSubmit,
  }) : super(key: key);

  @override
  State<SellerEditProductScreen> createState() => _SellerEditProductScreenState();
}

class _SellerEditProductScreenState extends State<SellerEditProductScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _nameC;
  late final TextEditingController _priceC;
  late final TextEditingController _unitC;
  late final TextEditingController _stockC;
  late final TextEditingController _descC;
  String _category = '';

  @override
  void initState() {
    super.initState();
    final p = widget.prefill;
    _nameC  = TextEditingController(text: _s(p['name'] ?? p.name));
    _priceC = TextEditingController(text: '${_coerce<int>(p['price'] ?? p.price, 0)}');
    _unitC  = TextEditingController(text: _s(p['unit'] ?? p.unit ?? 'kg'));
    _stockC = TextEditingController(text: '${_coerce<int>(p['stock'] ?? p.stock, 0)}');
    _descC  = TextEditingController(text: _s(p['description'] ?? p.description));
    _category = _s(p['category_slug'] ?? p.categorySlug ?? p['category'] ?? p.category);
  }

  @override
  void dispose() {
    _nameC.dispose();
    _priceC.dispose();
    _unitC.dispose();
    _stockC.dispose();
    _descC.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final body = <String, dynamic>{
      'name': _nameC.text.trim(),
      'price': int.tryParse(_priceC.text.replaceAll('.', '')) ?? 0,
      'unit': _unitC.text.trim(),
      'stock': int.tryParse(_stockC.text) ?? 0,
      'description': _descC.text.trim(),
      'category_slug': _category,
    };
    try {
      final updated = await widget.onSubmit(body);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Produk diperbarui')));
      Navigator.pop(context, updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Produk')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _submit,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: const StadiumBorder(),
            ),
            child: const Text('Simpan Perubahan'),
          ),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            children: [
              // Nama
              TextFormField(
                controller: _nameC,
                decoration: const InputDecoration(
                  labelText: 'Nama Produk',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 12),

              // Harga + Satuan
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _priceC,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Harga (Rp)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 110,
                    child: TextFormField(
                      controller: _unitC,
                      decoration: const InputDecoration(
                        labelText: 'Satuan',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Stok
              TextFormField(
                controller: _stockC,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Stok',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // Kategori (slug)
              DropdownButtonFormField<String>(
                value: _category.isEmpty ? null : _category,
                decoration: const InputDecoration(
                  labelText: 'Kategori',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'buah', child: Text('Buah')),
                  DropdownMenuItem(value: 'sayur', child: Text('Sayur')),
                ],
                onChanged: (v) => setState(() => _category = v ?? ''),
              ),
              const SizedBox(height: 12),

              // Deskripsi
              TextFormField(
                controller: _descC,
                decoration: const InputDecoration(
                  labelText: 'Deskripsi',
                  border: OutlineInputBorder(),
                ),
                maxLines: 4,
              ),
              const SizedBox(height: 12),

              // Info AI (read-only ringkas)
              if ((widget.prefill['freshness_score'] ?? 0) != 0)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.lightGrey),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.freshnessColor(
                            (widget.prefill['freshness_score'] ?? 0).toDouble(),
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${(widget.prefill['freshness_score'] ?? 0).round()}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Kelayakan AI: ${_s(widget.prefill['freshness_label'] ?? '')}',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
