// lib/app/presentation/screens/buyer/checkout_screen.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/foundation.dart' as foundation; // untuk describeEnum
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlng;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:dio/dio.dart';

// Providers
import '../../providers/checkout_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/auth_provider.dart';

// Model cart item (opsional; UI kita aman untuk dynamic)
import '../../../common/models/cart_item.dart' show CartItemModel;

// 🔽 Client khusus Snap & endpoint lain (punya kamu) — ALIAS agar tidak konflik dengan API baru
import '../../../../data/services/api.dart' as LegacyAPI;

// 🔽 API (baru) untuk akses dio di V2
import '../../../core/network/api.dart'; // exposes API.dio

import 'snap_webview_page.dart';
import '../../widgets/map_pick_page.dart';

// === PATCH-A: CONFIG & ENV (Flutter) ===
const bool kUseServerPreview = true; // <-- WAJIB true agar ongkir & item dari server
const String kEnvShopOriginLat =
    String.fromEnvironment('SHOP_ORIGIN_LAT', defaultValue: '-6.200000');
const String kEnvShopOriginLng =
    String.fromEnvironment('SHOP_ORIGIN_LNG', defaultValue: '106.816666');

// fallback ongkir bila server tidak balas
const int kShippingFlatFallback = 12000;

// channel Midtrans default bila server tidak kirim daftar
const List<List<String>> kDefaultMidtransChannels = [
  ['qris', 'QRIS'],
  ['gopay', 'GoPay'],
  ['bca_va', 'BCA VA'],
  ['bni_va', 'BNI VA'],
  ['bri_va', 'BRI VA'],
  ['permata_va', 'Permata VA'],
  ['card', 'Kartu Kredit'],
];

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  // ====== state pembayaran (LAMA) ======
  String _method = 'midtrans'; // default (dipakai alur preview lama)

  // ====== state pembayaran (BARU) ======
  final _notesController = TextEditingController(); // Catatan pembeli
  final _manualAddrCtrl = TextEditingController(); // Alamat manual
  String _selectedMethod = 'midtrans'; // 'midtrans' | 'transfer_manual' | 'cod'
  String _selectedChannel = 'qris'; // 'bca_va' | 'qris' | 'gopay' | 'cc'

  // ====== state peta & alamat (OSM) ======
  final MapController _mapCtl = MapController();
  latlng.LatLng? _pin;
  String? _formatted;
  bool _locLoading = false;
  bool _geocodeLoading = false;
  bool _markDefault = true;

  // ====== state preview & rate selection ======
  bool _bootstrapped = false;
  bool _loadingPreview = false;
  String? _previewForCode; // order_code yang terakhir dipreview
  List<Map<String, dynamic>> _rates = []; // dari /checkout/preview
  List<Map<String, dynamic>> _channels = []; // dari /checkout/preview
  Map<String, dynamic>? _chosenRate; // rate terpilih
  String _orderStatusText = 'pending'; // AnimatedSwitcher target
  bool _useInsurance = false;
  Timer? _pollTimer;

  // === PATCH-B: PREVIEW STATE ===
  Map<String, dynamic>? _preview; // payload preview penuh
  List<dynamic> _previewItems = []; // barang dari server
  int _pvSubtotal = 0, _pvShipping = 0, _pvDiscount = 0, _pvGrand = 0;

  // Kalau server-mu belum punya endpoint preview, biarkan false (fallback).
  static const bool _USE_SERVER_PREVIEW = true;

  // fallback pusat (Jakarta)
  static const latlng.LatLng _fallbackJakarta =
      latlng.LatLng(-6.200000, 106.816666);

  // ====== PATCH-B: daftar cart_item_id yang DIPAKSA dari argumen ======
  List<int> _forcedIds = [];

  // === NEW: helper ekstraksi ID dari args navigator ===
  // Ambil ID dari berbagai bentuk argumen navigator (list/singular/obj)
  List<int> _extractIdsFromArgs(Map args) {
    final out = <int>[];
    void add(dynamic v) {
      final id = int.tryParse('$v') ?? 0;
      if (id > 0) out.add(id);
    }

    // list standar
    if (args['cart_item_ids'] is List) {
      for (final v in (args['cart_item_ids'] as List)) add(v);
    }

    // singular / variasi key
    for (final k in ['cart_item_id', 'cartItemId', 'item_id', 'id']) {
      if (args[k] != null) add(args[k]);
    }

    // objek cart_item
    for (final k in ['cart_item', 'cartItem']) {
      final m = args[k];
      if (m is Map && m['id'] != null) add(m['id']);
    }

    return out.toSet().toList();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Inisialisasi pin dari alamat default (kalau ada)
      final cp = context.read<CheckoutProvider>();
      try {
        final a = (cp as dynamic).shippingAddress;
        if (a is Map && a['latitude'] != null && a['longitude'] != null) {
          _pin = latlng.LatLng(
            (a['latitude'] as num).toDouble(),
            (a['longitude'] as num).toDouble(),
          );
          _formatted = (a['address'] as String?)?.trim();
        } else {
          _pin = _fallbackJakarta;
        }
      } catch (_) {
        _pin = _fallbackJakarta;
      }
      // set input manual sesuai formatted awal (kalau ada)
      _manualAddrCtrl.text = (_formatted ?? '').trim();

      // ==== PATCH-B: baca argumen & paksa seleksi ====
      try {
        final args = (ModalRoute.of(context)?.settings.arguments as Map?) ?? {};
        _forcedIds = _extractIdsFromArgs(args); // ✅ gunakan helper baru
        if (_forcedIds.isNotEmpty) {
          _forceSelectIds(_forcedIds); // ⬅️ tidak ada lagi compile error
        }
      } catch (_) {}

      // Pastikan cart terisi & ada selection untuk checkout (fallback)
      final cart = context.read<CartProvider>();
      try {
        final itemsEmpty = (cart.items as List?)?.isEmpty ?? false;
        if (itemsEmpty) {
          try {
            await (cart as dynamic).fetch();
          } catch (_) {}
        }
      } catch (_) {}
      bool hasSel = false;
      try {
        hasSel = ((cart as dynamic).hasSelection == true);
      } catch (_) {
        try {
          final sel = (cart as dynamic).selectedIds;
          if (sel is Iterable && sel.isNotEmpty) hasSel = true;
        } catch (_) {}
      }
      try {
        final hasItems = (cart.items as List?)?.isNotEmpty ?? false;
        if (_forcedIds.isEmpty && !hasSel && hasItems) {
          try {
            (cart as dynamic).selectAll();
          } catch (_) {}
        }
      } catch (_) {}

      if (mounted) setState(() => _bootstrapped = true);

      // === PATCH-D: panggil preview server saat bootstrap
      await _reloadPreviewFromServer();
    });
  }

  /// Helper aman untuk memaksa seleksi ID di CartProvider tanpa asumsi signature.
  // Paksa CartProvider menyeleksi hanya ID yang diberikan (tahan-banting)
  void _forceSelectIds(List<int> ids) {
    final cart = context.read<CartProvider>();
    try {
      // andai ada API selectOnly(Set<int>)
      (cart as dynamic).selectOnly(ids.toSet());
      return;
    } catch (_) {}

    try {
      (cart as dynamic).clearSelection();
    } catch (_) {}

    for (final id in ids) {
      // coba beberapa signature umum
      try {
        (cart as dynamic).toggleSelect(id, true);
        continue;
      } catch (_) {}
      try {
        (cart as dynamic).toggleSelect(id, selected: true);
        continue;
      } catch (_) {}
      try {
        (cart as dynamic).setSelected(id, true);
        continue;
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _notesController.dispose();
    _manualAddrCtrl.dispose();
    super.dispose();
  }

  // ======================= PREVIEW (optional) =======================
  Future<void> _loadPreview(String orderCode) async {
    if (_loadingPreview || _previewForCode == orderCode) return;
    setState(() {
      _loadingPreview = true;
      _rates = [];
      _channels = [];
      _chosenRate = null;
    });
    try {
      final token = _readAuthToken(context);
      if (token.isEmpty) throw Exception('Silakan login terlebih dahulu');
      LegacyAPI.API.setToken(token);

      final data =
          await LegacyAPI.API.checkoutPreview(orderCode); // <-- bisa 404
      final rates = List<Map<String, dynamic>>.from(
        (data['shipping_rates'] as List?) ?? const [],
      );
      final channels = List<Map<String, dynamic>>.from(
        (data['payment_channels'] as List?) ?? const [],
      );

      setState(() {
        _previewForCode = orderCode;
        _rates = rates;
        _channels = channels;
        _method = channels.isNotEmpty
            ? (channels.first['code']?.toString() ?? 'midtrans')
            : 'midtrans';
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Tarif pengiriman belum tersedia. Melanjutkan tanpa preview.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingPreview = false);
    }
  }

  // === PATCH-C: Ambil preview dari server (AMAN) ===
  Future<void> _reloadPreviewFromServer() async {
    if (!kUseServerPreview) return;
    try {
      final Dio dio = API.dio; // dipakai seluruh V2
      final cart = context.read<CartProvider>();

      // 🔒 Kumpulkan IDs: forced > selectedIds > fallback dari item.selected
      List<int> ids = _forcedIds.isNotEmpty
          ? _forcedIds
          : cart.selectedIds
              .map((e) => int.tryParse('$e') ?? 0)
              .where((e) => e > 0)
              .toList();

      if (ids.isEmpty) {
        try {
          ids = cart.items
              .where(_isCartRowSelected) // ✅ aman, tidak akses ['selected'] langsung
              .map((it) => _extractCartItemId(it))
              .where((e) => e > 0)
              .toList();
        } catch (_) {}
      }

      // Kunci kurir/layanan jika sebelumnya sudah dipilih
      final String? lockCourier = _chosenRate == null
          ? null
          : ((_chosenRate!['courier_code'] ?? _chosenRate!['code'])?.toString());
      final String? lockService = _chosenRate == null
          ? null
          : ((_chosenRate!['service_code'] ?? _chosenRate!['service'])?.toString());

      // ✅ susun payload + include_items (WAJIB)
      final Map<String, dynamic> payload = {
        'address_text': _formatted?.trim().isNotEmpty == true
            ? _formatted!.trim()
            : (_manualAddrCtrl.text.trim().isNotEmpty
                ? _manualAddrCtrl.text.trim()
                : null),
        'lat': _pin?.latitude,
        'lng': _pin?.longitude,
        'use_insurance': _useInsurance,
        'shipping_courier_code': lockCourier,
        'shipping_service_code': lockService,
        'include_items': true, // ⬅️ minta server balikan daftar items
      };
      if (ids.isNotEmpty) {
        payload['cart_item_ids'] = ids; // ⬅️ kunci seleksi item
      }

      final resp = await dio.post('buyer/checkout/preview', data: payload);

      // === String-safe ===
      final Map<String, dynamic> data = _jsonMap(resp.data);
      final Map<String, dynamic> mData = _jsonMap(data['data']);
      final m = mData.isNotEmpty ? mData : data;

      final items = _jsonList(m['items']);
      final subtotal = (m['subtotal'] is num)
          ? (m['subtotal'] as num)
          : (double.tryParse('${m['subtotal']}') ?? 0);
      final shipping = (m['shipping_fee'] ?? m['ongkir']);
      final shippingNum =
          shipping is num ? shipping : (double.tryParse('$shipping') ?? 0);
      final discount = (m['discount_total'] ?? m['diskon']);
      final discountNum =
          discount is num ? discount : (double.tryParse('$discount') ?? 0);

      final dynamic gRaw = (m['grand_total'] ?? m['total']);
      final grandNum = (gRaw is num)
          ? gRaw
          : (double.tryParse('$gRaw') ?? (subtotal + shippingNum - discountNum));

      final rs = _jsonList(m['courier_options'].toString().isNotEmpty
              ? m['courier_options']
              : m['shipping_rates']) //
          .map((e) => _asMap(e))
          .toList();

      final ch = _jsonList(m['payment_channels']).map((e) => _asMap(e)).toList();

      setState(() {
        _preview = m;
        _previewItems = List<dynamic>.from(items);
        _pvSubtotal = subtotal.toInt();
        _pvShipping = shippingNum.toInt();
        _pvDiscount = discountNum.toInt();
        _pvGrand = grandNum.toInt();

        _rates = rs.map<Map<String, dynamic>>((mm) {
          return {
            'courier_code': (mm['courier_code'] ?? mm['code'] ?? '').toString(),
            'courier_company':
                (mm['courier_company'] ?? mm['company'] ?? '').toString(),
            'service_code': (mm['service_code'] ?? mm['service'] ?? '').toString(),
            'service_name': (mm['service_name'] ?? mm['service'] ?? '').toString(),
            'etd': (mm['etd'] ?? mm['estimation'] ?? '-').toString(),
            'price': (mm['total_price'] ?? mm['price'] ?? 0),
          };
        }).toList();

        if (_rates.isNotEmpty && _chosenRate == null) {
          _chosenRate = _rates.first;
        }

        _channels = ch;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Preview/ongkir sementara tidak tersedia.')));
      }
    }
  }

  // ======================= SNAP FLOW (REPLACED) =======================
  Future<void> _onCheckoutSnap(String orderCode) async {
    try {
      final token = _readAuthToken(context);
      if (token.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Silakan login terlebih dahulu.')),
        );
        return;
      }
      LegacyAPI.API.setToken(token);

      // Jika ada preview ongkir, wajib pilih salah satu
      if (_rates.isNotEmpty && _chosenRate == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Pilih metode pengiriman terlebih dahulu.')),
        );
        return;
      }

      // ✅ AMAN: tanpa obj?['key']
      final int shippingCost = (_rates.isEmpty || _chosenRate == null)
          ? 0
          : _toInt(_chosenRate!['price']);

      final String? courierCode = (_rates.isEmpty || _chosenRate == null)
          ? null
          : ((_chosenRate!['courier_code'] ?? _chosenRate!['code'])?.toString());

      final String? serviceCode = (_rates.isEmpty || _chosenRate == null)
          ? null
          : ((_chosenRate!['service_code'] ?? _chosenRate!['service'])?.toString());

      // 1) Coba method-method yang mungkin sudah ada di class API kamu
      String? redirectUrl;
      try {
        final snap = await (LegacyAPI.API as dynamic).createSnapTokenAdvanced(
          orderCode: orderCode,
          courierCode: courierCode,
          serviceCode: serviceCode,
          shippingCost: shippingCost,
        );
        redirectUrl = snap?['redirect_url'] as String?;
      } catch (_) {
        try {
          final snap = await (LegacyAPI.API as dynamic)
              .createMidtransSnap(orderCode: orderCode);
          redirectUrl = snap?['redirect_url'] as String?;
        } catch (_) {
          try {
            final snap = await (LegacyAPI.API as dynamic)
                .midtransSnap(orderCode: orderCode);
            redirectUrl = snap?['redirect_url'] as String?;
          } catch (_) {
            // lanjut ke auto-discover
          }
        }
      }

      // 2) Auto-discover endpoint di server (POST & GET, beberapa path umum)
      redirectUrl ??= await _discoverSnapRedirectUrl(orderCode, token);

      if (redirectUrl == null || redirectUrl.isEmpty) {
        throw Exception('Tidak menemukan endpoint Snap pada server.');
      }

      // 3) Buka Snap
      final done = await Navigator.push<bool>(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) =>
              SnapWebViewPage(redirectUrl: redirectUrl!),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );

      if (done == true) {
        _startPollingOrder(orderCode);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memproses pembayaran: $e')),
      );
    }
  }

  void _startPollingOrder(String code) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (tm) async {
      try {
        final d = await LegacyAPI.API.fetchOrder(code);
        final order = d['order'] as Map?;
        final status = (order?['status'] ?? '').toString();

        if (!mounted) return;
        setState(() => _orderStatusText = status);

        if ([
          'fulfillment_pending',
          'shipment_created',
          'shipped',
          'delivered',
          'completed',
          'paid'
        ].contains(status)) {
          tm.cancel();
          final trackingId = d['order']?['tracking_id'];
          final labelUrl = d['order']?['label_url'];
          if (trackingId != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Tracking: $trackingId')),
            );
          }
          if (labelUrl is String && labelUrl.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Label tersedia.')),
            );
          }
        }
      } catch (_) {}
    });
  }

  // ======================= peta & alamat (OSM) =======================
  Future<void> _moveCamera(latlng.LatLng target, {double zoom = 16}) async {
    _mapCtl.move(target, zoom);
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _locLoading = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Izin lokasi ditolak.')),
        );
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Aktifkan layanan lokasi di perangkat.')),
        );
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final p = latlng.LatLng(pos.latitude, pos.longitude);
      setState(() => _pin = p);
      await _moveCamera(p);
      await _reverseGeocodeOSM(p);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal ambil lokasi: $e')),
      );
    } finally {
      if (mounted) setState(() => _locLoading = false);
    }
  }

  Future<void> _reverseGeocodeOSM(latlng.LatLng p) async {
    setState(() => _geocodeLoading = true);
    try {
      final params = <String, String>{
        'format': 'jsonv2',
        'lat': '${p.latitude}',
        'lon': '${p.longitude}',
        'addressdetails': '1',
        'accept-language': 'id',
        'zoom': '18',
        if (kIsWeb) 'email': 'support@yourdomain.com',
      };
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', params);

      final resp = await http.get(
        uri,
        headers: kIsWeb
            ? {}
            : {
                'User-Agent': 'e-buyur/1.0 (support@yourdomain.com)',
              },
      );

      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final displayName = (data['display_name'] as String?)?.trim();
      final address = data['address'] as Map<String, dynamic>?;
      final built = displayName ?? _buildAddressFromNominatim(address);

      setState(() {
        _formatted = built ?? '${p.latitude}, ${p.longitude}';
        _manualAddrCtrl.text = _formatted ?? '';
      });

      // aman kalau provider tidak punya method ini
      try {
        (context.read<CheckoutProvider>() as dynamic).setAddressLocal(
          latitude: p.latitude,
          longitude: p.longitude,
          formattedAddress: _formatted ?? '',
        );
      } catch (_) {}

      // === PATCH-D: refresh preview setelah alamat berubah
      await _reloadPreviewFromServer();
    } catch (e) {
      setState(() {
        _formatted = '${p.latitude}, ${p.longitude}';
        _manualAddrCtrl.text = _formatted ?? '';
      });
    } finally {
      if (mounted) setState(() => _geocodeLoading = false);
    }
  }

  String? _buildAddressFromNominatim(Map<String, dynamic>? a) {
    if (a == null) return null;
    String pick(String k) => (a[k] as String? ?? '').trim();
    final parts = <String>[
      pick('road'),
      pick('neighbourhood').isNotEmpty ? pick('neighbourhood') : pick('suburb'),
      pick('village').isNotEmpty ? pick('village') : pick('town'),
      pick('city_district'),
      pick('city'),
      pick('state'),
      pick('postcode'),
      pick('country'),
    ].where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return null;
    return parts.join(', ');
  }

  Future<void> _onSaveAddress() async {
    final pin = _pin;
    final formatted = _formatted ?? _manualAddrCtrl.text.trim();
    if (formatted.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Isi alamat manual atau pilih titik di peta.')),
      );
      return;
    }
    final token = _readAuthToken(context);
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Silakan login dahulu.')),
      );
      return;
    }
    try {
      final prov = context.read<CheckoutProvider>();
      Map<String, dynamic>? saved;
      try {
        saved = await (prov as dynamic).saveAddress(
          token: token,
          latitude: pin?.latitude,
          longitude: pin?.longitude,
          formattedAddress: formatted,
          setDefault: _markDefault,
        );
      } catch (_) {}

      if (saved == null) {
        try {
          (prov as dynamic).setAddressLocal(
            latitude: pin?.latitude,
            longitude: pin?.longitude,
            formattedAddress: formatted,
          );
        } catch (_) {}
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Alamat dipakai untuk pesanan ini (tidak disimpan permanen).'),
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alamat tersimpan sebagai permanen.')),
        );
      }
      // refresh preview sesudah save
      await _reloadPreviewFromServer();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal simpan alamat: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final co = context.watch<CheckoutProvider>();
    final cart = context.watch<CartProvider>();

    // a) Ambil item terpilih & subtotal dari CartProvider
    final selectedItems = cart.selectedItems;
    final subtotalLocal = cart.selectedSubtotal;

    final isBusy = !_bootstrapped || cart.loading || co.loading;

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: isBusy
          ? const Center(child: CircularProgressIndicator())
          : (selectedItems.isEmpty && _previewItems.isEmpty
              ? const Center(child: Text('Tidak ada item untuk checkout.'))
              : _buildBody(
                  co, List<dynamic>.from(selectedItems), subtotalLocal)),
      bottomNavigationBar:
          isBusy ? null : _buildBottom(co, subtotalLocal, selectedItems),
    );
  }

  Widget _buildBody(
      CheckoutProvider co, List<dynamic> selectedItems, int subtotalLocal) {
    // status & map markers
    bool savingAddr = false;
    try {
      savingAddr = ((co as dynamic).isSavingAddress == true);
    } catch (_) {}

    final markers = <Marker>[
      if (_pin != null)
        Marker(
          point: _pin!,
          width: 40,
          height: 40,
          child: const Icon(Icons.location_pin, size: 40, color: Colors.red),
        ),
    ];

    // 👇 Tambahan: siapkan teks kurir/layanan TANPA obj?['key']
    final String courierStr = (_chosenRate == null)
        ? ''
        : (((_chosenRate!['courier_code'] ?? _chosenRate!['code'])?.toString()) ?? '')
            .toUpperCase();
    final String serviceStr = (_chosenRate == null)
        ? '-'
        : ((_chosenRate!['service_name'] ??
                    _chosenRate!['service_code'] ??
                    _chosenRate!['service'])
                ?.toString() ??
            '-');

    // ====== STYLE ala Tokopedia (hanya tampilan) ======
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ====== Status Order ======
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Container(
            key: ValueKey(_orderStatusText),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline),
                const SizedBox(width: 8),
                Text('Status: ${_orderStatusText.toUpperCase()}'),
              ],
            ),
          ),
        ),

        // ====== Card 1: Address Picker (OSM) + CATATAN + INPUT MANUAL ======
        Card(
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              SizedBox(
                height: 220,
                child: ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(12)),
                  child: FlutterMap(
                    mapController: _mapCtl,
                    options: MapOptions(
                      initialCenter: _pin ?? _fallbackJakarta,
                      initialZoom: 14,
                      onTap: (tapPos, point) {
                        setState(() => _pin = point);
                        _reverseGeocodeOSM(point);
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.yourcompany.ebuyur',
                      ),
                      MarkerLayer(markers: markers),
                    ],
                  ),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _locLoading ? null : _useCurrentLocation,
                          icon: _locLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.my_location),
                          label: const Text('Lokasi Saya'),
                        ),
                        OutlinedButton.icon(
                          onPressed: (_pin == null || _geocodeLoading)
                              ? null
                              : () => _reverseGeocodeOSM(_pin!),
                          icon: _geocodeLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.refresh),
                          label: const Text('Perbarui Alamat'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // INPUT MANUAL alamat
                    TextField(
                      controller: _manualAddrCtrl,
                      decoration: InputDecoration(
                        labelText: 'Alamat pengiriman (manual)',
                        hintText: 'Tulis alamat lengkap jika tidak pakai peta',
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onChanged: (v) {
                        setState(() => _formatted = v.trim());
                        _reloadPreviewFromServer(); // === PATCH-D
                      },
                    ),
                    const SizedBox(height: 12),
                    Text('Alamat Pengiriman',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.place_outlined, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _formatted?.isNotEmpty == true
                                ? _formatted!
                                : 'Pilih titik di peta atau isi alamat manual',
                            style: TextStyle(
                                color: Colors.grey[800], height: 1.4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _markDefault,
                      onChanged: (v) =>
                          setState(() => _markDefault = v ?? true),
                      title: const Text(
                          'Simpan sebagai alamat default (permanen)',
                          style: TextStyle(fontSize: 14)),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: (savingAddr) ? null : _onSaveAddress,
                        icon: savingAddr
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                            : const Icon(Icons.save_outlined),
                        label: Text(
                            savingAddr ? 'Menyimpan...' : 'Simpan Alamat'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // === Catatan Pembeli (BARU) ===
                    TextField(
                      controller: _notesController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Catatan untuk penjual (opsional)',
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ====== Card 2: Pengiriman (ringkas)
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Pengiriman',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Text(
                  _rates.isNotEmpty && _chosenRate != null
                      ? 'Kurir: $courierStr • Layanan: $serviceStr'
                      : 'Belum memilih tarif (pakai ongkir flat sementara).',
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // ====== Card 3: Items dari pilihan Cart/Preview ======
        _CartItemsCard(
          items: _previewItems.isNotEmpty
              ? List<dynamic>.from(_previewItems)
              : List<dynamic>.from(selectedItems),
        ),

        const SizedBox(height: 12),

        // ====== (opsional) daftar tarif dari preview ======
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: (_loadingPreview && _rates.isEmpty)
                ? const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        CircularProgressIndicator(strokeWidth: 2),
                        SizedBox(width: 12),
                        Text('Mengambil ongkir...')
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        title: const Text('Metode Pengiriman',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        trailing: TextButton(
                          onPressed: _rates.isEmpty ? null : () {},
                          child: const Text('Lihat Semua'),
                        ),
                      ),
                      const Divider(height: 1),
                      if (_rates.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(12.0),
                          child: Text(
                              'Belum ada tarif, sistem pakai ongkir flat sementara.'),
                        ),
                      ..._rates.map((r) => RadioListTile<String>(
                            value:
                                '${r['courier_code']}|${r['service_code']}',
                            groupValue: _chosenRate == null
                                ? null
                                : '${_chosenRate!['courier_code']}|${_chosenRate!['service_code']}',
                            onChanged: (_) {
                              setState(() => _chosenRate = r);
                              _reloadPreviewFromServer(); // === PATCH-D
                            },
                            title: Text(
                              '${(r['courier_code'] ?? '').toString().toUpperCase()} - ${r['service_name'] ?? r['service_code']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text('ETD: ${r['etd'] ?? '-'}'),
                            secondary: Text(_idr(_toInt(r['price']))),
                          )),
                      SwitchListTile.adaptive(
                        value: _useInsurance,
                        onChanged: (v) {
                          setState(() => _useInsurance = v);
                          _reloadPreviewFromServer(); // update biaya jika ada asuransi
                        },
                        title: const Text('Pakai Asuransi Pengiriman'),
                        subtitle: const Text('(opsional)'),
                      ),
                    ],
                  ),
          ),
        ),

        const SizedBox(height: 12),

        // ====== Card 4: Metode Pembayaran (segmented + chips)
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Metode Pembayaran',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                const Divider(height: 1),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'cod',
                        label: Text('COD'),
                        icon: Icon(Icons.delivery_dining)),
                    ButtonSegment(
                        value: 'transfer_manual',
                        label: Text('Transfer'),
                        icon: Icon(Icons.account_balance)),
                    ButtonSegment(
                        value: 'midtrans',
                        label: Text('Midtrans (VA/QR/E)'),
                        icon: Icon(Icons.payment)),
                  ],
                  selected: {_selectedMethod},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) {
                    setState(() {
                      _selectedMethod = s.first;
                      if (_selectedMethod != 'midtrans') {
                        _selectedChannel = '';
                      } else if (_selectedChannel.isEmpty) {
                        _selectedChannel = 'qris';
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                if (_selectedMethod == 'midtrans') ...[
                  const Text('Channel Midtrans',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),

                  // === PATCH-H: channel dinamis dari server; fallback ke default
                  Builder(builder: (_) {
                    final channels = _channels.isNotEmpty
                        ? _channels.map<List<String>>((m) {
                            final mm = _asMap(m);
                            return [
                              '${mm['code']}',
                              '${mm['name'] ?? mm['code']}'
                            ];
                          }).toList()
                        : kDefaultMidtransChannels;

                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ...channels.map((ch) => ChoiceChip(
                              label: Text(ch[1]),
                              selected: _selectedChannel == ch[0],
                              onSelected: (_) =>
                                  setState(() => _selectedChannel = ch[0]),
                            )),
                      ],
                    );
                  }),
                ],

                // (Tetap) dukungan lama dari _channels jika preview mengembalikan daftar
                if (_channels.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Channel dari Server (opsional)',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ..._channels.map((ch) => RadioListTile<String>(
                        value: '${ch['code']}',
                        groupValue: _method, // variabel lama (tetap ada)
                        onChanged: (v) =>
                            setState(() => _method = v ?? 'midtrans'),
                        title: Text('${ch['name'] ?? ch['code']}'),
                        subtitle: Text(
                            'Biaya admin: ${_idr(_toInt((_asMap(ch))['fee']))}'),
                      )),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // ====== Summary ======
        Builder(
          builder: (context) {
            // === PATCH-F: total dari preview server (authoritative)
            final shipping = (_pvShipping > 0)
                ? _pvShipping
                : (_rates.isNotEmpty && _chosenRate != null
                    ? _toInt(_chosenRate!['price'])
                    : kShippingFlatFallback);
            final subtotal =
                (_pvSubtotal > 0) ? _pvSubtotal : subtotalLocal;
            final discount = _pvDiscount;
            final total = (_pvGrand > 0)
                ? _pvGrand
                : (subtotal + shipping - discount);

            return _SummaryCard(
              subtotal: subtotal,
              shipping: shipping,
              insurance: _useInsurance ? 0 : 0,
              discount: discount,
              total: total,
            );
          },
        ),

        const SizedBox(height: 90),
      ],
    );
  }

  Widget _buildBottom(CheckoutProvider co, int subtotalLocal,
      List<dynamic> selectedItems) {
    // === PATCH-F (apply juga di bottom): gunakan angka dari preview
    final shipping = _pvShipping > 0
        ? _pvShipping
        : (_rates.isNotEmpty && _chosenRate != null
            ? _toInt(_chosenRate!['price'])
            : kShippingFlatFallback);
    final subtotal = _pvSubtotal > 0 ? _pvSubtotal : subtotalLocal;
    final discount = _pvDiscount;
    final total = _pvGrand > 0 ? _pvGrand : (subtotal + shipping - discount);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.06),
              blurRadius: 12,
              offset: const Offset(0, -4),
            )
          ],
        ),
        child: ElevatedButton(
          onPressed: co.loading
              ? null
              : () async {
                  // ========= PATCH 1: handler "Bayar" dinormalisasi =========
                  final auth = context.read<AuthProvider>();
                  final authToken = auth.token ?? '';
                  if (authToken.isEmpty) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Silakan login terlebih dahulu untuk bayar.')),
                    );
                    return;
                  }

                  if (selectedItems.isEmpty && _previewItems.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Pilih produk di Keranjang dulu')),
                    );
                    return;
                  }

                  final cart = context.read<CartProvider>();

                  // === (B.3) kumpulkan cart_item_ids: forced > selected > fallback selected flag
                  List<int> ids = _forcedIds.isNotEmpty
                      ? _forcedIds
                      : cart.selectedIds
                          .map((e) => int.tryParse('$e') ?? 0)
                          .where((e) => e > 0)
                          .toList();

                  if (ids.isEmpty) {
                    try {
                      ids = cart.items
                          .where(_isCartRowSelected)
                          .map((it) => _extractCartItemId(it))
                          .where((e) => e > 0)
                          .toList();
                    } catch (_) {}
                  }

                  final address = {
                    'lat': _pin?.latitude,
                    'lng': _pin?.longitude,
                    'formatted': (_formatted?.isNotEmpty == true)
                        ? _formatted
                        : (_manualAddrCtrl.text.trim().isNotEmpty
                            ? _manualAddrCtrl.text.trim()
                            : null),
                  };

                  try {
                    final raw = await context.read<CheckoutProvider>().createOrder(
                          paymentMethod: _selectedMethod, // 'midtrans' | 'transfer_manual' | 'cod'
                          paymentChannel: _selectedMethod == 'midtrans' ? _selectedChannel : null,
                          notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
                          address: address,
                          cartItemIds: ids, // ⬅️ WAJIB kirim ini
                        );

                    // 🔒 NORMALISASI root/data sesuai patch
                    final Map<String, dynamic> root = _asMap(raw);
                    final Map<String, dynamic> data = _asMap(root['data']);
                    final Map<String, dynamic> res  = data.isNotEmpty ? data : root;

                    // ⛔️ Stop kalau server gagal
                    final bool isOk = (res['status'] == 'success') ||
                        (res['success'] == true) ||
                        res.containsKey('order_id') ||
                        (res['order'] is Map);
                    if (!isOk) {
                      final msg = (res['message'] ?? res['error'] ?? 'Gagal membuat pesanan').toString();
                      throw Exception(msg);
                    }

                    final Map<String, dynamic> payment = _asMap(res['payment']);

                    final String? url = (res['redirect_url'] as String?) ??
                                        (res['payment_redirect_url'] as String?) ??
                                        (payment['redirect_url'] as String?);

                    final dynamic orderIdAny =
                        res['order_id'] ?? (res['order'] is Map ? (res['order'] as Map)['id'] : null);
                    final int? orderId =
                        orderIdAny is int ? orderIdAny : int.tryParse('$orderIdAny');

                    // 1) Midtrans + redirect_url → WebView
                    if (_selectedMethod == 'midtrans' && url != null && url.isNotEmpty && orderId != null) {
                      if (!mounted) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MidtransWebViewPage(
                            redirectUrl: url,
                            orderId: orderId,
                          ),
                        ),
                      );
                    } else {
                      // 2) Tampilkan instruksi (VA/QR) jika tanpa redirect
                      if (payment.isNotEmpty) {
                        // ✅ GANTI PaymentAwaitingPage → BottomSheet instruksi
                        await _showPaymentInstructions(payment);
                      } else {
                        final fallback = {
                          'bank': res['bank'] ?? res['bank_name'],
                          'va_number': res['va_number'] ?? res['account_number'] ?? res['bill_key'],
                          'qris_url': res['qris_url'] ?? res['qr_url'],
                          'qr_string': res['qr_string'],
                          'amount': res['amount'] ?? res['gross_amount'] ?? res['total'],
                          'instructions': res['instructions'] ?? res['how_to'],
                        };
                        if (fallback.values.any((v) => v != null && '$v'.isNotEmpty)) {
                          await _showPaymentInstructions(fallback);
                        }
                      }

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Pesanan dibuat. Lihat instruksi di detail pesanan.')),
                        );
                      }
                    }
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Gagal membuat pesanan: $e')),
                    );
                  }
                },
          child: co.loading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text('Bayar (${_idr(total)})'),
        ),
      ),
    );
  }

  // === PATCH-G2: BottomSheet instruksi pembayaran VA/QR (AMAN) ===
  Future<void> _showPaymentInstructions(Map<String, dynamic> p) async {
    final bank =
        (p['bank'] ?? p['bank_name'] ?? '').toString().toUpperCase();

    // ⬇️ UPGRADE: dukung field bersarang payment['va'] = { va_number, ... }
    final Map<String, dynamic>? vaMap =
        p['va'] is Map ? Map<String, dynamic>.from(p['va']) : null;

    final va = (p['va_number'] ??
            p['account_number'] ??
            p['bill_key'] ??
            (vaMap != null ? vaMap['va_number'] : null) ??
            '')
        .toString();

    final holder = (p['account_name'] ?? 'a.n.').toString();
    final qris =
        (p['qris_url'] ?? p['qr_url'] ?? p['qr_string'] ?? '').toString();
    final howto = _jsonList(p['instructions'] ?? p['how_to']);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: SingleChildScrollView(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Expanded(
                      child: Text('Instruksi Pembayaran',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16))),
                  IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close))
                ]),
                const SizedBox(height: 8),
                if (bank.isNotEmpty) Text('Bank: $bank'),
                if (holder.isNotEmpty && holder != 'a.n.') Text(holder),
                if (va.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  const Text('Nomor Pembayaran / VA',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  SelectableText(va,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ],
                if (qris.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('QRIS',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(qris,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54)),
                ],
                if (howto.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Cara Bayar',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ...howto.map((e) {
                    final mm = _asMap(e);
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${mm['title'] ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          (mm['steps'] as List?)?.join('\n') ?? (mm['text'] ?? '')),
                    );
                  }),
                ],
                const SizedBox(height: 12),
                FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Sudah Bayar')),
              ]),
        ),
      ),
    );
  }

  // ===================== Utils =====================
  int _toInt(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  String _idr(int v) {
    final f = NumberFormat.currency(
        locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    return f.format(v);
  }

  String _readAuthToken(BuildContext context) {
    try {
      final ap = Provider.of<AuthProvider>(context, listen: false) as dynamic;
      final t = (ap.token is String && ap.token.isNotEmpty)
          ? ap.token
          : (ap.accessToken is String && ap.accessToken.isNotEmpty)
              ? ap.accessToken
              : (ap.bearerToken is String && ap.bearerToken.isNotEmpty)
                  ? ap.bearerToken
                  : (ap.user?.token is String &&
                          (ap.user.token as String).isNotEmpty)
                      ? ap.user.token
                      : '';
      return t is String ? t : '';
    } catch (_) {
      return '';
    }
  }

  String? _extractOrderCode(Map<String, dynamic> body) {
    // 1) { orders: [ { code: '...' } ] }
    final orders =
        (body['orders'] as List?) ?? (body['data']?['orders'] as List?);
    if (orders != null && orders.isNotEmpty) {
      final first = orders.first;
      if (first is Map && first['code'] is String) {
        return first['code'] as String;
      }
    }
    // 2) { order: { code: '...' } }
    final order =
        (body['order'] as Map?) ?? (body['data']?['order'] as Map?);
    if (order != null && order['code'] is String) return order['code'] as String;
    // 3) { order_code: '...' }
    final code = (body['order_code'] ?? body['data']?['order_code']);
    if (code is String) return code;
    return null;
  }

  // ====== Auto-discover Snap redirect URL dari server (UPDATED) ======
  Future<String?> _discoverSnapRedirectUrl(
      String orderCode, String bearerToken) async {
    // Coba baca baseUrl dari API client jika ada
    String? baseFromApi;
    try {
      baseFromApi = ((LegacyAPI.API) as dynamic).baseUrl as String?;
    } catch (_) {}
    final bases = <String>[
      if (baseFromApi != null && baseFromApi.isNotEmpty) baseFromApi,
      'https://api.ebuyurmarket.com', // dari log kamu
    ];

    // Kandidat path (urut dari yang paling mungkin)
    final postPaths = <String>[
      '/api/buyer/orders/$orderCode/pay',
      '/api/buyer/payment/snap',
      '/api/buyer/checkout/pay',
      '/api/payment/midtrans/snap',
      '/api/payments/midtrans/snap',
      '/api/buyer/pay', // body: {order_code}
      '/api/orders/pay',
    ];
    final getPaths = <String>[
      '/api/buyer/orders/$orderCode/pay',
      '/api/buyer/checkout/pay?order_code=$orderCode',
      '/api/buyer/payment/snap?order_code=$orderCode',
      '/api/payment/midtrans/snap?order_code=$orderCode',
    ];

    // Coba POST endpoints
    for (final base in bases) {
      for (final p in postPaths) {
        try {
          final uri = Uri.parse('$base$p');
          final resp = await http.post(
            uri,
            headers: {
              'Authorization': 'Bearer $bearerToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'order_code': orderCode}),
          );
          if (resp.statusCode >= 200 && resp.statusCode < 300) {
            final m = jsonDecode(resp.body) as Map<String, dynamic>;
            final url = _extractRedirectUrlFromMap(m);
            if (url != null && url.isNotEmpty) return url;
          }
        } catch (_) {}
      }
      // next base
    }

    // Coba GET endpoints
    for (final base in bases) {
      for (final p in getPaths) {
        try {
          final uri = Uri.parse('$base$p');
          final resp = await http.get(
            uri,
            headers: {'Authorization': 'Bearer $bearerToken'},
          );
          if (resp.statusCode >= 200 && resp.statusCode < 300) {
            final m = jsonDecode(resp.body) as Map<String, dynamic>;
            final url = _extractRedirectUrlFromMap(m);
            if (url != null && url.isNotEmpty) return url;
          }
        } catch (_) {}
      }
    }

    return null;
  }

  String? _extractRedirectUrlFromMap(Map<String, dynamic> m) {
    String? pick(List<String> keys) {
      dynamic cur = m;
      for (final k in keys) {
        if (cur is Map && cur.containsKey(k)) {
          cur = cur[k];
        } else {
          return null;
        }
      }
      return (cur is String && cur.isNotEmpty) ? cur : null;
    }

    // Langsung di root
    final direct =
        m['redirect_url'] ?? m['payment_url'] ?? m['url'] ?? m['snap_url'];
    if (direct is String && direct.isNotEmpty) return direct;

    // Bersarang
    final nested = pick(['data', 'redirect_url']) ??
        pick(['payment', 'redirect_url']) ??
        pick(['payment', 'url']) ??
        pick(['snap', 'redirect_url']) ??
        pick(['result', 'redirect_url']);
    if (nested != null) return nested;

    // Hanya token → bentuk URL redirection dari token
    final token = m['token'] ??
        m['snap_token'] ??
        m['transaction_token'] ??
        (m['data'] is Map ? (m['data'] as Map)['token'] : null);
    if (token is String && token.isNotEmpty) {
      // Jika sudah production ganti ke app.midtrans.com
      return 'https://app.sandbox.midtrans.com/snap/v3/redirection/$token';
    }
    return null;
  }
}

/* ===================== Widgets ===================== */

/// Widget daftar item ala Tokopedia, **tahan banting tipe**.
class _CartItemsCard extends StatelessWidget {
  const _CartItemsCard({required this.items});
  final List<dynamic> items;

  @override
  Widget build(BuildContext context) {
    String idr(int v) => NumberFormat.currency(
            locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0)
        .format(v);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(
            title:
                Text('Barang dibeli', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          const Divider(height: 1),

          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Tidak ada item.'),
            ),

          ...items.map((e) => _itemTile(e, idr)),

          const SizedBox(height: 6),
        ],
      ),
    );
  }

  // ==== helpers untuk membaca field secara aman ====
  String? _s(dynamic v) {
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
  }

  int _i(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  String _nameOf(dynamic it) {
    try {
      final v = (it as dynamic).name;
      if (v is String && v.isNotEmpty) return v;
    } catch (_) {}
    if (it is Map && _s(it['name']) != null) return _s(it['name'])!;
    if (it is Map && _s(it['title']) != null) return _s(it['title'])!;
    return 'Produk';
  }

  String? _imageOf(dynamic it) {
    try {
      final v = (it as dynamic).imageUrl;
      if (_s(v) != null) return _s(v);
    } catch (_) {}
    if (it is Map && _s(it['imageUrl']) != null) return _s(it['imageUrl']);
    if (it is Map && _s(it['image_url']) != null) return _s(it['image_url']);
    if (it is Map && _s(it['image']) != null) return _s(it['image']);
    return null;
  }

  int _qtyOf(dynamic it) {
    try {
      final v = (it as dynamic).qty;
      if (v is num) return v.toInt();
    } catch (_) {}
    try {
      final v = (it as dynamic).quantity;
      if (v is num) return v.toInt();
    } catch (_) {}
    if (it is Map && it.containsKey('qty')) return _i(it['qty']);
    if (it is Map && it.containsKey('quantity')) return _i(it['quantity']);
    return 0;
  }

  String _unitOf(dynamic it) {
    try {
      final v = (it as dynamic).unit;
      if (_s(v) != null) return _s(v)!;
    } catch (_) {}
    if (it is Map && _s(it['unit']) != null) return _s(it['unit'])!;
    return '';
  }

  int _unitPriceOf(dynamic it) {
    try {
      final v = (it as dynamic).unitPrice;
      if (v is num) return v.toInt();
    } catch (_) {}
    if (it is Map && it.containsKey('unit_price')) return _i(it['unit_price']);
    if (it is Map && it.containsKey('price')) return _i(it['price']);
    return 0;
  }

  int _lineTotalOf(dynamic it) {
    try {
      final v = (it as dynamic).lineTotal;
      if (v is num) return v.toInt();
    } catch (_) {}
    if (it is Map && it.containsKey('line_total')) return _i(it['line_total']);
    if (it is Map && it.containsKey('subtotal')) return _i(it['subtotal']);
    if (it is Map && it.containsKey('total')) return _i(it['total']);
    // fallback
    final q = _qtyOf(it);
    final p = _unitPriceOf(it);
    return q * p;
  }

  Widget _itemTile(dynamic it, String Function(int) idr) {
    final name = _nameOf(it);
    final image = _imageOf(it);
    final qty = _qtyOf(it);
    final unit = _unitOf(it);
    final lineTotal = _lineTotalOf(it);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      leading: image != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(image, width: 52, height: 52, fit: BoxFit.cover),
            )
          : CircleAvatar(
              backgroundColor: Colors.grey.shade200,
              child: const Icon(Icons.image, color: Colors.black54),
            ),
      title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text('x$qty ${unit}'.trim()),
      trailing: Text(idr(lineTotal)),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final int subtotal, shipping, insurance, discount, total;
  const _SummaryCard({
    required this.subtotal,
    required this.shipping,
    required this.insurance,
    required this.discount,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    Row row(String l, String r, {bool bold = false}) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(l,
                style:
                    bold ? const TextStyle(fontWeight: FontWeight.w600) : null),
            Text(r,
                style:
                    bold ? const TextStyle(fontWeight: FontWeight.w600) : null),
          ],
        );

    String idr(int v) =>
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0)
            .format(v);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            row('Total Harga', idr(subtotal)),
            const SizedBox(height: 6),
            row('Ongkos Kirim', idr(shipping)),
            const SizedBox(height: 6),
            row('Asuransi Pengiriman', idr(insurance)),
            const Divider(height: 20),
            row('Diskon', '-${idr(discount)}'),
            const SizedBox(height: 12),
            row('Total Tagihan', idr(total), bold: true),
          ],
        ),
      ),
    );
  }
}

/* ============================================================
   Midtrans WebView + polling status order (BARU)
   ============================================================ */
class MidtransWebViewPage extends StatefulWidget {
  final String redirectUrl;
  final int orderId;
  const MidtransWebViewPage(
      {super.key, required this.redirectUrl, required this.orderId});

  @override
  State<MidtransWebViewPage> createState() => _MidtransWebViewPageState();
}

class _MidtransWebViewPageState extends State<MidtransWebViewPage> {
  late final WebViewController _controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(widget.redirectUrl));

    // polling status setiap 3 detik (atau gunakan deep-link finish jika tersedia)
    _timer = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final data =
            await context.read<CheckoutProvider>().fetchOrder(widget.orderId);
        final status = data['status']?.toString() ?? '';
        if (status == 'paid' || status == 'processing') {
          _timer?.cancel();
          if (!mounted) return;
          Navigator.pop(context); // tutup WebView
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pembayaran berhasil.')),
          );
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pembayaran')),
      body: WebViewWidget(controller: _controller),
    );
  }
}

/* ============================================================
   IMBUHAN: BuyerCheckoutScreen (UI modern & ringkas)
   ============================================================ */

// === Top-level helper: normalisasi dynamic -> Map<String, dynamic>
// (dipakai BuyerCheckoutScreen & juga handler di atas)
Map<String, dynamic> _asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return <String, dynamic>{};
}

// ===== JSON helpers aman =====
Map<String, dynamic> _jsonMap(dynamic raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (raw is String && raw.trim().isNotEmpty) {
    try {
      final d = jsonDecode(raw);
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (_) {}
  }
  return <String, dynamic>{};
}

List<dynamic> _jsonList(dynamic raw) {
  if (raw is List) return List<dynamic>.from(raw);
  if (raw is String && raw.trim().isNotEmpty) {
    try {
      final d = jsonDecode(raw);
      if (d is List) return List<dynamic>.from(d);
    } catch (_) {}
  }
  return const [];
}

// === Helper aman baca flag "selected" dari row keranjang ===
bool _isCartRowSelected(dynamic it) {
  // properti .selected
  try {
    final v = (it as dynamic).selected;
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v == '1' || v.toLowerCase() == 'true';
  } catch (_) {}

  // key 'selected' pada Map
  try {
    if (it is Map) {
      final v = it['selected'];
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) return v == '1' || v.toLowerCase() == 'true';
    }
  } catch (_) {}

  return false;
}

// === Helper CartItemModel <-> Map (tahan banting) ===
int _extractCartItemId(dynamic it) {
  if (it is Map) {
    final raw = it['id'] ?? it['cart_item_id'] ?? it['cartItemId'] ?? 0;
    return raw is int ? raw : int.tryParse('$raw') ?? 0;
  }
  try {
    final v = (it as CartItemModel).id;
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
  try {
    final v = (it as dynamic).id;
    if (v is int) return v;
  } catch (_) {}
  return 0;
}

Map<String, dynamic> _cartItemToMap(dynamic it) {
  if (it is Map) return _asMap(it);
  final out = <String, dynamic>{};
  try {
    out['id'] = (it as dynamic).id;
  } catch (_) {}
  try {
    out['product_id'] = (it as dynamic).productId;
  } catch (_) {}
  try {
    out['name'] = (it as dynamic).name ?? (it as dynamic).productName;
  } catch (_) {}
  try {
    out['image_url'] =
        (it as dynamic).imageUrl ?? (it as dynamic).image;
  } catch (_) {}
  try {
    out['qty'] = (it as dynamic).qty ?? (it as dynamic).quantity ?? 1;
  } catch (_) {}
  try {
    out['unit_price'] =
        (it as dynamic).unitPrice ?? (it as dynamic).price ?? 0;
  } catch (_) {}
  try {
    out['line_total'] = (it as dynamic).lineTotal;
  } catch (_) {}
  final q = (out['qty'] ?? 1) as num;
  final p = (out['unit_price'] ?? out['price'] ?? 0) as num;
  out['line_total'] = (out['line_total'] ?? (q * p)).toInt();
  return out;
}

// Helper aman untuk “memastikan Map” dari item campuran
Map<String, dynamic> _ensureMapCartItem(dynamic obj) {
  if (obj is Map<String, dynamic>) return obj;
  if (obj is Map) return _asMap(obj);
  return _cartItemToMap(obj);
}

/// ================== REPLACE BuyerCheckoutScreen (FULL) ==================
class BuyerCheckoutScreen extends StatefulWidget {
  const BuyerCheckoutScreen({super.key});
  @override
  State<BuyerCheckoutScreen> createState() => _BuyerCheckoutScreenState();
}

class _BuyerCheckoutScreenState extends State<BuyerCheckoutScreen> {
  // ====== Pembayaran ======
  String _method = 'midtrans'; // 'midtrans' | 'transfer_manual' | 'cod'
  String _channel = 'qris'; // 'qris' | 'bca_va' | 'gopay' | 'cc'
  final _notes = TextEditingController();

  // ====== Alamat & lokasi ======
  final _address = TextEditingController();
  String? _formatted;
  double? _lat, _lng;
  bool _locLoading = false, _geocodeLoading = false;
  final MapController _mapCtl = MapController();

  // ====== Preview server ======
  Map<String, dynamic>? _preview;

  // Fallback pusat (Jakarta)
  static const double _fallbackLat = -6.200000;
  static const double _fallbackLng = 106.816666;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final cp = context.read<CheckoutProvider>() as dynamic;
        final a = cp.shippingAddress;
        if (a is Map && a['latitude'] != null && a['longitude'] != null) {
          _lat = (a['latitude'] as num).toDouble();
          _lng = (a['longitude'] as num).toDouble();
          _formatted = (a['address'] as String?)?.trim();
          if (_formatted?.isNotEmpty == true) _address.text = _formatted!;
        }
      } catch (_) {}
      await _reloadPreview();
    });
  }

  @override
  void dispose() {
    _notes.dispose();
    _address.dispose();
    super.dispose();
  }

  // ======================= DATA / PREVIEW =======================
  // 🔧 FIX #1: pakai _jsonMap (string-safe) + kirim cart_item_ids + include_items
  Future<void> _reloadPreview() async {
    try {
      final Dio dio = API.dio;
      // Kumpulkan IDs dari keranjang
      final cart = context.read<CartProvider>();
      List<int> ids = cart.selectedIds
          .map((e) => int.tryParse('$e') ?? 0)
          .where((e) => e > 0)
          .toList();
      if (ids.isEmpty) {
        try {
          ids = cart.items
              .where(_isCartRowSelected)
              .map((it) => _extractCartItemId(it))
              .where((e) => e > 0)
              .toList();
        } catch (_) {}
      }

      final payload = <String, dynamic>{
        'address_text':
            _address.text.trim().isEmpty ? null : _address.text.trim(),
        'lat': _lat ?? _fallbackLat,
        'lng': _lng ?? _fallbackLng,
        'include_items': true, // ⬅️ penting
      };
      if (ids.isNotEmpty) payload['cart_item_ids'] = ids; // ⬅️ penting

      final resp = await dio.post('buyer/checkout/preview', data: payload);

      // gunakan helper string-safe
      final Map<String, dynamic> data = _jsonMap(resp.data);
      setState(() {
        final Map<String, dynamic> dd = _jsonMap(data['data']);
        _preview = dd.isNotEmpty ? dd : data;
      });
    } catch (e) {
      debugPrint('[checkout preview] $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal memuat ringkasan.')),
        );
      }
    }
  }

  // ============ Lokasi / Reverse Geocode ============
  Future<bool> _ensureLocationPermission() async {
    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied ||
        p == LocationPermission.deniedForever) {
      p = await Geolocator.requestPermission();
    }
    return p != LocationPermission.denied &&
        p != LocationPermission.deniedForever;
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _locLoading = true);
    try {
      final ok = await _ensureLocationPermission();
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('Izin lokasi ditolak. Aktifkan di Pengaturan.')),
          );
        }
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Aktifkan layanan lokasi di perangkat.')),
          );
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      _lat = pos.latitude;
      _lng = pos.longitude;
      _mapCtl.move(latlng.LatLng(_lat!, _lng!), 16);

      await _reverseGeocodeOSM(_lat!, _lng!);
      await _reloadPreview();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal ambil lokasi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _locLoading = false);
    }
  }

  Future<void> _reverseGeocodeOSM(double lat, double lng) async {
    setState(() => _geocodeLoading = true);
    try {
      final uri =
          Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': '$lat',
        'lon': '$lng',
        'addressdetails': '1',
        'accept-language': 'id',
        'zoom': '18',
      });
      final resp = await http.get(uri, headers: {
        'User-Agent': 'e-buyur/1.0 (support@yourdomain.com)',
      });
      if (resp.statusCode == 200) {
        final m = jsonDecode(resp.body) as Map<String, dynamic>;
        final displayName = (m['display_name'] as String?)?.trim();
        final addr = m['address'] as Map<String, dynamic>?;
        _formatted = displayName ?? _buildAddressFromNominatim(addr);
        if (_formatted?.isNotEmpty == true) _address.text = _formatted!;
      }
    } catch (_) {
      _formatted =
          '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
      _address.text = _formatted!;
    } finally {
      if (mounted) setState(() => _geocodeLoading = false);
    }
  }

  String? _buildAddressFromNominatim(Map<String, dynamic>? a) {
    if (a == null) return null;
    String pick(String k) => (a[k] as String? ?? '').trim();
    final parts = <String>[
      pick('road'),
      pick('neighbourhood').isNotEmpty
          ? pick('neighbourhood')
          : pick('suburb'),
      pick('village').isNotEmpty ? pick('village') : pick('town'),
      pick('city_district'),
      pick('city'),
      pick('state'),
      pick('postcode'),
      pick('country'),
    ].where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(', ');
  }

  Future<void> _openMapPicker() async {
    final result = await Navigator.of(context).push<MapPickResult>(
      MaterialPageRoute(builder: (_) => const MapPickPage()),
    );
    if (result != null) {
      _lat = result.lat;
      _lng = result.lng;
      if (result.address?.isNotEmpty == true) {
        _formatted = result.address;
        _address.text = result.address!;
      }
      _mapCtl.move(latlng.LatLng(_lat!, _lng!), 16);
      await _reloadPreview();
    }
  }

  Future<void> _saveAddress() async {
    final text = _address.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Isi alamat terlebih dahulu.')),
      );
      return;
    }
    try {
      final prov = context.read<CheckoutProvider>();
      Map<String, dynamic>? saved;
      try {
        saved = await (prov as dynamic).saveAddress(
          formattedAddress: text,
          latitude: _lat,
          longitude: _lng,
          setDefault: true,
        );
      } catch (_) {
        try {
          (prov as dynamic).setAddressLocal(
            formattedAddress: text, latitude: _lat, longitude: _lng,
          );
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(saved == null
                  ? 'Alamat dipakai untuk pesanan ini.'
                  : 'Alamat tersimpan.')),
        );
      }
      await _reloadPreview();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal simpan alamat: $e')),
        );
      }
    }
  }

  // ======================= UI HELPERS =======================
  String _fmt(num v) => NumberFormat.currency(
          locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0)
      .format(v);

  int _subtotalFromCart() {
    try {
      final cart = context.read<CartProvider>();
      try {
        final ss = (cart as dynamic).selectedSubtotal;
        if (ss is num && ss > 0) return ss.toInt();
      } catch (_) {}
      int sum = 0;
      for (final obj in cart.items) {
        if (obj is Map) {
          final m = Map<String, dynamic>.from(obj as Map);
          final qty = (m['qty'] ?? m['quantity'] ?? 1) as num;
          final price = (m['price'] ?? m['unit_price'] ?? 0) as num;
          final line = (m['line_total'] ?? m['subtotal']) as num?;
          sum += (line ?? (qty * price)).toInt();
        } else {
          try {
            final q =
                (obj as dynamic).qty ?? (obj as dynamic).quantity ?? 1;
            final p =
                (obj as dynamic).price ?? (obj as dynamic).unitPrice ?? 0;
            sum += ((q as num) * (p as num)).toInt();
          } catch (_) {}
        }
      }
      return sum;
    } catch (_) {
      return 0;
    }
  }

  // ======================= BUILD =======================
  @override
  Widget build(BuildContext context) {
    final int subtotal = (() {
      final v = _preview?['subtotal'];
      final x = v is num ? v.toInt() : int.tryParse('$v') ?? 0;
      return x > 0 ? x : _subtotalFromCart();
    })();

    final int shipping = (() {
      final v =
          _preview?['shipping_fee'] ?? _preview?['ongkir'];
      return v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    })();

    final int discount = (() {
      final v = _preview?['discount_total'] ??
          _preview?['discount'] ??
          _preview?['diskon'];
      return v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    })();

    final int grand = (() {
      final v = _preview?['grand_total'] ?? _preview?['total'];
      final g = v is num ? v.toInt() : int.tryParse('$v') ?? 0;
      return g > 0 ? g : (subtotal + shipping - discount);
    })();

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: RefreshIndicator(
        onRefresh: () async => _reloadPreview(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ===== Alamat & Peta =====
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Expanded(
                          child: Text('Alamat & Catatan',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        TextButton.icon(
                          onPressed: _openMapPicker,
                          icon: const Icon(Icons.map_outlined),
                          label: const Text('Pilih di Peta'),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 180,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: FlutterMap(
                            mapController: _mapCtl,
                            options: MapOptions(
                              initialCenter: latlng.LatLng(
                                _lat ?? _fallbackLat,
                                _lng ?? _fallbackLng,
                              ),
                              initialZoom: 14,
                              onTap: (_, p) async {
                                _lat = p.latitude;
                                _lng = p.longitude;
                                await _reverseGeocodeOSM(_lat!, _lng!);
                                await _reloadPreview();
                              },
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName:
                                    'com.yourcompany.ebuyur',
                              ),
                              if (_lat != null && _lng != null)
                                MarkerLayer(markers: [
                                  Marker(
                                    point: latlng.LatLng(_lat!, _lng!),
                                    width: 40,
                                    height: 40,
                                    child: const Icon(Icons.location_pin,
                                        size: 40, color: Colors.red),
                                  )
                                ]),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        ElevatedButton.icon(
                          onPressed:
                              _locLoading ? null : _useCurrentLocation,
                          icon: _locLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.my_location),
                          label: const Text('Lokasi Saya'),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _address,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Alamat pengiriman',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => _reloadPreview(),
                      ),
                      if ((_formatted ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(children: [
                          const Icon(Icons.place_outlined, size: 18),
                          const SizedBox(width: 6),
                          Expanded(child: Text(_formatted!, style: const TextStyle(height: 1.4))),
                        ]),
                      ],
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _saveAddress,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Simpan Alamat'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _notes,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText:
                              'Catatan untuk penjual (opsional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ===== Ringkasan Item =====
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Ringkasan Item',
                          style:
                              TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Builder(builder: (_) {
                        // Ambil dari preview (jika ada)
                        final rawList =
                            (_preview?['items'] as List?) ?? const [];
                        if (rawList.isNotEmpty) {
                          final List<Map<String, dynamic>> items =
                              rawList
                                  .map<Map<String, dynamic>>(
                                      (obj) => _ensureMapCartItem(obj))
                                  .toList();

                          return Column(
                            children: items.map((m) {
                              final qty = (m['qty'] ??
                                  m['quantity'] ??
                                  1) as num;
                              final line = (m['line_total'] ??
                                  m['subtotal'] ??
                                  0) as num;
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: _thumb(m['image_url']?.toString() ??
                                    m['imageUrl']?.toString()),
                                title: Text(
                                    m['name']?.toString() ??
                                        m['product_name']?.toString() ??
                                        '-',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text('x${qty.toInt()}'),
                                trailing: Text(_fmt(line)),
                              );
                            }).toList(),
                          );
                        }

                        // Fallback dari CartProvider
                        final cart = context.read<CartProvider>();
                        if (cart.items.isEmpty) {
                          return const Text('Tidak ada item.');
                        }
                        final List<Map<String, dynamic>> items2 =
                            cart.items
                                .map<Map<String, dynamic>>(
                                    (obj) => _ensureMapCartItem(obj))
                                .toList();

                        return Column(
                          children: items2.map((m) {
                            final qty = (m['qty'] ??
                                m['quantity'] ??
                                1) as num;
                            final line = (m['line_total'] ??
                                    m['subtotal'] ??
                                    (qty * (m['price'] ?? 0))) as num;
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: _thumb(m['image_url']?.toString() ??
                                  m['imageUrl']?.toString()),
                              title: Text(
                                  m['name']?.toString() ??
                                      m['product_name']?.toString() ??
                                      '-',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text('x${qty.toInt()}'),
                              trailing: Text(_fmt(line)),
                            );
                          }).toList(),
                        );
                      }),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ===== Metode Pembayaran =====
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Metode Pembayaran',
                          style:
                              TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, children: [
                        _mChip('Midtrans', 'midtrans', _method),
                        _mChip('Transfer', 'transfer_manual', _method),
                        _mChip('COD', 'cod', _method),
                      ]),
                      const SizedBox(height: 12),
                      if (_method == 'midtrans') ...[
                        const Text('Channel Midtrans',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, children: [
                          _cChip('QRIS', 'qris', _channel),
                          _cChip('BCA VA', 'bca_va', _channel),
                          _cChip('GoPay', 'gopay', _channel),
                          _cChip('Kartu', 'cc', _channel),
                        ]),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ===== Total =====
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      _row('Subtotal', _fmt(subtotal)),
                      _row('Ongkir', _fmt(shipping)),
                      _row('Diskon', _fmt(discount)),
                      const Divider(),
                      _row('Grand Total', _fmt(grand), bold: true),
                    ],
                  ),
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
              onPressed: _onPayNow,
              child: Text('Bayar Sekarang (${_fmt(grand)})'),
            ),
          ),
        ),
      ),
    );
  }

  // ======================= ACTION: BAYAR =======================
  Future<void> _onPayNow() async {
    try {
      final cart = context.read<CartProvider>();
      List<int> ids = cart.selectedIds
          .map((x) => int.tryParse('$x') ?? 0)
          .where((x) => x > 0)
          .toList();
      if (ids.isEmpty) {
        try {
          ids = cart.items
              .where(_isCartRowSelected)
              .map((it) => _extractCartItemId(it))
              .where((e) => e > 0)
              .toList();
        } catch (_) {}
      }
      if (ids.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pilih produk di Keranjang dulu.')));
        return;
      }

      final result =
          await context.read<CheckoutProvider>().createOrder(
                paymentMethod: _method,
                paymentChannel:
                    _method == 'midtrans' ? _channel : null,
                notes: _notes.text.trim().isEmpty
                    ? null
                    : _notes.text.trim(),
                address: {
                  'formatted': _address.text.trim().isEmpty
                      ? _formatted
                      : _address.text.trim(),
                  'lat': _lat ?? _fallbackLat,
                  'lng': _lng ?? _fallbackLng,
                },
                cartItemIds: ids, // ⬅️ wajib
              );

      // === NORMALISASI root/data sesuai patch
      final Map<String, dynamic> root = _asMap(result);
      final Map<String, dynamic> data = _asMap(root['data']);
      final Map<String, dynamic> res  = data.isNotEmpty ? data : root;

      // ⛔️ Guard error
      final bool isOk = (res['status'] == 'success') ||
          (res['success'] == true) ||
          res.containsKey('order_id') ||
          (res['order'] is Map);
      if (!isOk) {
        final msg = (res['message'] ?? res['error'] ?? 'Gagal membuat pesanan').toString();
        throw Exception(msg);
      }

      final Map<String, dynamic> payment = _asMap(res['payment']);
      final String? url = (res['redirect_url'] as String?) ??
          (res['payment_redirect_url'] as String?) ??
          (payment['redirect_url'] as String?);

      final dynamic orderIdAny =
          res['order_id'] ??
              (res['order'] is Map
                  ? (res['order'] as Map)['id']
                  : null);
      final int? orderId = orderIdAny is int
          ? orderIdAny
          : int.tryParse('$orderIdAny');

      if (_method == 'midtrans' &&
          url != null &&
          url.isNotEmpty &&
          orderId != null) {
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => MidtransWebViewPage(
                  redirectUrl: url, orderId: orderId)),
        );
      } else {
        if (!mounted) return;
        if (payment.isNotEmpty) {
          // ✅ panggil helper TOP-LEVEL agar tidak bentrok signature
          await _showPaymentInstructionsTopLevel(context, payment);
        } else {
          final fallback = {
            'bank': res['bank'] ?? res['bank_name'],
            'va_number': res['va_number'] ?? res['account_number'] ?? res['bill_key'],
            'qris_url': res['qris_url'] ?? res['qr_url'],
            'qr_string': res['qr_string'],
            'amount': res['amount'] ?? res['gross_amount'] ?? res['total'],
            'instructions': res['instructions'] ?? res['how_to'],
          };
          if (fallback.values.any((v) => v != null && '$v'.isNotEmpty)) {
            await _showPaymentInstructionsTopLevel(context, fallback);
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Pesanan dibuat. Lihat instruksi di detail pesanan.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuat pesanan: $e')));
    }
  }

  // ======================= WIDGET HELPERS =======================
  Widget _thumb(String? url) {
    const size = 56.0;
    Widget fallback() => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: const Color(0xFFEFEFEF),
              borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.image_not_supported),
        );
    if (url == null || url.isEmpty) return fallback();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback()),
    );
  }

  Widget _mChip(String label, String value, String selected) {
    final on = value == selected;
    return ChoiceChip(
        selected: on,
        label: Text(label),
        onSelected: (_) => setState(() => _method = value));
  }

  Widget _cChip(String label, String value, String selected) {
    final on = value == selected;
    return FilterChip(
        selected: on,
        label: Text(label),
        showCheckmark: false,
        onSelected: (_) => setState(() => _channel = value));
  }

  Widget _row(String label, String r, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style: bold
                      ? const TextStyle(fontWeight: FontWeight.bold)
                      : null)),
          Text(r, style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null),
        ]),
      );
}


/* ============================================================
   ========  V2: Versi Checkout minimal sesuai perbaikan  =====
   ============================================================ */

enum PaymentMethod { midtrans, transfer, cod }
enum MidtransChannel { qris, gopay, bca_va, bni_va, card }

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
        productId: j['product_id'] ?? j['id'] ?? 0,
        name: j['name'] ?? '-',
        imageUrl: (j['image_url'] ?? '').toString(),
        qty: (j['qty'] ?? j['quantity'] ?? 0) as int,
        unitPrice: (j['unit_price'] ?? j['price'] ?? 0) as int,
        lineTotal:
            (j['line_total'] ?? (j['qty'] ?? 0) * (j['unit_price'] ?? 0))
                as int,
      );
}

class CheckoutPreview {
  final List<CheckoutItem> items;
  final int subtotal;
  final int shippingFee;
  final double distanceKm;
  final int discountTotal;
  final int grandTotal;

  CheckoutPreview({
    required this.items,
    required this.subtotal,
    required this.shippingFee,
    required this.distanceKm,
    required this.discountTotal,
    required this.grandTotal,
  });

  factory CheckoutPreview.fromJson(Map<String, dynamic> j) =>
      CheckoutPreview(
        items: (_jsonList(j['items'].toString().isNotEmpty ? j['items'] : j['data']))
            .map((e) => CheckoutItem.fromJson(_asMap(e)))
            .toList(),
        subtotal: (j['subtotal'] ?? 0) is double
            ? (j['subtotal'] as double).toInt()
            : (j['subtotal'] ?? 0) as int,
        shippingFee: (j['shipping_fee'] ?? j['ongkir'] ?? 0) is double
            ? (j['shipping_fee'] as double).toInt()
            : (j['shipping_fee'] ?? j['ongkir'] ?? 0) as int,
        distanceKm: ((j['distance_km'] ?? 0) as num).toDouble(),
        discountTotal: (j['discount_total'] ?? j['diskon'] ?? 0) is double
            ? (j['discount_total'] as double).toInt()
            : (j['discount_total'] ?? j['diskon'] ?? 0) as int,
        grandTotal: (j['grand_total'] ?? j['total'] ?? 0) is double
            ? (j['grand_total'] as double).toInt()
            : (j['grand_total'] ?? j['total'] ?? 0) as int,
      );
}

class CheckoutV2Screen extends StatefulWidget {
  const CheckoutV2Screen({super.key});

  @override
  State<CheckoutV2Screen> createState() => _CheckoutV2ScreenState();
}

class _CheckoutV2ScreenState extends State<CheckoutV2Screen> {
  final TextEditingController _addressCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  PaymentMethod _method = PaymentMethod.midtrans;
  MidtransChannel _channel = MidtransChannel.qris;

  bool _loading = false;
  CheckoutPreview? _preview;

  double? _lat;
  double? _lng;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reloadPreview());
  }

  Future<void> _reloadPreview() async {
    try {
      final Dio dio = API.dio;

      // Kumpulkan IDs dari keranjang
      final cart = context.read<CartProvider>();
      List<int> ids = cart.selectedIds
          .map((e) => int.tryParse('$e') ?? 0)
          .where((e) => e > 0)
          .toList();
      if (ids.isEmpty) {
        try {
          ids = cart.items
              .where(_isCartRowSelected)
              .map((it) => _extractCartItemId(it))
              .where((e) => e > 0)
              .toList();
        } catch (_) {}
      }

      final payload = <String, dynamic>{
        'address_text': _addressCtrl.text.trim().isEmpty
            ? null
            : _addressCtrl.text.trim(),
        'lat': _lat,
        'lng': _lng,
        'include_items': true, // ⬅️ WAJIB
      };
      if (ids.isNotEmpty) payload['cart_item_ids'] = ids; // ⬅️ WAJIB

      final resp = await dio.post('buyer/checkout/preview', data: payload);

      // Normalisasi payload (string-safe)
      final Map<String, dynamic> data = _jsonMap(resp.data);

      setState(() {
        final dd = _jsonMap(data['data']);
        _preview = CheckoutPreview.fromJson(dd.isNotEmpty ? dd : data);
      });
    } catch (e) {
      debugPrint('[checkout preview] $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal memuat ringkasan.')),
        );
      }
    }
  }

  Future<void> _openMapPicker() async {
    final result = await Navigator.of(context).push<MapPickResult>(
      MaterialPageRoute(builder: (_) => const MapPickPage()),
    );
    if (result != null) {
      setState(() {
        _lat = result.lat;
        _lng = result.lng;
        if (result.address?.isNotEmpty == true) {
          _addressCtrl.text = result.address!;
        }
      });
      await _reloadPreview();
    }
  }

  Future<void> _payNow() async {
    if (_preview == null) {
      await _reloadPreview();
      if (_preview == null) return;
    }
    setState(() => _loading = true);
    try {
      final Dio dio = API.dio;
      final payload = {
        'payment_method': _method.name, // 'midtrans'|'transfer'|'cod'
        'payment_channel': _method == PaymentMethod.midtrans
            ? foundation.describeEnum(_channel) // qris|gopay|bca_va|bni_va|card
            : null,
        'address_text': _addressCtrl.text,
        'lat': _lat,
        'lng': _lng,
        'note': _noteCtrl.text,
      };
      final resp = await dio.post('buyer/checkout', data: payload);

      // String-safe + normalisasi root/data
      final Map<String, dynamic> root = _jsonMap(resp.data);
      final Map<String, dynamic> data = _jsonMap(root['data']);
      final Map<String, dynamic> res  = data.isNotEmpty ? data : root;
      final Map<String, dynamic> payment = _jsonMap(res['payment']);

      // ⛔️ Guard error
      final bool isOk = (res['status'] == 'success') ||
          (res['success'] == true) ||
          res.containsKey('order_id') ||
          (res['order'] is Map);
      if (!isOk) {
        final msg = (res['message'] ?? res['error'] ?? 'Gagal membuat pesanan').toString();
        throw Exception(msg);
      }

      final String? redirectUrl = (res['redirect_url'] as String?) ??
          (res['payment_redirect_url'] as String?) ??
          (payment['redirect_url'] as String?);
      final dynamic orderIdAny =
          res['order_id'] ?? res['id'] ?? res['order']?['id'];
      final int? orderId = orderIdAny is int ? orderIdAny : int.tryParse('$orderIdAny');

      if (_method == PaymentMethod.midtrans &&
          redirectUrl != null &&
          redirectUrl.isNotEmpty &&
          orderId != null) {
        if (context.mounted) {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => MidtransWebViewPage(
              redirectUrl: redirectUrl,
              orderId: orderId,
            ),
          ));
        }
      } else {
        if (context.mounted) {
          if (payment.isNotEmpty) {
            await _showPaymentInstructionsTopLevel(context, payment);
          } else {
            final fallback = {
              'bank': res['bank'] ?? res['bank_name'],
              'va_number': res['va_number'] ?? res['account_number'] ?? res['bill_key'],
              'qris_url': res['qris_url'] ?? res['qr_url'],
              'qr_string': res['qr_string'],
              'amount': res['amount'] ?? res['gross_amount'] ?? res['total'],
              'instructions': res['instructions'] ?? res['how_to'],
            };
            if (fallback.values.any((v) => v != null && '$v'.isNotEmpty)) {
              await _showPaymentInstructionsTopLevel(context, fallback);
            }
          }

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pesanan dibuat. Lihat instruksi di detail pesanan.')),
          );
        }
      }
    } catch (e) {
      debugPrint('[checkout create] $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuat pesanan: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildPaymentSelector() {
    return Column(
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
              selected: _method == PaymentMethod.midtrans,
              onSelected: (_) =>
                  setState(() => _method = PaymentMethod.midtrans),
            ),
            ChoiceChip(
              label: const Text('Transfer'),
              selected: _method == PaymentMethod.transfer,
              onSelected: (_) =>
                  setState(() => _method = PaymentMethod.transfer),
            ),
            ChoiceChip(
              label: const Text('COD'),
              selected: _method == PaymentMethod.cod,
              onSelected: (_) =>
                  setState(() => _method = PaymentMethod.cod),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_method == PaymentMethod.midtrans) ...[
          const Text('Channel Midtrans'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                label: const Text('QRIS'),
                selected: _channel == MidtransChannel.qris,
                onSelected: (_) =>
                    setState(() => _channel = MidtransChannel.qris),
              ),
              FilterChip(
                label: const Text('BCA VA'),
                selected: _channel == MidtransChannel.bca_va,
                onSelected: (_) =>
                    setState(() => _channel = MidtransChannel.bca_va),
              ),
              FilterChip(
                label: const Text('GoPay'),
                selected: _channel == MidtransChannel.gopay,
                onSelected: (_) =>
                    setState(() => _channel = MidtransChannel.gopay),
              ),
              FilterChip(
                label: const Text('Kartu'),
                selected: _channel == MidtransChannel.card,
                onSelected: (_) =>
                    setState(() => _channel = MidtransChannel.card),
              ),
              FilterChip(
                label: const Text('BNI VA'),
                selected: _channel == MidtransChannel.bni_va,
                onSelected: (_) =>
                    setState(() => _channel = MidtransChannel.bni_va),
              ),
            ],
          ),
        ]
      ],
    );
  }

  Widget _buildItems() {
    final items = _preview?.items ?? const <CheckoutItem>[];
    if (items.isEmpty) {
      return const Text('Belum ada item di keranjang.');
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final it = items[i];
        return ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(it.imageUrl, width: 56, height: 56,
                fit: BoxFit.cover, errorBuilder: (_, __, ___) {
              return Container(
                  width: 56,
                  height: 56,
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.image));
            }),
          ),
          title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('x${it.qty} • Rp ${it.unitPrice}'),
          trailing: Text('Rp ${it.lineTotal}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
        );
      },
    );
  }

  Widget _buildTotals() {
    final s = _preview;
    final subtotal = s?.subtotal ?? 0;
    final ship = s?.shippingFee ?? 0;
    final disc = s?.discountTotal ?? 0;
    final gt = s?.grandTotal ?? 0;
    final dist = s?.distanceKm ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row('Subtotal', subtotal),
        _row('Ongkir ${dist > 0 ? "(${dist.toStringAsFixed(1)} km)" : ""}',
            ship),
        _row('Diskon', -disc),
        const Divider(),
        _row('Grand Total', gt, bold: true),
      ],
    );
  }

  Widget _row(String label, int nominal, {bool bold = false}) {
    final style = TextStyle(
        fontSize: 15, fontWeight: bold ? FontWeight.w800 : FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text('Rp $nominal', style: style),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gt = _preview?.grandTotal ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: RefreshIndicator(
        onRefresh: () async => _reloadPreview(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                              child: Text('Alamat & Catatan',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700))),
                          TextButton.icon(
                            onPressed: _openMapPicker,
                            icon: const Icon(Icons.map_outlined),
                            label: const Text('Pilih di Peta'),
                          )
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _addressCtrl, // (C) benar
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText: 'Alamat pengiriman...',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => _reloadPreview(),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _noteCtrl, // (C) benar
                        maxLines: 2,
                        decoration: const InputDecoration(
                          hintText:
                              'Catatan untuk penjual (opsional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Ringkasan Item',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      _buildItems(), // (C) pakai builder V2
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _buildPaymentSelector(),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _buildTotals(),
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
              onPressed: _loading ? null : _payNow,
              child:
                  Text(_loading ? 'Memproses...' : 'Bayar Sekarang (Rp $gt)'),
            ),
          ),
        ),
      ),
    );
  }
}

/// Top-level helper agar bisa dipakai juga oleh BuyerCheckoutScreen.
/// (Dinamai ulang supaya tidak tabrakan dengan method di class lain)
Future<void> _showPaymentInstructionsTopLevel(
    BuildContext context, Map<String, dynamic> payment) async {
  final title = (payment['channel'] ??
          payment['method_name'] ??
          'Instruksi Pembayaran')
      .toString();
  final va = (payment['va_number'] ??
          payment['va'] ??
          payment['account_number'] ??
          '')
      .toString();
  final qr =
      (payment['qr_string'] ?? payment['qris'] ?? payment['qr_url'] ?? '')
          .toString();
  final bank = (payment['bank'] ?? payment['bank_name'] ?? '').toString();
  final amount =
      payment['amount'] ?? payment['gross_amount'] ?? payment['total'];

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (bank.isNotEmpty) Text('Bank: $bank'),
            if (va.isNotEmpty) SelectableText('No. VA: $va'),
            if (qr.isNotEmpty) SelectableText('QR: $qr'),
            if (amount != null) Text('Nominal: Rp $amount'),
            const SizedBox(height: 12),
            const Text(
                'Setelah bayar, tekan tombol "Saya sudah bayar" di detail pesanan untuk refresh status.'),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ),
          ],
        ),
      );
    },
  );
}
