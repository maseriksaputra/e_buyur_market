import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../../core/services/review_api_service.dart';

class WriteReviewPage extends StatefulWidget {
  final int productId;
  final String? productName;
  const WriteReviewPage({super.key, required this.productId, this.productName});

  @override
  State<WriteReviewPage> createState() => _WriteReviewPageState();
}

class _WriteReviewPageState extends State<WriteReviewPage> {
  late final ReviewApiService api;
  final _comment = TextEditingController();
  int _rating = 5;

  List<EligibleOrderItem> _eligible = [];
  EligibleOrderItem? _selected;
  bool _loading = true;
  bool _submitting = false;

  final ImagePicker _picker = ImagePicker();
  final List<XFile> _images = [];

  @override
  void initState() {
    super.initState();
    api = ReviewApiService(context.read<Dio>());
    _loadEligible();
  }

  Future<void> _loadEligible() async {
    setState(() => _loading = true);
    try {
      final list = await api.eligibleOrderItems(widget.productId);
      setState(() {
        _eligible = list;
        if (_eligible.isNotEmpty) _selected = _eligible.first;
      });
    } catch (e) {
      // biarkan kosong → user isi manual via dialog nanti
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickImages() async {
    try {
      final files =
          await _picker.pickMultiImage(imageQuality: 85, maxWidth: 2000);
      if (files != null) {
        setState(() {
          final remain = 5 - _images.length;
          _images.addAll(files.take(remain));
        });
      }
    } catch (e) {
      _toast('Gagal memilih gambar: $e');
    }
  }

  void _removeImage(int i) {
    setState(() => _images.removeAt(i));
  }

  Future<void> _submit() async {
    if (_rating < 1 || _rating > 5) {
      _toast('Pilih rating 1–5 bintang.');
      return;
    }

    // Pastikan ada order_item_id
    int? orderItemId = _selected?.id;
    if (orderItemId == null) {
      // jika tidak ada endpoint eligible → minta input manual ID item
      final id = await _askOrderItemId();
      if (id == null) return;
      orderItemId = id;
    }

    setState(() => _submitting = true);
    try {
      // siapkan multipart files
      final files = <MultipartFile>[];
      for (final x in _images) {
        if (kIsWeb) {
          final bytes = await x.readAsBytes();
          files.add(MultipartFile.fromBytes(bytes,
              filename: x.name,
              contentType:
                  DioMediaType.parse('image/${x.name.split('.').last}')));
        } else {
          files.add(await MultipartFile.fromFile(x.path, filename: x.name));
        }
      }

      await api.create(
        productId: widget.productId,
        orderItemId: orderItemId,
        rating: _rating,
        comment: _comment.text,
        photos: files,
      );

      if (!mounted) return;
      _toast('Ulasan terkirim!');
      Navigator.pop(context, true); // true => minta refresh list
    } catch (e) {
      _toast('Gagal menyimpan ulasan: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<int?> _askOrderItemId() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Masukkan ID Item Pesanan'),
        content: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'contoh: 123'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('OK')),
        ],
      ),
    );
    if (ok == true) {
      final v = int.tryParse(c.text);
      if (v == null) {
        _toast('ID tidak valid.');
        return null;
      }
      return v;
    }
    return null;
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.productName ?? 'Produk';

    return Scaffold(
      appBar: AppBar(title: Text('Tulis Ulasan • $name')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Rating picker
                const Text('Rating',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(
                  children: List.generate(5, (i) {
                    final filled = i < _rating;
                    return IconButton(
                      onPressed: () => setState(() => _rating = i + 1),
                      icon: Icon(filled ? Icons.star : Icons.star_border,
                          color: const Color(0xFFFFC107)),
                    );
                  }),
                ),
                const SizedBox(height: 16),

                // Order item chooser / manual
                const Text('Item Pesanan',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (_eligible.isNotEmpty)
                  DropdownButtonFormField<EligibleOrderItem>(
                    value: _selected,
                    items: _eligible.map((e) {
                      final label = [
                        '#${e.id}',
                        if (e.variantName != null) e.variantName!,
                        if (e.quantity != null) 'x${e.quantity}',
                        if (e.orderCode != null) e.orderCode!,
                      ].join(' · ');
                      return DropdownMenuItem(value: e, child: Text(label));
                    }).toList(),
                    onChanged: (v) => setState(() => _selected = v),
                    decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Pilih item pesanan'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _askOrderItemId,
                    icon: const Icon(Icons.edit),
                    label: const Text('Masukkan ID Item Pesanan (manual)'),
                  ),
                const SizedBox(height: 16),

                // Komentar
                const Text('Komentar (opsional)',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  controller: _comment,
                  maxLines: 4,
                  maxLength: 3000,
                  decoration: const InputDecoration(
                    hintText: 'Bagikan pengalamanmu…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // Foto
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Foto (opsional, maks 5)',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    Text('${_images.length}/5'),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < _images.length; i++)
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: kIsWeb
                                ? Image.network(_images[i].path,
                                    height: 80, width: 80, fit: BoxFit.cover)
                                : Image.file(File(_images[i].path),
                                    height: 80, width: 80, fit: BoxFit.cover),
                          ),
                          Positioned(
                            right: -8,
                            top: -8,
                            child: IconButton(
                              onPressed: () => _removeImage(i),
                              icon: const Icon(Icons.cancel,
                                  size: 18, color: Colors.red),
                            ),
                          )
                        ],
                      ),
                    if (_images.length < 5)
                      InkWell(
                        onTap: _pickImages,
                        child: Container(
                          height: 80,
                          width: 80,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: const Color(0xFFF1F5F9),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Icon(Icons.add_a_photo_outlined),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),

                // Submit
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send),
                    label: const Text('Kirim Ulasan'),
                  ),
                ),
              ],
            ),
    );
  }
}
