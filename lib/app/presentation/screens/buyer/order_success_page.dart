import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Halaman sukses order.
/// - Membaca argument navigator berupa Map<String, dynamic> (opsional)
///   dan menampilkan kode pesanan di UI.
/// - Tombol utama tetap: kembali ke beranda (pop sampai route pertama).
class OrderSuccessPage extends StatelessWidget {
  const OrderSuccessPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final data = (args is Map)
        ? Map<String, dynamic>.from(args as Map)
        : const <String, dynamic>{};

    // Ambil kode pesanan dari beberapa kemungkinan key, fallback '-'
    final code = (data['code'] ??
            data['order_code'] ??
            data['orderId'] ??
            data['id'] ??
            '-')
        .toString();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Berhasil'),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Ikon sukses
                  Container(
                    width: 112,
                    height: 112,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 96,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Terima kasih!',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Pesanan kamu sudah dibuat.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  // Kode pesanan + tombol salin
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.receipt_long_rounded, size: 20),
                          const SizedBox(width: 10),
                          const Text(
                            'Kode Pesanan:',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: SelectableText(
                              code,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            tooltip: 'Salin kode',
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: code));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Kode pesanan disalin'),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Tombol kembali ke beranda (tetap sama fungsinya)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () =>
                          Navigator.popUntil(context, (r) => r.isFirst),
                      child: const Text('Kembali ke Beranda'),
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
}

/// Kompatibilitas ke kode lama yang mungkin masih mereferensikan
/// `_OrderSuccessPage`. Jangan dipakai di kode baru.
@Deprecated('Gunakan OrderSuccessPage')
class _OrderSuccessPage extends OrderSuccessPage {
  const _OrderSuccessPage({Key? key}) : super(key: key);
}
