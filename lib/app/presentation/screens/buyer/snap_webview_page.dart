// lib/app/presentation/screens/buyer/snap_webview_page.dart
//
// WebView untuk menampilkan Midtrans Snap (redirect_url).
// Mengembalikan `true` via Navigator.pop(context, true) saat transaksi dianggap selesai,
// lalu layar pemanggil bisa melakukan polling status pembayaran.

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class SnapWebViewPage extends StatefulWidget {
  final String redirectUrl;
  const SnapWebViewPage({super.key, required this.redirectUrl});

  @override
  State<SnapWebViewPage> createState() => _SnapWebViewPageState();
}

class _SnapWebViewPageState extends State<SnapWebViewPage> {
  late final WebViewController _controller;
  bool _isLoading = true;
  int _progress = 0;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (req) {
            final url = req.url;
            // Heuristik selesai:
            // - Snap biasanya redirect ke URL finish/callback dengan query status
            if (_isDoneUrl(url)) {
              // Tutup WebView → pemanggil lanjut polling status via API
              Navigator.of(context).pop(true);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (_) {
            setState(() => _isLoading = true);
          },
          onProgress: (p) {
            setState(() => _progress = p);
          },
          onPageFinished: (url) async {
            // Hindari tab baru dari window.open()
            await _controller.runJavaScript("""
              (function(){
                try {
                  window.open = function(u){ window.location.href = u; };
                } catch(e) {}
              })();
            """);
            setState(() => _isLoading = false);
          },
          onWebResourceError: (_) {
            // Bisa tampilkan snackbar/toast jika perlu
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.redirectUrl));
  }

  bool _isDoneUrl(String url) {
    // Kumpulan tanda-tanda transaksi selesai/meninggalkan halaman pembayaran.
    // Sesuaikan jika kamu punya callback URL khusus di server.
    final u = Uri.tryParse(url);
    if (u == null) return false;

    final lower = url.toLowerCase();
    // Common Snap indicators
    if (lower.contains('/finish') ||
        lower.contains('status_code=') ||
        lower.contains('transaction_status=') ||
        lower.contains('redirect_status=') ||
        lower.contains('payment_id=')) {
      return true;
    }

    // Optional: jika kembali ke domain backend sendiri (mis. callback/thanks page)
    // contoh: https://api.ebuyurmarket.com/payments/finish?...
    final host = (u.host).toLowerCase();
    final path = (u.path).toLowerCase();
    if (host.contains('ebuyurmarket.com') && path.contains('payments')) {
      return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final showProgress = _isLoading || (_progress > 0 && _progress < 100);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pembayaran'),
        actions: [
          IconButton(
            tooltip: 'Tutup',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
        bottom: showProgress
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  value: (_progress > 0 && _progress < 100)
                      ? _progress / 100.0
                      : null,
                ),
              )
            : null,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Align(
              alignment: Alignment.center,
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
