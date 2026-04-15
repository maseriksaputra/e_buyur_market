import 'package:dio/dio.dart';
import '../services/api.dart'; // pastikan ini menginisialisasi Dio baseUrl & auth

class ProductRepository {
  final Dio _dio = API.dio;

  // ====== UTIL: fallback envelope & ekstraksi list yang fleksibel ======

  Map<String, dynamic> _errorEnvelope(Object e, [StackTrace? st]) {
    // Jangan lempar; kembalikan payload aman agar UI tidak meledak
    return <String, dynamic>{
      'status': 'error',
      'message': e.toString(),
    };
  }

  /// Ambil list dari berbagai bentuk payload yang umum:
  /// - [ ... ] (list langsung)
  /// - { data: [ ... ] }
  /// - { data: { items: [ ... ] } }
  /// - { data: { rows: [ ... ] } }
  /// - { items: [ ... ] } / { rows: [ ... ] }
  List<dynamic> _extractRawList(dynamic data) {
    if (data is List) return data;

    if (data is Map) {
      // 1st layer
      if (data['data'] is List) return data['data'] as List;

      if (data['items'] is List) return data['items'] as List;
      if (data['rows'] is List) return data['rows'] as List;

      // 2nd layer (common pagination envelope)
      final d = data['data'];
      if (d is Map) {
        if (d['items'] is List) return d['items'] as List;
        if (d['rows'] is List) return d['rows'] as List;
        if (d['data'] is List) return d['data'] as List; // nested
      }
    }

    return const <dynamic>[];
  }

  Map<String, dynamic> _safeMap(dynamic v) {
    if (v is Map) {
      return Map<String, dynamic>.from(v as Map);
    }
    return <String, dynamic>{};
  }

  // ====== VERSI AMAN untuk ambil list (RAW MAP) ======

  /// Versi aman yang selalu mengembalikan List<Map> meskipun backend 500 / payload berubah.
  /// Gunakan ini di provider agar UI tidak crash saat server error.
  Future<List<Map<String, dynamic>>> getSellerProductsRaw({
    int page = 1,
    int perPage = 12,
    String? q,
    String? status,
    bool? active,
  }) async {
    try {
      final res = await _dio.get(
        'seller/products',
        queryParameters: {
          'page': page,
          'per_page': perPage,
          if (q != null && q.isNotEmpty) 'q': q,
          if (status != null && status.isNotEmpty) 'status': status,
          if (active != null) 'active': active ? 1 : 0,
        },
      );

      if (res.statusCode != 200 || res.data == null) {
        return <Map<String, dynamic>>[]; // graceful fallback
      }

      final data = res.data;

      // Envelope error (kalau backend pakai {status:'error',...})
      if (data is Map && (data['status'] == 'error' || data['error'] == true)) {
        return <Map<String, dynamic>>[];
      }

      final rawList = _extractRawList(data);
      return rawList.map<Map<String, dynamic>>(_safeMap).toList();
    } catch (_) {
      // Jangan lempar; UI tetap hidup
      return <Map<String, dynamic>>[];
    }
  }

  // ====== VERSI AMAN untuk ambil list (GENERIC TYPED) ======

  /// Versi typed yang menerima mapper `fromJson`. Contoh pakai:
  /// `repo.getSellerProducts<Product>(fromJson: Product.fromJson)`
  Future<List<T>> getSellerProducts<T>({
    required T Function(Map<String, dynamic>) fromJson,
    int page = 1,
    int perPage = 12,
    String? q,
    String? status,
    bool? active,
  }) async {
    try {
      final res = await _dio.get(
        'seller/products',
        queryParameters: {
          'page': page,
          'per_page': perPage,
          if (q != null && q.isNotEmpty) 'q': q,
          if (status != null && status.isNotEmpty) 'status': status,
          if (active != null) 'active': active ? 1 : 0,
        },
      );

      if (res.statusCode != 200 || res.data == null) {
        return <T>[];
      }

      final data = res.data;

      if (data is Map && (data['status'] == 'error' || data['error'] == true)) {
        return <T>[];
      }

      final rawList = _extractRawList(data);
      final items = <T>[];
      for (final e in rawList) {
        try {
          final m = _safeMap(e);
          items.add(fromJson(m));
        } catch (_) {
          // Skip item yang rusak; jangan gagalkan semuanya
        }
      }
      return items;
    } catch (_) {
      return <T>[];
    }
  }

  // ====== METHOD LAMA (dipertahankan), dibikin aman ======

  /// Tetap ada untuk kompatibilitas, sekarang dibuat tahan 500:
  Future<Map<String, dynamic>> listSeller({
    String? q,
    String? status,
    bool? active,
    int page = 1,
  }) async {
    try {
      final res = await _dio.get('seller/products', queryParameters: {
        if (q != null && q.isNotEmpty) 'q': q,
        if (status != null) 'status': status,
        if (active != null) 'active': active ? 1 : 0,
        'page': page,
      });

      if (res.statusCode != 200 || res.data == null) {
        // Envelope kosong agar UI aman
        return <String, dynamic>{
          'data': <dynamic>[],
          'page': page,
          'status': 'ok',
        };
      }

      final data = res.data;
      if (data is Map && (data['status'] == 'error' || data['error'] == true)) {
        return <String, dynamic>{
          'data': <dynamic>[],
          'page': page,
          'status': 'error',
          'message': data['message'] ?? 'Server error',
        };
      }

      // Biarkan bentuk asli, tapi pastikan Map
      return _safeMap(data);
    } catch (e, st) {
      // Jangan lempar
      return _errorEnvelope(e, st);
    }
  }

  Future<Map<String, dynamic>> create({
    required String name,
    required String category, // 'buah'|'sayur'
    required int price,
    required String unit,
    required int stock,
    String? description,
    String? nutritionInfo,
    String? storageNotes,
    int? suitabilityPercent,
    double? freshnessScore,
    String? freshnessLabel,
    String status = 'published',
    String? imagePath,
    List<String>? galleryPaths,
  }) async {
    try {
      final form = FormData();

      form.fields.addAll([
        MapEntry('name', name),
        MapEntry('category', category),
        MapEntry('price', '$price'),
        MapEntry('unit', unit),
        MapEntry('stock', '$stock'),
        MapEntry('status', status),
        if (description != null) MapEntry('description', description),
        if (nutritionInfo != null) MapEntry('nutrition_info', nutritionInfo),
        if (storageNotes != null) MapEntry('storage_notes', storageNotes),
        if (suitabilityPercent != null)
          MapEntry('suitability_percent', '$suitabilityPercent'),
        if (freshnessScore != null)
          MapEntry('freshness_score', freshnessScore.toString()),
        if (freshnessLabel != null) MapEntry('freshness_label', freshnessLabel),
      ]);

      if (imagePath != null) {
        form.files.add(
          MapEntry('image',
              await MultipartFile.fromFile(imagePath, filename: 'main.jpg')),
        );
      }
      if (galleryPaths != null) {
        for (int i = 0; i < galleryPaths.length; i++) {
          form.files.add(
            MapEntry(
              'gallery[$i]',
              await MultipartFile.fromFile(galleryPaths[i],
                  filename: 'g$i.jpg'),
            ),
          );
        }
      }

      final res = await _dio.post('seller/products', data: form);
      return _safeMap(res.data);
    } catch (e, st) {
      return _errorEnvelope(e, st);
    }
  }

  Future<Map<String, dynamic>> update({
    required int id,
    String? name,
    String? category,
    int? price,
    String? unit,
    int? stock,
    String? description,
    String? nutritionInfo,
    String? storageNotes,
    int? suitabilityPercent,
    double? freshnessScore,
    String? freshnessLabel,
    String? status,
    String? imagePath,
    List<String>? galleryPathsAppend,
    bool? isActive,
  }) async {
    try {
      final form = FormData();
      if (name != null) form.fields.add(MapEntry('name', name));
      if (category != null) form.fields.add(MapEntry('category', category));
      if (price != null) form.fields.add(MapEntry('price', '$price'));
      if (unit != null) form.fields.add(MapEntry('unit', unit));
      if (stock != null) form.fields.add(MapEntry('stock', '$stock'));
      if (description != null) {
        form.fields.add(MapEntry('description', description));
      }
      if (nutritionInfo != null) {
        form.fields.add(MapEntry('nutrition_info', nutritionInfo));
      }
      if (storageNotes != null) {
        form.fields.add(MapEntry('storage_notes', storageNotes));
      }
      if (suitabilityPercent != null) {
        form.fields.add(MapEntry('suitability_percent', '$suitabilityPercent'));
      }
      if (freshnessScore != null) {
        form.fields
            .add(MapEntry('freshness_score', freshnessScore.toString()));
      }
      if (freshnessLabel != null) {
        form.fields.add(MapEntry('freshness_label', freshnessLabel));
      }
      if (status != null) form.fields.add(MapEntry('status', status));
      if (isActive != null) {
        form.fields.add(MapEntry('is_active', isActive ? '1' : '0'));
      }

      if (imagePath != null) {
        form.files.add(
          MapEntry('image',
              await MultipartFile.fromFile(imagePath, filename: 'main.jpg')),
        );
      }
      if (galleryPathsAppend != null) {
        for (int i = 0; i < galleryPathsAppend.length; i++) {
          form.files.add(
            MapEntry(
              'gallery[$i]',
              await MultipartFile.fromFile(
                galleryPathsAppend[i],
                filename: 'g$i.jpg',
              ),
            ),
          );
        }
      }

      final res = await _dio.post('seller/products/$id', data: form);
      return _safeMap(res.data);
    } catch (e, st) {
      return _errorEnvelope(e, st);
    }
  }

  Future<void> toggleActive(int id) async {
    try {
      await _dio.patch('/seller/products/$id/toggle');
    } catch (_) {
      // swallow error agar UI tidak crash
    }
  }

  Future<void> delete(int id) async {
    try {
      await _dio.delete('seller/products/$id');
    } catch (_) {
      // swallow error agar UI tidak crash
    }
  }
}
