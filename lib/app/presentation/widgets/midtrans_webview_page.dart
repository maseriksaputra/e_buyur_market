import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../providers/checkout_provider.dart';

class MidtransWebViewPage extends StatefulWidget {
  final String redirectUrl;
  final int orderId;
  const MidtransWebViewPage({super.key, required this.redirectUrl, required this.orderId});

  @override State<MidtransWebViewPage> createState() => _MidtransWebViewPageState();
}

class _MidtransWebViewPageState extends State<MidtransWebViewPage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final data = await context.read<CheckoutProvider>().fetchOrder(widget.orderId);
      final status = data['status']?.toString() ?? '';
      if (status == 'paid' || status == 'processing') {
        _timer?.cancel();
        if (!mounted) return;
        Navigator.pop(context);
        Navigator.pushReplacementNamed(context, '/order-success', arguments: data);
      }
    });
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(widget.redirectUrl));
    return Scaffold(
      appBar: AppBar(title: const Text('Pembayaran')),
      body: WebViewWidget(controller: controller),
    );
  }
}
