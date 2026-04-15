import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/review_api_service.dart';
import '../../screens/buyer/write_review_page.dart';

/// Widget ulasan produk (fetch, filter, paginasi).
/// Tambahan properti:
/// - [showWriteButton] : tampilkan tombol "Tulis Ulasan" (default false / sembunyikan di halaman produk)
/// - [showHeaderTitle] : tampilkan judul "Ulasan Pembeli" (default true)
class ProductReviewsSection extends StatefulWidget {
  final int productId;
  final String? productName;

  /// Tampilkan judul "Ulasan Pembeli" di header
  final bool showHeaderTitle;

  /// Tampilkan tombol "Tulis Ulasan"
  final bool showWriteButton;

  const ProductReviewsSection({
    super.key,
    required this.productId,
    this.productName,
    this.showHeaderTitle = true,
    this.showWriteButton = false,
  });

  @override
  State<ProductReviewsSection> createState() => _ProductReviewsSectionState();
}

class _ProductReviewsSectionState extends State<ProductReviewsSection> {
  late final ReviewApiService api;
  String sort = 'recent';
  int? ratingFilter; // 1..5 / null = semua
  bool hasPhoto = false;

  bool loading = true;
  bool loadingMore = false;
  bool hasMore = false;
  int page = 1;

  ReviewSummary? summary;
  final List<ReviewItem> items = [];

  @override
  void initState() {
    super.initState();
    // Ambil Dio dari Provider; kalau tidak ada, ReviewApiService kamu
    // sebaiknya punya ctor default sendiri. Di sini asumsi Provider<Dio> tersedia.
    api = ReviewApiService(context.read<Dio>());
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        loading = true;
        page = 1;
        items.clear();
        hasMore = false;
      });
    } else {
      if (loadingMore || !hasMore) return;
      setState(() => loadingMore = true);
    }

    try {
      final r = await api.fetch(
        productId: widget.productId,
        sort: sort,
        rating: ratingFilter,
        hasPhoto: hasPhoto,
        page: page,
      );
      if (!mounted) return;
      setState(() {
        summary = r.summary;
        items.addAll(r.data);
        hasMore = r.currentPage < r.lastPage;
        if (hasMore) page = r.currentPage + 1;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat ulasan: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
          loadingMore = false;
        });
      }
    }
  }

  Future<void> _openWrite() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => WriteReviewPage(
          productId: widget.productId,
          productName: widget.productName,
        ),
      ),
    );
    if (ok == true && mounted) {
      _load(reset: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sum = summary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),

        // Header: judul + tombol tulis (opsional)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              if (widget.showHeaderTitle)
                Expanded(
                  child: Text(
                    'Ulasan Pembeli',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                )
              else
                const Spacer(),
              if (widget.showWriteButton)
                FilledButton.icon(
                  onPressed: _openWrite,
                  icon: const Icon(Icons.rate_review_outlined, size: 18),
                  label: const Text('Tulis Ulasan'),
                ),
            ],
          ),
        ),

        // Ringkasan rating
        if (sum != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: _SummaryCard(summary: sum),
          )
        else if (loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(minHeight: 2),
          ),

        // Filter bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip('Semua', selected: ratingFilter == null, onTap: () {
                ratingFilter = null;
                _load(reset: true);
              }),
              for (final s in [5, 4, 3, 2, 1])
                _chip('$s★', selected: ratingFilter == s, onTap: () {
                  ratingFilter = s;
                  _load(reset: true);
                }),
              _chip(
                hasPhoto ? 'Dengan Foto ✓' : 'Dengan Foto',
                icon: Icons.photo_camera_back_outlined,
                selected: hasPhoto,
                onTap: () {
                  hasPhoto = !hasPhoto;
                  _load(reset: true);
                },
              ),
              _sortDropdown(),
            ],
          ),
        ),

        // Galeri foto kecil
        if (sum != null && sum.photos.isNotEmpty)
          SizedBox(
            height: 76,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              scrollDirection: Axis.horizontal,
              itemBuilder: (_, i) {
                final p = sum.photos[i];
                return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    p.url,
                    height: 64,
                    width: 64,
                    fit: BoxFit.cover,
                  ),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemCount: sum.photos.length,
            ),
          ),

        const SizedBox(height: 8),

        // List ulasan
        if (loading && items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Belum ada ulasan.'),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemBuilder: (_, i) => _ReviewTile(item: items[i]),
            separatorBuilder: (_, __) => const Divider(height: 24),
            itemCount: items.length,
          ),

        if (hasMore)
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: loadingMore ? null : () => _load(reset: false),
              child: loadingMore
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Muat Lagi'),
            ),
          ),

        const SizedBox(height: 24),
      ],
    );
  }

  Widget _chip(
    String label, {
    bool selected = false,
    IconData? icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected
          ? Theme.of(context).colorScheme.primary
          : const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 16,
                  color: selected ? Colors.white : const Color(0xFF334155)),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: selected ? Colors.white : const Color(0xFF334155),
                fontWeight: FontWeight.w600,
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _sortDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: sort,
          items: const [
            DropdownMenuItem(value: 'recent', child: Text('Terbaru')),
            DropdownMenuItem(value: 'rating', child: Text('Tertinggi')),
            DropdownMenuItem(value: 'photo', child: Text('Dengan Foto')),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => sort = v);
            _load(reset: true);
          },
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final ReviewSummary summary;
  const _SummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final total = summary.count == 0 ? 1 : summary.count;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 12)
        ],
      ),
      child: Row(
        children: [
          // rata-rata besar
          SizedBox(
            width: 90,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summary.avg.toStringAsFixed(2),
                  style: const TextStyle(
                      fontSize: 32, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                _stars(summary.avg.round()),
                Text('${summary.count} ulasan',
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
                Text('${summary.satisfiedPct}% puas',
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // breakdown bar 5..1
          Expanded(
            child: Column(
              children: [5, 4, 3, 2, 1].map((s) {
                final cnt = summary.stars[s] ?? 0;
                final pct = cnt / total;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                          width: 18,
                          child: Text('$s', textAlign: TextAlign.right)),
                      const SizedBox(width: 6),
                      const Icon(Icons.star,
                          size: 14, color: Color(0xFFFFC107)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 8,
                          backgroundColor: const Color(0xFFE2E8F0),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                          width: 36,
                          child:
                              Text(cnt.toString(), textAlign: TextAlign.right)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stars(int n) {
    return Row(
      children: List.generate(
        5,
        (i) => Icon(
          i < n ? Icons.star : Icons.star_border,
          size: 18,
          color: const Color(0xFFFFC107),
        ),
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final ReviewItem item;
  const _ReviewTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const CircleAvatar(radius: 18, child: Icon(Icons.person, size: 18)),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(
                item.buyerName ?? 'Pengguna',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            _stars(item.rating),
          ]),
          if (item.variantName != null || item.quantity != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                [
                  if (item.variantName != null) item.variantName!,
                  if (item.quantity != null) 'x${item.quantity}',
                ].join(' · '),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          if ((item.comment ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(item.comment!, style: const TextStyle(fontSize: 14)),
            ),
          if (item.photos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: item.photos
                    .map(
                      (u) => ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(u,
                            height: 72, width: 72, fit: BoxFit.cover),
                      ),
                    )
                    .toList(),
              ),
            ),
        ]),
      )
    ]);
  }

  Widget _stars(int n) => Row(
        children: List.generate(
          5,
          (i) => Icon(
            i < n ? Icons.star : Icons.star_border,
            size: 14,
            color: const Color(0xFFFFC107),
          ),
        ),
      );
}
