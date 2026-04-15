import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'tulis_ulasan_sheet.dart';

// Sesuaikan kalau kamu pakai helper API sendiri
const String kApiBase = 'https://your-api-base-url.com/api';
Future<Map<String, String>> defaultHeaders({bool multipart = false}) async {
  final h = <String, String>{'Accept': 'application/json'};
  if (!multipart) h['Content-Type'] = 'application/json';
  return h;
}

class UlasanSection extends StatefulWidget {
  final int productId;
  final double avgRating;
  final int ratingCount;
  final String? apiBase;
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

  // paging & flags
  int page = 1;
  bool loading = false;
  bool error = false;
  String? errorMsg;
  bool noReviews = false; // <-- NEW: penanda tidak ada ulasan

  // data
  final List<Map<String, dynamic>> items = [];
  double avg = 0;
  int count = 0;
  int satisfiedPct = 0;
  Map<String, int> stars = {'5': 0, '4': 0, '3': 0, '2': 0, '1': 0};
  List<String> summaryPhotos = [];

  Future<void> _fetch({bool reset = false}) async {
    if (loading) return;
    setState(() {
      loading = true;
      error = false;
      if (reset) {
        page = 1;
        items.clear();
        noReviews = false; // reset flag saat refresh
      }
    });

    try {
      final base = widget.apiBase ?? kApiBase;
      final headersFn = widget.headerProvider ?? defaultHeaders;

      final params = {
        'sort': sort,
        'page': '$page',
        if (mediaOnly) 'has_photo': '1',
        if (ratingEq != null) 'rating': '${ratingEq!}',
      };
      final uri = Uri.parse('$base/products/${widget.productId}/reviews')
          .replace(queryParameters: params);

      final res =
          await http.get(uri, headers: await headersFn(multipart: false));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final map = jsonDecode(res.body) as Map<String, dynamic>;

        // ===== summary =====
        final s = (map['summary'] ?? {}) as Map;
        avg = (s['avg'] ?? widget.avgRating).toDouble();
        count = (s['count'] ?? widget.ratingCount) as int;
        satisfiedPct = (s['satisfied_pct'] ?? 0) as int;

        final st = (s['stars'] ?? {}) as Map;
        stars = {
          '5': (st['5'] ?? st[5] ?? 0) as int,
          '4': (st['4'] ?? st[4] ?? 0) as int,
          '3': (st['3'] ?? st[3] ?? 0) as int,
          '2': (st['2'] ?? st[2] ?? 0) as int,
          '1': (st['1'] ?? st[1] ?? 0) as int,
        };

        summaryPhotos = ((s['photos'] ?? []) as List)
            .map((e) => (e is Map) ? (e['url'] ?? '') : e.toString())
            .whereType<String>()
            .toList();

        // ===== data list =====
        final data = ((map['data'] ?? []) as List)
            .cast<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();

        setState(() {
          items.addAll(data);
          // Tandai "Belum ada ulasan." bila ringkasan 0 dan list kosong.
          noReviews = (count == 0) && items.isEmpty;
        });
      } else {
        setState(() {
          error = true;
          errorMsg = 'HTTP ${res.statusCode}';
        });
      }
    } catch (e) {
      // Jangan spam snackbar: cukup tandai error.
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
    final ratingText = avg.isNaN ? '0.00' : avg.toStringAsFixed(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ===== Ringkasan =====
        _SummaryHeader(
          ratingText: ratingText,
          satisfiedPct: satisfiedPct,
          count: count,
          stars: stars,
        ),
        const SizedBox(height: 12),

        // ===== Galeri Foto Ulasan (ringkas) =====
        if (summaryPhotos.isNotEmpty) _MediaRow(urls: summaryPhotos),

        const SizedBox(height: 8),
        // ===== Filter bar (media, rating, sort) =====
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

        // ===== Pesan kosong / error sederhana =====
        if (!loading && items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              noReviews ? 'Belum ada ulasan.' : 'Tidak bisa memuat ulasan.',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),

        // ===== Daftar Ulasan =====
        for (final r in items) _ReviewCard(r: r),

        if (loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),

        if (!loading && items.isNotEmpty)
          TextButton(
            onPressed: () {
              page += 1;
              _fetch();
            },
            child: const Text('Muat lagi'),
          ),

        const SizedBox(height: 16),

        // ===== Tulis Ulasan =====
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () async {
              final ok = await showModalBottomSheet<bool>(
                context: context,
                isScrollControlled: true,
                builder: (_) => TulisUlasanSheet(
                  productId: widget.productId,
                  apiBase: widget.apiBase,
                  headerProvider: widget.headerProvider,
                ),
              );
              if (ok == true) _fetch(reset: true);
            },
            icon: const Icon(Icons.rate_review),
            label: const Text('Tulis Ulasan'),
          ),
        ),
      ],
    );
  }
}

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

    int totalUlasan() {
      // jumlahkan aman meski map kosong
      var t = 0;
      for (final v in stars.values) t += v;
      return t;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // skor besar
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$ratingText / 5.0',
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold),
                ),
                Text('$satisfiedPct% pembeli merasa puas'),
                Text('$count rating • ${totalUlasan()} ulasan'),
              ],
            ),
            const SizedBox(width: 16),
            // distribusi
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
          final u = urls[i];
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              u,
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
    final photos = ((r['photos'] ?? []) as List)
        .cast<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();

    // jenis × qty dari orderItem (aman)
    final oi = r['order_item'] ?? r['orderItem'];
    String? variantName;
    String? qtyText;
    if (oi is Map) {
      final rawVar = oi['variant_name'] ?? oi['variant'];
      variantName = rawVar?.toString();
      final rawQty = oi['quantity'];
      if (rawQty is num) {
        qtyText = '× ${rawQty.toInt()}';
      } else if (rawQty is String) {
        final q = int.tryParse(rawQty);
        if (q != null) qtyText = '× $q';
      }
    }

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
                child: Text(
                  buyer.toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < rating ? Icons.star : Icons.star_border,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
          if (variantName != null || qtyText != null) ...[
            const SizedBox(height: 6),
            Text(
              'Dibeli: ${variantName ?? "-"}${qtyText ?? ""}',
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
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
                final url = (p['url'] ?? p['path'] ?? '').toString();
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
