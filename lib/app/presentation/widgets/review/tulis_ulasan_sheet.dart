import 'package:flutter/material.dart';

class TulisUlasanSheet extends StatelessWidget {
  final int productId;
  final String? apiBase;
  final Future<Map<String, String>> Function({bool multipart})? headerProvider;

  const TulisUlasanSheet({
    super.key,
    required this.productId,
    this.apiBase,
    this.headerProvider,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, controller) {
        return Material(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.rate_review, color: Colors.green),
                    const SizedBox(width: 8),
                    const Text('Tulis Ulasan',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context, false),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.all(16),
                  children: const [
                    Text(
                      'Fitur ini hanya tersedia dari halaman Riwayat Pesanan '
                      'untuk pesanan yang statusnya sudah Diterima (delivered).',
                      style: TextStyle(height: 1.4),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Silakan buka menu Riwayat, pilih pesanan terkait, '
                      'lalu tekan tombol “Tulis Ulasan”.',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Mengerti'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
