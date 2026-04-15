// lib/app/core/services/review_api_service.dart
import 'package:dio/dio.dart' as dio;

import '../auth/token_store_io.dart' if (dart.library.html) '../auth/token_store_web.dart';

class ReviewPhotoLite {
  final int id;
  final String url;
  ReviewPhotoLite({required this.id, required this.url});
  factory ReviewPhotoLite.fromJson(Map<String, dynamic> j) =>
      ReviewPhotoLite(id: (j['id'] as num).toInt(), url: (j['url'] ?? '') as String);
}

class ReviewSummary {
  final double avg;
  final int count;
  final Map<int, int> stars; // {5: n, 4: n, ...}
  final int satisfiedPct; // % ulasan 4★+5★
  final List<ReviewPhotoLite> photos;
  ReviewSummary({
    required this.avg,
    required this.count,
    required this.stars,
    required this.satisfiedPct,
    required this.photos,
  });
  factory ReviewSummary.fromJson(Map<String, dynamic> j) => ReviewSummary(
        avg: (j['avg'] ?? 0).toDouble(),
        count: (j['count'] ?? 0) is num ? (j['count'] as num).toInt() : 0,
        stars: {
          5: (j['stars']?['5'] ?? j['stars']?[5] ?? 0) as int,
          4: (j['stars']?['4'] ?? j['stars']?[4] ?? 0) as int,
          3: (j['stars']?['3'] ?? j['stars']?[3] ?? 0) as int,
          2: (j['stars']?['2'] ?? j['stars']?[2] ?? 0) as int,
          1: (j['stars']?['1'] ?? j['stars']?[1] ?? 0) as int,
        },
        satisfiedPct: (j['satisfied_pct'] ?? 0) is num
            ? (j['satisfied_pct'] as num).toInt()
            : 0,
        photos: ((j['photos'] ?? []) as List)
            .whereType<Map>()
            .map((e) => ReviewPhotoLite.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class ReviewItem {
  final int id;
  final int rating;
  final String? comment;
  final String? buyerName;
  final List<String> photos;
  final String? variantName;
  final int? quantity;
  final DateTime? createdAt;

  ReviewItem({
    required this.id,
    required this.rating,
    required this.comment,
    required this.buyerName,
    required this.photos,
    this.variantName,
    this.quantity,
    this.createdAt,
  });

  factory ReviewItem.fromJson(Map<String, dynamic> j) {
    final buyer = (j['buyer'] is Map)
        ? Map<String, dynamic>.from(j['buyer'])
        : <String, dynamic>{};
    final imgs = (j['photos'] as List? ?? const [])
        .whereType<Map>()
        .map((e) {
          final m = Map<String, dynamic>.from(e);
          final url = (m['url'] ?? m['path'] ?? '').toString();
          return url;
        })
        .where((s) => s.isNotEmpty)
        .toList();

    // parsing aman orderItem
    final oi = j['order_item'] ?? j['orderItem'];
    String? variantName;
    int? quantity;
    if (oi is Map) {
      final map = Map<String, dynamic>.from(oi);
      final rawVariant = map['variant_name'] ?? map['variant'];
      if (rawVariant != null) {
        variantName = rawVariant.toString();
      }
      final rawQty = map['quantity'];
      if (rawQty is num) {
        quantity = rawQty.toInt();
      } else if (rawQty is String) {
        quantity = int.tryParse(rawQty);
      }
    }

    return ReviewItem(
      id: (j['id'] as num).toInt(),
      rating: (j['rating'] as num).toInt(),
      comment: j['comment']?.toString(),
      buyerName: buyer['name']?.toString(),
      photos: imgs,
      variantName: variantName,
      quantity: quantity,
      createdAt: j['created_at'] != null
          ? DateTime.tryParse(j['created_at'].toString())
          : null,
    );
  }
}

class ReviewPage {
  final ReviewSummary summary;
  final List<ReviewItem> data;
  final int currentPage, lastPage, perPage, total;
  ReviewPage({
    required this.summary,
    required this.data,
    required this.currentPage,
    required this.lastPage,
    required this.perPage,
    required this.total,
  });
}

class EligibleOrderItem {
  final int id;
  final String? variantName;
  final int? quantity;
  final String? orderCode;
  EligibleOrderItem(
      {required this.id, this.variantName, this.quantity, this.orderCode});

  factory EligibleOrderItem.fromJson(Map<String, dynamic> j) =>
      EligibleOrderItem(
        id: ((j['id'] ?? j['order_item_id']) as num).toInt(),
        variantName: (j['variant_name'] ?? j['variant'])?.toString(),
        quantity: (j['quantity'] is num)
            ? (j['quantity'] as num).toInt()
            : (j['quantity'] is String ? int.tryParse(j['quantity']) : null),
        orderCode: j['order_code']?.toString(),
      );
}

class ReviewApiService {
  final dio.Dio _dio;
  ReviewApiService(this._dio);

  Future<Map<String, String>> _authHeaders() async {
    final token = await TokenStore.read();
    final h = <String, String>{
      'Accept': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    }
    return h;
  }

  // helper kosong untuk fallback error/timeout
  ReviewSummary _emptySummary() => ReviewSummary(
        avg: 0,
        count: 0,
        stars: const {5: 0, 4: 0, 3: 0, 2: 0, 1: 0},
        satisfiedPct: 0,
        photos: const [],
      );

  ReviewPage _emptyPage() => ReviewPage(
        summary: _emptySummary(),
        data: const [],
        currentPage: 1,
        lastPage: 1,
        perPage: 0,
        total: 0,
      );

  // GET list ulasan
  Future<ReviewPage> fetch({
    required int productId,
    String sort = 'recent', // recent|rating|photo
    int? rating, // 1..5
    bool hasPhoto = false,
    int page = 1,
  }) async {
    try {
      final res = await _dio.get(
        'products/$productId/reviews',
        queryParameters: {
          'sort': sort,
          if (rating != null) 'rating': rating,
          if (hasPhoto) 'has_photo': 1,
          'page': page,
        },
        options: dio.Options(
          headers: await _authHeaders(),
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      final root = (res.data is Map)
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};

      final summary = ReviewSummary.fromJson(
        Map<String, dynamic>.from(root['summary'] ?? {}),
      );

      final list = (root['data'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => ReviewItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      final meta = Map<String, dynamic>.from(root['meta'] ?? {});
      int _toInt(dynamic v, int d) {
        if (v is num) return v.toInt();
        final p = int.tryParse('$v');
        return p ?? d;
      }

      return ReviewPage(
        summary: summary,
        data: list,
        currentPage: _toInt(meta['current_page'], 1),
        lastPage: _toInt(meta['last_page'], 1),
        perPage: _toInt(meta['per_page'], list.length),
        total: _toInt(meta['total'], list.length),
      );
    } on dio.DioException {
      return _emptyPage();
    } catch (_) {
      return _emptyPage();
    }
  }

  // GET kandidat order item yang sudah delivered untuk produk ini (best effort)
  Future<List<EligibleOrderItem>> eligibleOrderItems(int productId) async {
    final tryUrls = <String>[
      '/buyer/order-items', // ?product_id=&status=delivered
      '/orders/my',         // ?status=delivered&product_id=
    ];
    for (final u in tryUrls) {
      try {
        final res = await _dio.get(
          u,
          queryParameters: {'product_id': productId, 'status': 'delivered'},
          options: dio.Options(
            headers: await _authHeaders(),
            sendTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(seconds: 30),
          ),
        );
        final body = res.data;
        final data = (body is Map) ? (body['data'] ?? body) : body;
        final list = (data as List)
            .whereType<Map>()
            .map((e) => EligibleOrderItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        if (list.isNotEmpty) return list;
      } on dio.DioException {
        // lanjut coba endpoint berikutnya
      } catch (_) {
        // lanjut coba endpoint berikutnya
      }
    }
    return <EligibleOrderItem>[];
  }

  // POST buat ulasan
  Future<void> create({
    required int productId,
    required int orderItemId,
    required int rating,
    String? comment,
    List<dio.MultipartFile> photos = const [],
  }) async {
    final form = dio.FormData.fromMap({
      'product_id': productId,
      'order_item_id': orderItemId,
      'rating': rating,
      if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim(),
      if (photos.isNotEmpty) 'photos': photos, // array 'photos[]'
    });

    await _dio.post(
      'reviews',
      data: form,
      options: dio.Options(
        headers: await _authHeaders(),
        contentType: 'multipart/form-data',
        sendTimeout: const Duration(seconds: 45),
        receiveTimeout: const Duration(seconds: 45),
      ),
    );
  }
}
