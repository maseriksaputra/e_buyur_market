
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/network/api.dart';

class PaymentAwaitingPage extends StatefulWidget {
  final int orderId;
  final String? bankName;
  final String? vaNumber;
  final String? billKey;
  final String? billerCode;
  final int amount;
  final String? redirectUrl;
  const PaymentAwaitingPage({super.key, required this.orderId, required this.amount, this.bankName, this.vaNumber, this.billKey, this.billerCode, this.redirectUrl});

  @override
  State<PaymentAwaitingPage> createState() => _PaymentAwaitingPageState();
}

class _PaymentAwaitingPageState extends State<PaymentAwaitingPage> {
  Timer? _t;
  String _status = 'awaiting_payment';

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  void _startPolling() {
    _t?.cancel();
    _t = Timer.periodic(const Duration(seconds: 4), (_) async {
      try {
        final dio = API.dio;
        final r = await dio.get('buyer/orders/${widget.orderId}/status');
        final s = (r.data['status'] ?? r.data['order_status'] ?? '').toString();
        if (!mounted) return;
        setState(()=>_status=s);
        if (s == 'paid' || s == 'completed') {
          _t?.cancel();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pembayaran terverifikasi.')));
            Navigator.pop(context, true);
          }
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVa = widget.vaNumber != null;
    final isMandiri = widget.billKey != null && widget.billerCode != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Menunggu Pembayaran')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Status: ${_status.toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          if (isVa) ...[
            _kv('Metode', 'Transfer VA ${widget.bankName ?? ''}'),
            _kv('Nomor VA', widget.vaNumber!),
            _kv('Jumlah', 'Rp ${widget.amount}'),
          ] else if (isMandiri) ...[
            _kv('Metode', 'Mandiri E-channel'),
            _kv('Bill Key', widget.billKey!),
            _kv('Biller Code', widget.billerCode!),
            _kv('Jumlah', 'Rp ${widget.amount}'),
          ] else ...[
            const Text('Selesaikan pembayaran di halaman Midtrans.'),
          ],
          const SizedBox(height: 16),
          const Text('Halaman ini memeriksa status otomatis setiap 4 detik.'),
        ]),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [Expanded(child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))), SelectableText(v)]),
  );
}
