// lib/app/presentation/widgets/review/tulis_ulasan_sheet.dart
//
// Bottom sheet untuk kirim ulasan: rating, komentar, dan foto (multipart).
// Ketergantungan: http (^1.x), image_picker (^1.x), dart:io
//
// return true ke navigator jika sukses agar parent bisa refresh.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

import 'ulasan_section.dart'; // pakai kApiBase & defaultHeaders

const int kMaxPhotos = 6;

class TulisUlasanSheet extends StatefulWidget {
  final int productId;

  /// Opsional: override base URL (mis. 'https://domain.com/api')
  final String? apiBase;

  /// Opsional: override header provider agar bisa suntik Authorization
  final Future<Map<String, String>> Function({bool multipart})? headerProvider;

  const TulisUlasanSheet({
    super.key,
    required this.productId,
    this.apiBase,
    this.headerProvider,
  });

  @override
  State<TulisUlasanSheet> createState() => _TulisUlasanSheetState();
}

class _TulisUlasanSheetState extends State<TulisUlasanSheet> {
  int rating = 5;
  final TextEditingController ctrl = TextEditingController();
  final List<XFile> photos = [];
  bool saving = false;

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    try {
      final picker = ImagePicker();
      final files = await picker.pickMultiImage(imageQuality: 85);
      if (files != null && files.isNotEmpty) {
        final remain = kMaxPhotos - photos.length;
        if (remain <= 0) return;
        setState(() {
          photos.addAll(files.take(remain));
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memilih foto: $e')),
      );
    }
  }

  Future<void> _submit() async {
    if (saving) return;
    setState(() => saving = true);

    try {
      final base = widget.apiBase ?? kApiBase;
      final headersFn = widget.headerProvider ?? defaultHeaders;

      final uri = Uri.parse('$base/reviews');
      final req = http.MultipartRequest('POST', uri);

      // headers
      final h = await headersFn(multipart: true);
      req.headers.addAll(h);

      // fields
      req.fields['product_id'] = widget.productId.toString();
      req.fields['rating'] = rating.toString();
      req.fields['comment'] = ctrl.text;

      // files
      for (final f in photos) {
        req.files.add(await http.MultipartFile.fromPath('photos[]', f.path));
      }

      final resp = await req.send();
      final body = await resp.stream.bytesToString();

      if (resp.statusCode == 201) {
        if (mounted) {
          Navigator.pop(context, true);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Gagal mengirim ulasan (HTTP ${resp.statusCode}): $body')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Terjadi kesalahan: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Tulis Ulasan',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed:
                      saving ? null : () => Navigator.pop(context, false),
                  icon: const Icon(Icons.close),
                )
              ],
            ),
            const SizedBox(height: 12),

            // Rating
            Row(
              children: List.generate(
                5,
                (i) => IconButton(
                  iconSize: 28,
                  onPressed:
                      saving ? null : () => setState(() => rating = i + 1),
                  icon: Icon(i < rating ? Icons.star : Icons.star_border),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Komentar
            TextField(
              controller: ctrl,
              enabled: !saving,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Komentar (opsional)',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),

            // Foto
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in photos)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(f.path),
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        right: -8,
                        top: -8,
                        child: IconButton(
                          icon: const Icon(Icons.cancel),
                          onPressed: saving
                              ? null
                              : () {
                                  setState(() {
                                    photos.remove(f);
                                  });
                                },
                        ),
                      ),
                    ],
                  ),
                if (photos.length < kMaxPhotos)
                  OutlinedButton.icon(
                    onPressed: saving ? null : _pickImages,
                    icon: const Icon(Icons.add_a_photo),
                    label: const Text('Tambah Foto'),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Submit
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: saving ? null : _submit,
                child: saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Kirim'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
