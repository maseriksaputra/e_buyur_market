// lib/app/presentation/widgets/review/ulasan_section.dart
// Versi: no write button, punya timeout, fallback baseUrl tanpa ApiConfig.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// 🔧 Tambah: normalisasi URL gambar
import '../../../core/utils/url_fix.dart';

// ====== Header helper (kalau kamu punya headerProvider sendiri boleh dioper) ======
Future<Map<String, String>> _defaultHeaders({bool multipart = false}) async {
  final h = <String, String>{'Accept': 'application/json'};
  if (!multipart) h['Content-Type'] = 'application/json';
  return h;
}

// Fallback base URL (bisa dioverride lewat widget.apiBase)
String _defaultBaseUrl() {
  // bisa diset via --dart-define=API_BASE_URL=https://domain/api/v1
  const env = String.fromEnvironment('API_BASE_URL', defaultValue: '');
  if (env.isNotEmpty) return env;
  if (kIsWeb) return 'http://127.0.0.1:8000/api/v1';
  if (Platform.isAndroid) return 'http://10.0.2.2:8000/api/v1';
  return 'http://127.0.0.1:8000/api/v1';
}

class UlasanSection extends StatefulWidget {
  final int productId;
  final double avgRating;
  final int ratingCount;

  /// Optional override API base (default ke _defaultBaseUrl)
  final String? apiBase;

  /// Optional header provider
  final Future<Map<String, String>> Function({bool multipart})? headerProvider;

  const UlasanSection({
    super.key,
    required this.productId,
    required this.avgRating,
    required this.ratingCount,
    this.apiBase,
    this.headerProvider,
  });

  @override
  State<UlasanSection> createState() => _UlasanSectionState();
}

class _UlasanSectionState extends State<UlasanSection> {
  // query
  String sort = 'recent';
  int? ratingEq; // null = semua
  bool mediaOnly = false;

  // paging & state
  int page = 1;
  bool loading = false;
  bool error = false;
  String? errorMsg;

  // data
  final List<Map<String, dynamic>> items = [];
  double avg = 0;
  int count = 0;
  int satisfiedPct = 0;
  Map<String, int> stars = {'5': 0, '4': 0, '3': 0, '2': 0, '1': 0};
  List<String> summaryPhotos = [];
  bool noReviews = false;

  Future<void> _fetch({bool reset = false}) async {
    if (loading) return;
    setState(() {
      loading = true;
      error = false;
      errorMsg = null;
      if (reset) {
        page = 1;
        items.clear();
        noReviews = false;
      }
    });

    try {
      final base = (widget.apiBase?.trim().isNotEmpty == true)
          ? widget.apiBase!.trim()
          : _defaultBaseUrl();

      final headersFn = widget.headerProvider ?? _defaultHeaders;

      final params = <String, String>{
        'sort': sort,
        'page': '$page',
        if (mediaOnly) 'has_photo': '1',
        if (ratingEq != null) 'rating': '${ratingEq!}',
      };

      final uri = Uri.parse('$base/products/${widget.productId}/reviews')
          .replace(queryParameters: params);

      // ⏱ timeout agar tak menggantung
      final res = await http
          .get(uri, headers: await headersFn(multipart: false))
          .timeout(const Duration(seconds: 15));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final map = jsonDecode(res.body) as Map<String, dynamic>;

        final s = (map['summary'] ?? {}) as Map;
        final avgRaw = s['avg'] ?? widget.avgRating;
        avg = (avgRaw is num) ? avgRaw.toDouble() : 0.0;
        count = (s['count'] is num)
            ? (s['count'] as num).toInt()
            : widget.ratingCount;
        satisfiedPct = (s['satisfied_pct'] is num)
            ? (s['satisfied_pct'] as num).toInt()
            : 0;

        final st = (s['stars'] ?? {}) as Map;
        stars = {
          '5': (st['5'] ?? st[5] ?? 0) as int,
          '4': (st['4'] ?? st[4] ?? 0) as int,
          '3': (st['3'] ?? st[3] ?? 0) as int,
          '2': (st['2'] ?? st[2] ?? 0) as int,
          '1': (st['1'] ?? st[1] ?? 0) as int,
        };

        // ✅ Normalisasi URL foto ringkasan
        summaryPhotos = ((s['photos'] ?? []) as List)
            .map((e) => (e is Map)
                ? (e['url'] ?? e['path'] ?? '')
                : e.toString())
            .map((u) => fixImageUrl(u))
            .where((u) => u.isNotEmpty)
            .toList();

        final data = ((map['data'] ?? []) as List)
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();

        setState(() {
          items.addAll(data);
          noReviews = (count == 0) && items.isEmpty;
        });
      } else {
        setState(() {
          error = true;
          errorMsg = 'HTTP ${res.statusCode}';
        });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        error = true;
        errorMsg = 'Timeout saat memuat ulasan (15s).';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = true;
        errorMsg = e.toString();
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final ratingText = avg.isNaN ? '0.0' : avg.toStringAsFixed(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummaryHeader(
          ratingText: ratingText,
          satisfiedPct: satisfiedPct,
          count: count,
          stars: stars,
        ),
        const SizedBox(height: 12),

        if (summaryPhotos.isNotEmpty) _MediaRow(urls: summaryPhotos),

        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              label: const Text('Media'),
              selected: mediaOnly,
              onSelected: (v) {
                setState(() => mediaOnly = v);
                _fetch(reset: true);
              },
            ),
            DropdownButton<int?>(
              value: ratingEq,
              hint: const Text('Rating'),
              items: const [
                DropdownMenuItem(value: null, child: Text('Semua')),
                DropdownMenuItem(value: 5, child: Text('5 ★')),
                DropdownMenuItem(value: 4, child: Text('4 ★')),
                DropdownMenuItem(value: 3, child: Text('3 ★')),
                DropdownMenuItem(value: 2, child: Text('2 ★')),
                DropdownMenuItem(value: 1, child: Text('1 ★')),
              ],
              onChanged: (v) {
                setState(() => ratingEq = v);
                _fetch(reset: true);
              },
            ),
            const Spacer(),
            DropdownButton<String>(
              value: sort,
              items: const [
                DropdownMenuItem(value: 'recent', child: Text('Terbaru')),
                DropdownMenuItem(
                    value: 'rating', child: Text('Rating Tertinggi')),
                DropdownMenuItem(value: 'photo', child: Text('Dengan Foto')),
              ],
              onChanged: (v) {
                if (v != null) {
                  setState(() => sort = v);
                  _fetch(reset: true);
                }
              },
            ),
          ],
        ),

        const SizedBox(height: 12),
        if (error && items.isEmpty) _ErrorInline(message: errorMsg),

        for (final r in items) _ReviewCard(r: r),

        if (loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),

        if (!loading && items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              noReviews ? 'Belum ada ulasan.' : 'Tidak bisa memuat ulasan.',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),

        if (!loading && items.isNotEmpty)
          TextButton(
              onPressed: () {
                page += 1;
                _fetch();
              },
              child: const Text('Muat lagi')),

        // ❌ Tidak ada tombol “Tulis Ulasan” di section ini
        const SizedBox(height: 8),
      ],
    );
  }
}

// ====== Komponen UI kecil ======

class _SummaryHeader extends StatelessWidget {
  final String ratingText;
  final int satisfiedPct;
  final int count;
  final Map<String, int> stars;
  const _SummaryHeader({
    required this.ratingText,
    required this.satisfiedPct,
    required this.count,
    required this.stars,
  });

  @override
  Widget build(BuildContext context) {
    Widget bar(int star) {
      final total = count == 0 ? 1 : count;
      final v = (stars['$star'] ?? 0) / total;
      return Row(
        children: [
          SizedBox(width: 18, child: Text('$star', textAlign: TextAlign.right)),
          const SizedBox(width: 4),
          const Icon(Icons.star, size: 14),
          const SizedBox(width: 8),
          Expanded(child: LinearProgressIndicator(value: v)),
          const SizedBox(width: 8),
          SizedBox(width: 28, child: Text('${stars['$star'] ?? 0}')),
        ],
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$ratingText / 5.0',
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold)),
                Text('$satisfiedPct% pembeli merasa puas'),
                Text(
                    '$count rating • ${(stars.values).fold<int>(0, (a, b) => a + b)} ulasan'),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                children: [
                  for (final s in [5, 4, 3, 2, 1]) ...[
                    bar(s),
                    if (s != 1) const SizedBox(height: 6),
                  ]
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaRow extends StatelessWidget {
  final List<String> urls;
  const _MediaRow({required this.urls});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: urls.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          // ✅ Pastikan URL sudah fixed, dan fallback placeholder bila kosong/error
          final fixed = fixImageUrl(urls[i]);
          if (fixed.isEmpty) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 96,
                height: 96,
                color: Theme.of(context).colorScheme.surfaceVariant,
                child: const Icon(Icons.image_not_supported),
              ),
            );
          }
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              fixed,
              width: 96,
              height: 96,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 96,
                height: 96,
                color: Theme.of(context).colorScheme.surfaceVariant,
                child: const Icon(Icons.image_not_supported),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> r;
  const _ReviewCard({required this.r});
  @override
  Widget build(BuildContext context) {
    final buyer =
        (r['buyer'] is Map) ? (r['buyer']['name'] ?? 'Pengguna') : 'Pengguna';
    final rating = (r['rating'] ?? 0) as int;
    final comment = (r['comment'] ?? '').toString();
    final photos = ((r['photos'] ?? []) as List).whereType<Map>().toList();

    final oi = (r['order_item'] ?? r['orderItem']) as Map?;
    final variantName = oi?['variant_name'] ?? oi?['variant'];
    final qty = oi?['quantity'];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              const CircleAvatar(child: Icon(Icons.person)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('$buyer',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Row(
                  children: List.generate(
                      5,
                      (i) => Icon(i < rating ? Icons.star : Icons.star_border,
                          size: 18))),
            ],
          ),
          if (variantName != null || qty != null) ...[
            const SizedBox(height: 6),
            Text('Dibeli: ${variantName ?? "-"}${qty != null ? " × $qty" : ""}',
                style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          ],
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(comment),
          ],
          if (photos.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: photos.map((p) {
                // ✅ Normalisasi setiap foto ulasan
                final raw = (p['url'] ?? p['path'] ?? '').toString();
                final url = fixImageUrl(raw);
                if (url.isEmpty) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 96,
                      height: 96,
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      child: const Icon(Icons.image_not_supported),
                    ),
                  );
                }
                return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    url,
                    width: 96,
                    height: 96,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 96,
                      height: 96,
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      child: const Icon(Icons.image_not_supported),
                    ),
                  ),
                );
              }).toList(),
            )
          ],
        ]),
      ),
    );
  }
}

class _ErrorInline extends StatelessWidget {
  final String? message;
  const _ErrorInline({this.message});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(message ?? 'Gagal memuat ulasan.',
          style:
              TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
    );
  }
}
