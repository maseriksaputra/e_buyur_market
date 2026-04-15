// lib/app/presentation/screens/buyer/checkout_v2.dart
import 'dart:async';
import 'package:flutter/foundation.dart' as f; // f.describeEnum
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';               // ⬅️ NEW
import '../../providers/cart_provider.dart';           // ⬅️ NEW

import '../../../core/network/api.dart'; // satu pintu, ada interceptor token

// ========================= Enums =========================
enum PaymentMethod { midtrans, transfer, cod }

// 🔥 Channel Midtrans: VA lengkap + e-wallet + kartu
enum MidtransChannel {
  qris,
  gopay,
  card,
  bca_va,
  bni_va,
  bri_va,
  permata_va,
  echannel, // Mandiri bill payment
}

String midtransChannelToApi(MidtransChannel c) => switch (c) {
      MidtransChannel.qris => 'qris',
      MidtransChannel.gopay => 'gopay',
      MidtransChannel.card => 'card',
      MidtransChannel.bca_va => 'bca_va',
      MidtransChannel.bni_va => 'bni_va',
      MidtransChannel.bri_va => 'bri_va',
      MidtransChannel.permata_va => 'permata_va',
      MidtransChannel.echannel => 'echannel',
    };

// ========================= Models =========================
class CheckoutItem {
  final int productId;
  final String name;
  final String imageUrl;
  final int qty;
  final int unitPrice;
  final int lineTotal;

  CheckoutItem({
    required this.productId,
    required this.name,
    required this.imageUrl,
    required this.qty,
    required this.unitPrice,
    required this.lineTotal,
  });

  factory CheckoutItem.fromJson(Map<String, dynamic> j) => CheckoutItem(
        productId: (j['product_id'] ?? j['id'] ?? 0) is String
            ? int.tryParse('${j['product_id'] ?? j['id'] ?? 0}') ?? 0
            : (j['product_id'] ?? j['id'] ?? 0) as int,
        name: (j['name'] ?? j['product_name'] ?? '-').toString(),
        imageUrl: (j['image_url'] ?? j['imageUrl'] ?? j['image'] ?? '').toString(),
        qty: ((j['qty'] ?? j['quantity'] ?? 0) as num).toInt(),
        unitPrice: ((j['unit_price'] ?? j['price'] ?? 0) as num).toInt(),
        lineTotal: (j['line_total'] ??
                (((j['qty'] ?? 0) as num).toInt() *
                    ((j['unit_price'] ?? 0) as num).toInt())) is num
            ? (j['line_total'] ??
                    (((j['qty'] ?? 0) as num).toInt() *
                        ((j['unit_price'] ?? 0) as num).toInt())) as int
            : int.tryParse(
                    '${j['line_total'] ?? (((j['qty'] ?? 0) as num).toInt() * ((j['unit_price'] ?? 0) as num).toInt())}') ??
                0,
      );
}

class CheckoutPreview {
  final List<CheckoutItem> items;
  final int subtotal;
  final int shippingFee;
  final int discountTotal;
  final int grandTotal;
  final double distanceKm;

  CheckoutPreview({
    required this.items,
    required this.subtotal,
    required this.shippingFee,
    required this.discountTotal,
    required this.grandTotal,
    required this.distanceKm,
  });

  factory CheckoutPreview.fromJson(Map<String, dynamic> j) {
    final rawItems = (j['items'] ?? j['data'] ?? []) as List;
    return CheckoutPreview(
      items: rawItems
          .map((e) =>
              CheckoutItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      subtotal: ((j['subtotal'] ?? 0) as num).toInt(),
      shippingFee: ((j['shipping_fee'] ?? j['ongkir'] ?? 0) as num).toInt(),
      discountTotal: ((j['discount_total'] ?? j['diskon'] ?? 0) as num).toInt(),
      grandTotal: ((j['grand_total'] ?? j['total'] ?? 0) as num).toInt(),
      distanceKm: ((j['distance_km'] ?? 0) as num).toDouble(),
    );
  }
}

// ========================= Payment Awaiting Page =========================
class PaymentAwaitingPage extends StatefulWidget {
  final int orderId;
  final String? bankName;    // untuk VA
  final String? vaNumber;    // untuk VA
  final String? billKey;     // Mandiri e-channel
  final String? billerCode;  // Mandiri e-channel
  final int amount;
  final String? redirectUrl; // Snap/redirect methods

  const PaymentAwaitingPage({
    super.key,
    required this.orderId,
    required this.amount,
    this.bankName,
    this.vaNumber,
    this.billKey,
    this.billerCode,
    this.redirectUrl,
  });

  @override
  State<PaymentAwaitingPage> createState() => _PaymentAwaitingPageState();
}

class _PaymentAwaitingPageState extends State<PaymentAwaitingPage> {
  Timer? _t;
  String _status = 'waiting';
  final _rp = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

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
        setState(() => _status = s);
        if (s == 'paid' || s == 'completed') {
          _t?.cancel();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Pembayaran terverifikasi.')),
            );
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
    final isMandiri = widget.billKey != null && widget.billerCode != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Menunggu Pembayaran')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Status: ${_status.toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          if (widget.vaNumber != null) ...[
            _kv('Metode', 'Transfer VA ${widget.bankName ?? ''}'),
            _kv('Nomor VA', widget.vaNumber!),
            _kv('Jumlah', _rp.format(widget.amount)),
          ] else if (isMandiri) ...[
            _kv('Metode', 'Mandiri E-channel'),
            _kv('Bill Key', widget.billKey!),
            _kv('Biller Code', widget.billerCode!),
            _kv('Jumlah', _rp.format(widget.amount)),
          ] else ...[
            const Text('Selesaikan pembayaran di halaman Midtrans.'),
            const SizedBox(height: 8),
            if (widget.redirectUrl != null && widget.redirectUrl!.isNotEmpty)
              SizedBox(
                width: double.infinity, height: 46,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pushNamed(
                    '/midtrans-webview',
                    arguments: {'url': widget.redirectUrl, 'order_id': widget.orderId},
                  ),
                  child: const Text('Buka Halaman Pembayaran'),
                ),
              ),
          ],
          const SizedBox(height: 16),
          const Text('Layar ini memperbarui status otomatis setiap 4 detik.'),
        ]),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
          SelectableText(v),
        ]),
      );
}

// ========================= Screen (Checkout) =========================
class CheckoutV2Screen extends StatefulWidget {
  const CheckoutV2Screen({super.key});
  @override
  State<CheckoutV2Screen> createState() => _CheckoutV2ScreenState();
}

class _CheckoutV2ScreenState extends State<CheckoutV2Screen> {
  // Controllers
  final TextEditingController addressCtrl = TextEditingController();
  final TextEditingController noteCtrl = TextEditingController();

  // Payment state
  PaymentMethod method = PaymentMethod.midtrans;
  MidtransChannel channel = MidtransChannel.qris;

  // Data state
  CheckoutPreview? preview;
  bool loading = false;
  String? errorText;

  // Map state
  final mapCtrl = Completer<GoogleMapController>();
  LatLng? pin;
  Timer? _debounce; // debounce untuk _reloadPreview saat mengetik alamat

  // Formatter
  final _rp = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initMapAndPreview());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    addressCtrl.dispose();
    noteCtrl.dispose();
    super.dispose();
  }

  // ========================= Helpers =========================
  String _idr(num v) => _rp.format(v);

  void _debouncedReload() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _reloadPreview);
  }

  // Kumpulkan cart_item_ids dari CartProvider: selectedIds -> fallback dari items.selected
  List<int> _collectSelectedCartIds() {
    try {
      final cart = context.read<CartProvider>();
      // 1) dari selectedIds
      final ids = cart.selectedIds
          .map((e) => int.tryParse('$e') ?? 0)
          .where((e) => e > 0)
          .toList();
      if (ids.isNotEmpty) return ids;

      // 2) fallback: cek flag "selected" di items
      final out = <int>[];
      for (final it in cart.items) {
        final sel = _isSelected(it);
        if (!sel) continue;
        final id = _extractCartItemId(it);
        if (id > 0) out.add(id);
      }
      return out;
    } catch (_) {
      return <int>[];
    }
  }

  bool _isSelected(dynamic it) {
    try {
      final v = (it as dynamic).selected;
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) return v == '1' || v.toLowerCase() == 'true';
    } catch (_) {}
    if (it is Map) {
      final v = it['selected'];
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) return v == '1' || v.toLowerCase() == 'true';
    }
    return false;
  }

  int _extractCartItemId(dynamic it) {
    if (it is Map) {
      final raw = it['id'] ?? it['cart_item_id'] ?? it['cartItemId'] ?? 0;
      return raw is int ? raw : int.tryParse('$raw') ?? 0;
    }
    try {
      final v = (it as dynamic).id;
      if (v is int) return v;
    } catch (_) {}
    try {
      final v = (it as dynamic).cartItemId;
      if (v is int) return v;
    } catch (_) {}
    try {
      final v = (it as dynamic).cart_item_id;
      if (v is int) return v;
    } catch (_) {}
    return 0;
  }

  Future<void> _initMapAndPreview() async {
    // Lokasi awal: current position; fallback Jakarta
    const fallback = LatLng(-6.200000, 106.816666);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        perm = await Geolocator.requestPermission();
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        pin = fallback;
      } else {
        final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium);
        pin = LatLng(pos.latitude, pos.longitude);
      }
    } catch (_) {
      pin = fallback;
    }
    if (!mounted) return;
    setState(() {});
    await _reloadPreview();
  }

  Future<void> _reloadPreview() async {
    setState(() {
      loading = true;
      errorText = null;
    });
    try {
      final Dio dio = API.dio;

      // ⬅️ NEW: kumpulkan ID item keranjang yang dipilih
      final ids = _collectSelectedCartIds();

      // 1) Endpoint preview utama — sertakan include_items & cart_item_ids (kalau ada)
      final resp = await dio.post(
        'buyer/checkout/preview',
        data: {
          if (ids.isNotEmpty) 'cart_item_ids': ids, // ⬅️ penting
          'address_text': addressCtrl.text.trim().isEmpty ? null : addressCtrl.text.trim(),
          'lat': pin?.latitude,
          'lng': pin?.longitude,
          'include_items': true, // ⬅️ penting
        },
      );

      // Normalisasi payload
      final raw = resp.data;
      final Map<String, dynamic> data =
          raw is Map<String, dynamic> ? raw : Map<String, dynamic>.from(raw as Map);

      // Bisa saja server membungkus di { data: {...} }
      final payload = data['data'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(data['data'])
          : data;

      var pv = CheckoutPreview.fromJson(payload);

      // 2) Fallback jika items kosong -> ambil langsung dari cart
      if (pv.items.isEmpty) {
        final r2 = await dio.get('buyer/cart');
        final cartMap = r2.data is Map<String, dynamic>
            ? r2.data
            : Map<String, dynamic>.from(r2.data);
        final cartItemsList =
            (cartMap['items'] ?? cartMap['data'] ?? []) as List;
        final items = cartItemsList
            .map((e) =>
                CheckoutItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        final sub = items.fold<int>(0, (s, it) => s + it.lineTotal);
        pv = CheckoutPreview(
          items: items,
          subtotal: sub,
          shippingFee: pv.shippingFee,
          discountTotal: pv.discountTotal,
          grandTotal: sub + pv.shippingFee - pv.discountTotal,
          distanceKm: pv.distanceKm,
        );
      }

      if (!mounted) return;
      setState(() {
        preview = pv;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorText = 'Gagal memuat checkout: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        loading = false;
      });
    }
  }

  // ========================= Midtrans Channel Selector =========================
  Widget _buildMidtransChannelSelector() {
    final chips = <Widget>[
      const Text('VA Bank', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(width: 8),
      FilterChip(label: const Text('BCA VA'), selected: channel==MidtransChannel.bca_va, onSelected: (_)=>setState(()=>channel=MidtransChannel.bca_va)),
      FilterChip(label: const Text('BNI VA'), selected: channel==MidtransChannel.bni_va, onSelected: (_)=>setState(()=>channel=MidtransChannel.bni_va)),
      FilterChip(label: const Text('BRI VA'), selected: channel==MidtransChannel.bri_va, onSelected: (_)=>setState(()=>channel=MidtransChannel.bri_va)),
      FilterChip(label: const Text('Permata VA'), selected: channel==MidtransChannel.permata_va, onSelected: (_)=>setState(()=>channel=MidtransChannel.permata_va)),
      FilterChip(label: const Text('Mandiri (E-channel)'), selected: channel==MidtransChannel.echannel, onSelected: (_)=>setState(()=>channel=MidtransChannel.echannel)),
      const SizedBox(height: 8),
      const Text('E-Wallet & Lainnya', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(width: 8),
      FilterChip(label: const Text('QRIS'), selected: channel==MidtransChannel.qris, onSelected: (_)=>setState(()=>channel=MidtransChannel.qris)),
      FilterChip(label: const Text('GoPay'), selected: channel==MidtransChannel.gopay, onSelected: (_)=>setState(()=>channel=MidtransChannel.gopay)),
      FilterChip(label: const Text('Kartu'), selected: channel==MidtransChannel.card, onSelected: (_)=>setState(()=>channel=MidtransChannel.card)),
    ];

    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  // ========================= Pay Now Flow =========================
  Future<void> _onPay() async {
    if (preview == null) {
      await _reloadPreview();
      if (preview == null) return;
    }
    setState(() => loading = true);
    try {
      final Dio dio = API.dio;

      // ⬅️ NEW: kumpulkan ID yang dipilih agar order hanya mencakup item itu
      final ids = _collectSelectedCartIds();

      final resp = await dio.post('buyer/checkout', data: {
        'payment_method': 'midtrans',
        'payment_channel': midtransChannelToApi(channel),
        'address_text': addressCtrl.text,
        'lat': pin?.latitude,
        'lng': pin?.longitude,
        'note': noteCtrl.text,
        if (ids.isNotEmpty) 'cart_item_ids': ids, // ⬅️ penting
      });

      final raw = resp.data;
      final Map<String, dynamic> data =
          raw is Map<String, dynamic> ? raw : Map<String, dynamic>.from(raw as Map);
      final normalized = data['data'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(data['data'])
          : data;

      final orderId = normalized['order_id'] ?? normalized['id'];
      final amount = (normalized['amount'] ??
          preview?.grandTotal ??
          normalized['grand_total'] ??
          0) as num;

      // Case 1: VA via Core API (server kirim kode VA / Mandiri bill key)
      final va = normalized['va'];
      final mandiri = normalized['mandiri'];
      if (orderId != null && (va != null || mandiri != null)) {
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PaymentAwaitingPage(
              orderId: int.tryParse('$orderId') ?? 0,
              amount: amount.toInt(),
              bankName: (va?['bank'] ?? va?['name'])?.toString(),
              vaNumber: (va?['va_number'] ?? va?['number'])?.toString(),
              billKey: mandiri?['bill_key']?.toString(),
              billerCode: mandiri?['biller_code']?.toString(),
            ),
          ),
        );
        return;
      }

      // Case 2: Snap / redirect (QRIS, GoPay, Card, atau VA via Snap)
      final redirectUrl =
          normalized['redirect_url'] ?? normalized['payment_redirect_url'];
      if (orderId != null) {
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PaymentAwaitingPage(
              orderId: int.tryParse('$orderId') ?? 0,
              amount: amount.toInt(),
              redirectUrl: redirectUrl?.toString(),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Checkout gagal: $e')));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // ========================= UI =========================
  @override
  Widget build(BuildContext context) {
    final gt = preview?.grandTotal ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: RefreshIndicator(
        onRefresh: _reloadPreview,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Alamat & Peta
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Alamat & Lokasi',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    _buildMap(),
                    const SizedBox(height: 8),
                    TextField(
                      controller: addressCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        hintText: 'Detail alamat…',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => _debouncedReload(),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: noteCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        hintText: 'Catatan untuk penjual (opsional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Ringkasan Item
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ringkasan Item',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    if (errorText != null)
                      Text(errorText!,
                          style: const TextStyle(color: Colors.red)),
                    if ((preview?.items ?? []).isEmpty)
                      const Text('Keranjang kosong / tidak terbaca.'),
                    ...((preview?.items ?? []).map((it) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              it.imageUrl,
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 56,
                                height: 56,
                                color: Colors.grey.shade200,
                                child: const Icon(Icons.image),
                              ),
                            ),
                          ),
                          title: Text(it.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle:
                              Text('x${it.qty} • ${_idr(it.unitPrice)}'),
                          trailing: Text(
                            _idr(it.lineTotal),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ))).toList(),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Pembayaran
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Metode Pembayaran',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Midtrans'),
                          selected: method == PaymentMethod.midtrans,
                          onSelected: (_) =>
                              setState(() => method = PaymentMethod.midtrans),
                        ),
                        ChoiceChip(
                          label: const Text('Transfer'),
                          selected: method == PaymentMethod.transfer,
                          onSelected: (_) =>
                              setState(() => method = PaymentMethod.transfer),
                        ),
                        ChoiceChip(
                          label: const Text('COD'),
                          selected: method == PaymentMethod.cod,
                          onSelected: (_) =>
                              setState(() => method = PaymentMethod.cod),
                        ),
                      ],
                    ),
                    if (method == PaymentMethod.midtrans) ...[
                      const SizedBox(height: 8),
                      const Text('Channel Midtrans'),
                      const SizedBox(height: 4),
                      _buildMidtransChannelSelector(),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Total
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    _row('Subtotal', preview?.subtotal ?? 0),
                    _row(
                      'Ongkir${(preview?.distanceKm ?? 0) > 0 ? " (${preview!.distanceKm.toStringAsFixed(1)} km)" : ""}',
                      preview?.shippingFee ?? 0,
                    ),
                    _row('Diskon', -(preview?.discountTotal ?? 0)),
                    const Divider(),
                    _row('Grand Total', gt, bold: true),
                  ],
                ),
              ),
              const SizedBox(height: 120),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: loading ? null : _onPay,
              child: Text(
                loading
                    ? 'Memproses...'
                    : 'Bayar Sekarang (${_idr(gt)})',
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ========================= Small UI helpers =========================
  Widget _card({required Widget child}) => Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(padding: const EdgeInsets.all(12), child: child),
      );

  Widget _row(String label, int nominal, {bool bold = false}) {
    final s =
        TextStyle(fontSize: 15, fontWeight: bold ? FontWeight.w800 : FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: s)),
          Text(_idr(nominal), style: s),
        ],
      ),
    );
  }

  Widget _buildMap() {
    final center = pin ?? const LatLng(-6.200000, 106.816666);
    return SizedBox(
      height: 180,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: GoogleMap(
          initialCameraPosition: CameraPosition(target: center, zoom: 15),
          mapType: MapType.normal,
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
          markers: {
            Marker(
              markerId: const MarkerId('pin'),
              position: center,
              draggable: true,
              onDragEnd: (p) async {
                pin = p;
                if (!mounted) return;
                setState(() {});
                await _reloadPreview();
              },
            ),
          },
          onMapCreated: (c) {
            if (!mapCtrl.isCompleted) {
              mapCtrl.complete(c);
            }
          },
          onTap: (p) async {
            pin = p;
            if (!mounted) return;
            setState(() {});
            await _reloadPreview();
          },
        ),
      ),
    );
  }
}
