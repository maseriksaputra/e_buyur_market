import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/network/api.dart';

enum PaymentMethod { midtrans, transfer, cod }
enum MidtransChannel { qris, gopay, card, bca_va, bni_va, bri_va, permata_va, echannel }

String midtransChannelToApi(MidtransChannel c) {
  switch (c) {
    case MidtransChannel.qris: return 'qris';
    case MidtransChannel.gopay: return 'gopay';
    case MidtransChannel.card: return 'card';
    case MidtransChannel.bca_va: return 'bca_va';
    case MidtransChannel.bni_va: return 'bni_va';
    case MidtransChannel.bri_va: return 'bri_va';
    case MidtransChannel.permata_va: return 'permata_va';
    case MidtransChannel.echannel: return 'echannel';
  }
}

class CheckoutItem {
  final int productId;
  final String name;
  final String imageUrl;
  final int qty;
  final int unitPrice;
  final int lineTotal;
  CheckoutItem({required this.productId,required this.name,required this.imageUrl,required this.qty,required this.unitPrice,required this.lineTotal});
  factory CheckoutItem.fromJson(Map<String, dynamic> j) => CheckoutItem(
    productId: j['product_id'] ?? j['id'] ?? 0,
    name: (j['name'] ?? j['product_name'] ?? '').toString(),
    imageUrl: (j['image_url'] ?? j['imageUrl'] ?? '').toString(),
    qty: (j['qty'] ?? j['quantity'] ?? 0) as int,
    unitPrice: (j['unit_price'] ?? j['price'] ?? 0) as int,
    lineTotal: (j['line_total'] ?? (((j['qty'] ?? 0) as int) * ((j['unit_price'] ?? j['price'] ?? 0) as int))) as int,
  );
}

class CourierOption {
  final String code;
  final String company;
  final String serviceCode;
  final String serviceName;
  final String etd;
  final int price;
  CourierOption({required this.code,required this.company,required this.serviceCode,required this.serviceName,required this.etd,required this.price});
  factory CourierOption.fromJson(Map<String,dynamic> j) => CourierOption(
    code: (j['code'] ?? j['courier_code'] ?? '').toString(),
    company: (j['company'] ?? j['courier'] ?? '').toString(),
    serviceCode: (j['service_code'] ?? '').toString(),
    serviceName: (j['service'] ?? j['service_name'] ?? '').toString(),
    etd: (j['etd'] ?? j['duration'] ?? '').toString(),
    price: (j['price'] ?? j['amount'] ?? 0) is double ? (j['price'] as double).toInt() : (j['price'] ?? j['amount'] ?? 0) as int,
  );
}

class CheckoutPreview {
  final List<CheckoutItem> items;
  final List<CourierOption> courierOptions;
  final int subtotal;
  final int shippingFee;
  final double distanceKm;
  final int discountTotal;
  final int grandTotal;
  final Map<String,dynamic>? selectedCourier;
  CheckoutPreview({
    required this.items,
    required this.courierOptions,
    required this.subtotal,
    required this.shippingFee,
    required this.distanceKm,
    required this.discountTotal,
    required this.grandTotal,
    required this.selectedCourier,
  });
  factory CheckoutPreview.fromJson(Map<String,dynamic> j) => CheckoutPreview(
    items: ((j['items'] ?? j['data'] ?? []) as List).map((e)=>CheckoutItem.fromJson(Map<String,dynamic>.from(e))).toList(),
    courierOptions: ((j['courier_options'] ?? j['rates'] ?? []) as List).map((e)=>CourierOption.fromJson(Map<String,dynamic>.from(e))).toList(),
    subtotal: ((j['subtotal'] ?? 0) as num).toInt(),
    shippingFee: ((j['shipping_fee'] ?? j['ongkir'] ?? 0) as num).toInt(),
    distanceKm: ((j['distance_km'] ?? 0) as num).toDouble(),
    discountTotal: ((j['discount_total'] ?? 0) as num).toInt(),
    grandTotal: ((j['grand_total'] ?? j['total'] ?? 0) as num).toInt(),
    selectedCourier: j['selected_courier'] != null ? Map<String,dynamic>.from(j['selected_courier']) : null,
  );
}

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});
  @override State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _addressCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _mapController = Completer<GoogleMapController>();
  LatLng? _pin;
  bool _loading = false;
  CheckoutPreview? _preview;
  String? _error;
  PaymentMethod _method = PaymentMethod.midtrans;
  MidtransChannel _channel = MidtransChannel.qris;
  int _selectedCourierIndex = 0;

  @override
  void initState() {
    super.initState();
    _initLocationAndPreview();
  }

  Future<void> _initLocationAndPreview() async {
    final fallback = const LatLng(-6.200000, 106.816666);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        perm = await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      _pin = LatLng(pos.latitude, pos.longitude);
    } catch (_) { _pin = fallback; }
    setState(() {});
    await _reloadPreview();
  }

  Future<void> _reloadPreview() async {
    setState(()=>_loading=true);
    try {
      final dio = API.dio;
      final resp = await dio.post('buyer/checkout/preview', data: {
        'address_text': _addressCtrl.text,
        'lat': _pin?.latitude,
        'lng': _pin?.longitude,
        'courier_code': _preview?.selectedCourier?['code'],
        'courier_service_code': _preview?.selectedCourier?['service_code'],
      });
      final data = (resp.data is Map<String,dynamic>) ? resp.data : (resp.data['data'] ?? resp.data);
      setState(() {
        _preview = CheckoutPreview.fromJson(Map<String,dynamic>.from(data));
        if ((_preview!.courierOptions).isNotEmpty && _preview!.selectedCourier==null) {
          _selectedCourierIndex = 0;
        } else if (_preview!.selectedCourier != null) {
          final sc = _preview!.selectedCourier!;
          final idx = _preview!.courierOptions.indexWhere((c)=> c.code==sc['code'] && c.serviceCode==sc['service_code']);
          if (idx >= 0) _selectedCourierIndex = idx;
        }
        _error = null;
      });
    } catch (e) {
      setState(()=>_error = e.toString());
    } finally { setState(()=>_loading=false); }
  }

  Future<void> _pickOnMap(LatLng p) async {
    _pin = p;
    setState((){});
    await _reloadPreview();
  }

  Widget _buildMap() {
    final center = _pin ?? const LatLng(-6.2,106.816666);
    return SizedBox(
      height: 180,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: GoogleMap(
          initialCameraPosition: CameraPosition(target: center, zoom: 15),
          myLocationEnabled: true, myLocationButtonEnabled: true,
          onMapCreated: (c)=>_mapController.complete(c),
          markers: { Marker(markerId: const MarkerId('pin'), position: center, draggable: true, onDragEnd: _pickOnMap) },
          onTap: _pickOnMap,
        ),
      ),
    );
  }

  Widget _buildCourierSelector() {
    final opts = _preview?.courierOptions ?? const <CourierOption>[];
    if (opts.isEmpty) return const Text('Tarif kurir belum tersedia. Pastikan alamat/koordinat terisi.');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Kurir (Biteship)', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      ...List.generate(opts.length, (i){
        final o = opts[i];
        final selected = i == _selectedCourierIndex;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('${o.company} - ${o.serviceName}'),
          subtitle: Text('ETD: ${o.etd} • Rp ${o.price}'),
          trailing: Radio<int>(value: i, groupValue: _selectedCourierIndex, onChanged: (v) async {
            setState(()=>_selectedCourierIndex = v ?? 0);
            _preview = CheckoutPreview(
              items: _preview!.items,
              courierOptions: _preview!.courierOptions,
              subtotal: _preview!.subtotal,
              shippingFee: o.price,
              distanceKm: _preview!.distanceKm,
              discountTotal: _preview!.discountTotal,
              grandTotal: _preview!.subtotal + o.price - _preview!.discountTotal,
              selectedCourier: {
                'code': o.code, 'company': o.company,
                'service_code': o.serviceCode, 'service_name': o.serviceName, 'etd': o.etd,
              },
            );
            setState((){});
          }),
          shape: RoundedRectangleBorder(
            side: BorderSide(color: selected ? Theme.of(context).colorScheme.primary : Colors.grey.shade300),
            borderRadius: BorderRadius.circular(10),
          ),
        );
      })
    ]);
  }

  Widget _buildChannelSelector() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Channel Midtrans', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilterChip(label: const Text('QRIS'), selected: _channel==MidtransChannel.qris, onSelected: (_)=>setState(()=>_channel=MidtransChannel.qris)),
        FilterChip(label: const Text('GoPay'), selected: _channel==MidtransChannel.gopay, onSelected: (_)=>setState(()=>_channel=MidtransChannel.gopay)),
        FilterChip(label: const Text('Kartu'), selected: _channel==MidtransChannel.card, onSelected: (_)=>setState(()=>_channel=MidtransChannel.card)),
        FilterChip(label: const Text('BCA VA'), selected: _channel==MidtransChannel.bca_va, onSelected: (_)=>setState(()=>_channel=MidtransChannel.bca_va)),
        FilterChip(label: const Text('BNI VA'), selected: _channel==MidtransChannel.bni_va, onSelected: (_)=>setState(()=>_channel=MidtransChannel.bni_va)),
        FilterChip(label: const Text('BRI VA'), selected: _channel==MidtransChannel.bri_va, onSelected: (_)=>setState(()=>_channel=MidtransChannel.bri_va)),
        FilterChip(label: const Text('Permata VA'), selected: _channel==MidtransChannel.permata_va, onSelected: (_)=>setState(()=>_channel=MidtransChannel.permata_va)),
        FilterChip(label: const Text('Mandiri (E-channel)'), selected: _channel==MidtransChannel.echannel, onSelected: (_)=>setState(()=>_channel=MidtransChannel.echannel)),
      ]),
    ]);
  }

  Future<void> _payNow() async {
    if (_preview == null) await _reloadPreview();
    setState(()=>_loading=true);
    try {
      final dio = API.dio;
      final selectedCourier = _preview?.selectedCourier ?? ( (_preview?.courierOptions.isNotEmpty ?? false)
        ? {
            'code': _preview!.courierOptions[_selectedCourierIndex].code,
            'company': _preview!.courierOptions[_selectedCourierIndex].company,
            'service_code': _preview!.courierOptions[_selectedCourierIndex].serviceCode,
            'service_name': _preview!.courierOptions[_selectedCourierIndex].serviceName,
            'etd': _preview!.courierOptions[_selectedCourierIndex].etd,
          }
        : null );

      final resp = await dio.post('buyer/checkout', data: {
        'payment_method': 'midtrans',
        'payment_channel': midtransChannelToApi(_channel),
        'address_text': _addressCtrl.text,
        'lat': _pin?.latitude, 'lng': _pin?.longitude,
        'note': _noteCtrl.text,
        'courier_code': selectedCourier?['code'],
        'courier_service_code': selectedCourier?['service_code'],
      });
      final data = (resp.data is Map<String,dynamic>) ? resp.data : (resp.data['data'] ?? resp.data);
      final orderId = data['order_id'] ?? data['id'];

      final va = data['va'] as Map?;
      final mandiri = data['mandiri'] as Map?;
      final amount = (data['amount'] ?? _preview?.grandTotal ?? 0) as int;
      final redirectUrl = data['redirect_url'];

      if (!mounted) return;
      Navigator.of(context).pushNamed('/payment-awaiting', arguments: {
        'orderId': int.tryParse('$orderId') ?? 0,
        'amount': amount,
        'bankName': va?['bank']?.toString(),
        'vaNumber': va?['va_number']?.toString(),
        'billKey': mandiri?['bill_key']?.toString(),
        'billerCode': mandiri?['biller_code']?.toString(),
        'redirectUrl': redirectUrl?.toString(),
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Checkout gagal: $e')));
    } finally {
      if (mounted) setState(()=>_loading=false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gt = _preview?.grandTotal ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: RefreshIndicator(
        onRefresh: _reloadPreview,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Alamat & Lokasi', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _buildMap(),
              const SizedBox(height: 8),
              TextField(
                controller: _addressCtrl, maxLines: 2,
                decoration: const InputDecoration(hintText: 'Detail alamat (blok/jalan/patokan)…', border: OutlineInputBorder()),
                onChanged: (_)=>_reloadPreview(),
              ),
              const SizedBox(height: 8),
              TextField(controller: _noteCtrl, maxLines: 2, decoration: const InputDecoration(hintText: 'Catatan untuk penjual (opsional)', border: OutlineInputBorder())),
            ])),
            const SizedBox(height: 12),

            _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Ringkasan Item', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
              if ((_preview?.items ?? const []).isEmpty) const Text('Keranjang kosong / data item belum tersedia.'),
              ...((_preview?.items ?? const <CheckoutItem>[]).map((it) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: ClipRRect(borderRadius: BorderRadius.circular(8),
                  child: Image.network(it.imageUrl, width: 56, height: 56, fit: BoxFit.cover, errorBuilder: (_, __, ___) =>
                    Container(width: 56, height: 56, color: Colors.grey.shade200, child: const Icon(Icons.image)))),
                title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('x${it.qty} • Rp ${it.unitPrice}'),
                trailing: Text('Rp ${it.lineTotal}', style: const TextStyle(fontWeight: FontWeight.w700)),
              ))).toList(),
            ])),
            const SizedBox(height: 12),

            _card(child: _buildCourierSelector()),
            const SizedBox(height: 12),

            _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Metode Pembayaran', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                ChoiceChip(label: const Text('Midtrans'), selected: _method==PaymentMethod.midtrans, onSelected: (_)=>setState(()=>_method=PaymentMethod.midtrans)),
                ChoiceChip(label: const Text('Transfer'), selected: _method==PaymentMethod.transfer, onSelected: (_)=>setState(()=>_method=PaymentMethod.transfer)),
                ChoiceChip(label: const Text('COD'), selected: _method==PaymentMethod.cod, onSelected: (_)=>setState(()=>_method=PaymentMethod.cod)),
              ]),
              const SizedBox(height: 8),
              if (_method == PaymentMethod.midtrans) _buildChannelSelector(),
            ])),
            const SizedBox(height: 12),

            _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Total', style: TextStyle(fontWeight: FontWeight.w700)),
              _row('Subtotal', _preview?.subtotal ?? 0),
              _row('Ongkir', _preview?.shippingFee ?? 0),
              _row('Diskon', -(_preview?.discountTotal ?? 0)),
              const Divider(),
              _row('Grand Total', gt, bold: true),
            ])),
            const SizedBox(height: 120),
          ]),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16,8,16,16),
          child: SizedBox(height: 48, child: ElevatedButton(
            onPressed: _loading ? null : _payNow,
            child: Text(_loading ? 'Memproses...' : 'Bayar Sekarang (Rp $gt)'),
          )),
        ),
      ),
    );
  }

  Widget _row(String label, int nominal, {bool bold=false}) {
    final s = TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [Expanded(child: Text(label, style: s)), Text('Rp $nominal', style: s)]),
    );
  }

  Widget _card({required Widget child}) => Card(
    elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    child: Padding(padding: const EdgeInsets.all(12), child: child),
  );
}
