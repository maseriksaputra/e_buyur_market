// Path: lib/app/presentation/providers/checkout_provider.dart
//
// Versi minimal-kompatibel untuk dipakai oleh screen checkout.
// Aman digabung dengan kode lama: properti dan nama metode BARU tidak
// menimpa milikmu. Jika project lain masih mengakses `preview`, di sini
// disediakan getter yang mengembalikan `previewMap`.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import '../../core/network/api.dart'; // API.dio

class CheckoutProvider with ChangeNotifier {
  CheckoutProvider({Dio? dio}) : _dio = dio ?? API.dio;
  final Dio _dio;

  /// Flag pemuatan umum untuk operasi createOrder/loadPreview, dsb.
  bool loading = false;

  /// Flag khusus saat menyimpan alamat.
  bool isSavingAddress = false;

  /// Payload preview versi Map agar tidak bentrok dengan tipe/model lokal.
  /// - Struktur tipikal: {
  ///     items: [...],
  ///     courier_options: [...],
  ///     subtotal: int,
  ///     shipping_fee: int,
  ///     discount_total: int,
  ///     grand_total: int,
  ///     selected_courier: {...}
  ///   }
  Map<String, dynamic>? previewMap;

  /// Getter kompatibilitas (beberapa screen lama pakai `cp.preview`)
  Map<String, dynamic>? get preview => previewMap;

  /// Temp address yang diset lokal (tanpa commit ke server)
  Map<String, dynamic>? _tempAddress;

  // =========================================================
  // Alamat
  // =========================================================

  /// Simpan alamat pengiriman ke server (bila backend mendukung).
  /// Mengembalikan data alamat yang disimpan (bila ada), atau null jika
  /// endpoint tidak tersedia/diabaikan.
  Future<Map<String, dynamic>?> saveAddress({
    required String token,
    double? latitude,
    double? longitude,
    required String formattedAddress,
    bool setDefault = false,
  }) async {
    isSavingAddress = true;
    notifyListeners();
    try {
      // Coba beberapa endpoint umum — silakan sesuaikan dengan backend kamu.
      final candidates = <String>[
        '/buyer/addresses',
        '/buyer/address',
        '/addresses',
      ];
      for (final p in candidates) {
        try {
          final res = await _dio.post(
            p,
            data: {
              'address': formattedAddress,
              'latitude': latitude,
              'longitude': longitude,
              'is_default': setDefault,
            },
            options: Options(headers: {'Authorization': 'Bearer $token'}),
          );
          if (res.statusCode != null && res.statusCode! ~/ 100 == 2) {
            final data = _asMap(res.data);
            return data['data'] is Map
                ? Map<String, dynamic>.from(data['data'])
                : data;
          }
        } catch (_) {
          // coba endpoint berikutnya
        }
      }
      return null;
    } finally {
      isSavingAddress = false;
      notifyListeners();
    }
  }

  /// Set alamat lokal (untuk 1 transaksi saja) tanpa simpan permanen.
  void setAddressLocal({
    double? latitude,
    double? longitude,
    String? formattedAddress,
  }) {
    _tempAddress = {
      'latitude': latitude,
      'longitude': longitude,
      'address': formattedAddress,
    };
    notifyListeners();
  }

  Map<String, dynamic>? get tempAddress => _tempAddress;

  // =========================================================
  // Preview
  // =========================================================

  /// Ambil ringkasan checkout dari server (items, ongkir, total, dst).
  /// Gunakan saat alamat/pin/kurir berubah.
  Future<void> loadPreview({
    String? addressText,
    double? lat,
    double? lng,
    // Opsi tambahan jika mau lock kurir dari client:
    String? shippingCourierCode,
    String? shippingServiceCode,
    bool? useInsurance,
    List<int>? cartItemIds,
  }) async {
    loading = true;
    notifyListeners();
    try {
      final res = await _dio.post('buyer/checkout/preview', data: {
        if (addressText != null && addressText.isNotEmpty)
          'address_text': addressText,
        'lat': lat,
        'lng': lng,
        if (shippingCourierCode != null && shippingCourierCode.isNotEmpty)
          'shipping_courier_code': shippingCourierCode,
        if (shippingServiceCode != null && shippingServiceCode.isNotEmpty)
          'shipping_service_code': shippingServiceCode,
        if (useInsurance != null) 'use_insurance': useInsurance,
        if (cartItemIds != null && cartItemIds.isNotEmpty)
          'cart_item_ids': cartItemIds,
      });

      final data = _asMap(res.data);
      previewMap = data['data'] is Map
          ? Map<String, dynamic>.from(data['data'])
          : data;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // =========================================================
  // Create Order / Pay
  // =========================================================

  /// Buat pesanan dan inisiasi pembayaran.
  ///
  /// - paymentMethod: 'midtrans' | 'transfer_manual' | 'cod'
  /// - paymentChannel (opsional, untuk midtrans): 'qris' | 'gopay' | 'bca_va' | 'cc' | ...
  /// - address: { lat, lng, formatted }, atau struktur lain sesuai backend
  /// - cartItemIds: [id1, id2, ...] untuk memastikan yang dihitung
  /// - shipping* (opsional) untuk mengunci tarif kurir pilihan user
  Future<Map<String, dynamic>> createOrder({
    required String paymentMethod,
    String? paymentChannel,
    String? notes,
    Map<String, dynamic>? address,
    List<int>? cartItemIds,
    // opsional kurir
    String? shippingCourierCode,
    String? shippingCourierCompany,
    String? shippingServiceCode,
    String? shippingServiceName,
    String? shippingEtd,
    int? shippingCost,
  }) async {
    loading = true;
    notifyListeners();
    try {
      final payload = <String, dynamic>{
        'payment_method': paymentMethod,
        if (paymentChannel != null && paymentChannel.isNotEmpty)
          'payment_channel': paymentChannel,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        if (address != null) 'address': address,
        if (cartItemIds != null) 'cart_item_ids': cartItemIds,
        // Kurir (opsional)
        if (shippingCourierCode != null && shippingCourierCode.isNotEmpty)
          'shipping_courier_code': shippingCourierCode,
        if (shippingCourierCompany != null &&
            shippingCourierCompany.isNotEmpty)
          'shipping_courier_company': shippingCourierCompany,
        if (shippingServiceCode != null && shippingServiceCode.isNotEmpty)
          'shipping_service_code': shippingServiceCode,
        if (shippingServiceName != null && shippingServiceName.isNotEmpty)
          'shipping_service_name': shippingServiceName,
        if (shippingEtd != null && shippingEtd.isNotEmpty)
          'shipping_etd': shippingEtd,
        if (shippingCost != null) 'shipping_cost': shippingCost,
      };

      final res = await _dio.post('buyer/checkout', data: payload);
      return _asMap(res.data);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // =========================================================
  // Fetch Order (untuk polling status di WebView)
  // =========================================================

  /// Ambil detail order (dan status) berdasarkan ID.
  /// Mengembalikan map dengan minimal field `status`.
  Future<Map<String, dynamic>> fetchOrder(int id) async {
    final res = await _dio.get('buyer/orders/$id');
    final map = _asMap(res.data);

    // Normalisasi: jika payload punya objek 'order', flatten status agar konsisten.
    if (map['order'] is Map) {
      final ord = Map<String, dynamic>.from(map['order']);
      return {'status': ord['status'], 'order': ord, ...map};
    }
    return map;
  }

  // =========================================================
  // Utils
  // =========================================================

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    // beberapa backend membungkus di { data: ... }
    return {'data': data};
  }
}
