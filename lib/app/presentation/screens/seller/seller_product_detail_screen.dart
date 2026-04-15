import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../../core/theme/app_colors.dart' as theme;

/// Detail produk untuk SELLER
/// - Pakai data prefill dari arguments['product'] kalau ada (NO API CALL)
/// - Kalau tidak ada prefill, fetch ke /api/seller/products/:id, lalu fallback ke /api/products/:id
class SellerProductDetailScreen extends StatefulWidget {
  const SellerProductDetailScreen({Key? key}) : super(key: key);

  @override
  State<SellerProductDetailScreen> createState() => _SellerProductDetailScreenState();
}

class _SellerProductDetailScreenState extends State<SellerProductDetailScreen> {
  Map<String, dynamic>? _product;
  int? _id;
  bool _loading = true;
  String? _error;

  // ---- helpers ----
  String get _apiBase =>
      const String.fromEnvironment('API_BASE', defaultValue: 'https://api.ebuyurmarket.com');

  Map<String, String> _authHeaders(AuthProvider auth) {
    String? token;
    try { token = (auth as dynamic).token as String?; } catch (_) {}
    try { token ??= (auth as dynamic).accessToken as String?; } catch (_) {}
    try { token ??= (auth as dynamic).bearer as String?; } catch (_) {}
    return token != null && token!.isNotEmpty ? {'Authorization': 'Bearer $token'} : {};
  }

@override
void didChangeDependencies() {
  super.didChangeDependencies();
  if (_product != null || !_loading) return;

  final args = ModalRoute.of(context)?.settings.arguments;
  Map<String, dynamic>? prefill;
  if (args is Map) {
    _id = (args['id'] as num?)?.toInt();
    final p = args['product'];
    if (p is Map) prefill = Map<String, dynamic>.from(p);
  }

  if (prefill != null) {
    // ⬇️ PROMOSIKAN ke non-null dulu (di luar setState)
    final normalized = _normalize(prefill!);
    setState(() {
      _product = normalized;
      _loading = false;
      _error = null;
    });
  } else {
    _fetch();
  }
}


  Map<String, dynamic> _normalize(Map<String, dynamic> raw) {
    // Samakan key yang umum dipakai UI
    return {
      'id': raw['id'],
      'name': raw['name'] ?? raw['title'] ?? '-',
      'price': (raw['price'] is num) ? raw['price'] : num.tryParse('${raw['price']}') ?? 0,
      'stock': (raw['stock'] is num) ? raw['stock'] : num.tryParse('${raw['stock']}') ?? 0,
      'image_url': raw['image_url'] ?? raw['image'] ?? raw['thumbnail'],
      'category': raw['category'] ?? raw['category_slug'],
      'description': raw['description'],
      'freshness_score': raw['freshness_score'] ?? raw['suitability_percent'],
      'freshness_label': raw['freshness_label'],
      'nutrition': raw['nutrition'],
      'storage_tips': raw['storage_tips'],
    };
  }

  Future<void> _fetch() async {
    if (_id == null) {
      setState(() {
        _loading = false;
        _error = 'ID produk tidak ditemukan.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    final auth = context.read<AuthProvider>();
    final dio = Dio(BaseOptions(baseUrl: _apiBase, headers: _authHeaders(auth)));

    Future<Map<String, dynamic>> _hit(String path) async {
      final resp = await dio.get(path);
      if (resp.statusCode != null && resp.statusCode! >= 200 && resp.statusCode! < 300) {
        final data = resp.data is Map ? resp.data : json.decode(resp.data.toString());
        // Backend kita biasa bentuk {"data": {...}}
        final map = (data['data'] is Map) ? Map<String, dynamic>.from(data['data']) : Map<String, dynamic>.from(data);
        return _normalize(map);
      }
      throw DioException(
        requestOptions: RequestOptions(path: path),
        response: resp,
        type: DioExceptionType.badResponse,
      );
    }

    try {
      // Utama
      final m = await _hit('/api/seller/products/$_id');
      if (!mounted) return;
      setState(() {
        _product = m;
        _loading = false;
      });
    } on DioException catch (_) {
      // Fallback umum (non-seller) — supaya tidak mentok 500
      try {
        final m2 = await _hit('/api/products/$_id');
        if (!mounted) return;
        setState(() {
          _product = m2;
          _loading = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _error = 'Gagal memuat (detail).';
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Gagal memuat.';
        _loading = false;
      });
    }
  }

  String _rupiah(num n) {
    final s = n.toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final idx = s.length - i;
      buf.write(s[i]);
      if (idx > 1 && idx % 3 == 1) buf.write('.');
    }
    return 'Rp ${buf.toString()}';
  }

  @override
  Widget build(BuildContext context) {
    final primary = theme.AppColors.primaryGreen;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detail Produk (Penjual)')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detail Produk (Penjual)')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _fetch,
                child: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
      );
    }

    final p = _product!;
    return Scaffold(
      appBar: AppBar(title: const Text('Detail Produk (Penjual)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AspectRatio(
            aspectRatio: 1.6,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: (p['image_url'] != null && '${p['image_url']}'.isNotEmpty)
                  ? Image.network('${p['image_url']}', fit: BoxFit.cover)
                  : Container(color: Colors.grey[200], child: const Icon(Icons.photo, size: 48)),
            ),
          ),
          const SizedBox(height: 16),
          Text('${p['name']}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: primary.withOpacity(.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_rupiah((p['price'] ?? 0) as num),
                    style: TextStyle(fontSize: 16, color: primary, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              Chip(
                label: Text('Stok: ${p['stock'] ?? 0}'),
                backgroundColor: Colors.grey[100],
              ),
            ],
          ),
          if ((p['freshness_score'] ?? 0) != 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.eco, size: 18, color: Colors.green),
                const SizedBox(width: 6),
                Text('${p['freshness_label'] ?? 'Kelayakan'}: ${p['freshness_score']}%'),
              ],
            ),
          ],
          const SizedBox(height: 16),
          if ((p['description'] ?? '').toString().isNotEmpty) ...[
            const Text('Deskripsi', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('${p['description']}'),
            const SizedBox(height: 12),
          ],
          if (p['storage_tips'] != null) ...[
            const Text('Tips Penyimpanan', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('${p['storage_tips']}'),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
