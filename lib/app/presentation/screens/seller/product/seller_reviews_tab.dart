import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// sesuaikan helper
const String kApiBase = 'https://your-api-base-url.com/api';
Future<Map<String, String>> defaultHeaders({bool multipart = false}) async {
  final h = <String, String>{'Accept': 'application/json'};
  if (!multipart) h['Content-Type'] = 'application/json';
  // h['Authorization'] = 'Bearer ...';
  return h;
}

class SellerReviewsTab extends StatefulWidget {
  final int productId;
  final String? apiBase;
  final Future<Map<String, String>> Function({bool multipart})? headerProvider;
  const SellerReviewsTab(
      {super.key, required this.productId, this.apiBase, this.headerProvider});

  @override
  State<SellerReviewsTab> createState() => _SellerReviewsTabState();
}

class _SellerReviewsTabState extends State<SellerReviewsTab> {
  bool loading = false;
  bool error = false;
  String? errorMsg;
  final List<Map<String, dynamic>> items = [];

  Future<void> _fetch() async {
    setState(() => loading = true);
    try {
      final base = widget.apiBase ?? kApiBase;
      final h = await (widget.headerProvider ?? defaultHeaders)
          .call(multipart: false);
      final uri =
          Uri.parse('$base/seller/reviews?product_id=${widget.productId}');
      final res = await http.get(uri, headers: h);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final m = jsonDecode(res.body) as Map<String, dynamic>;
        final data = ((m['data'] ?? []) as List)
            .cast<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
        setState(() => items
          ..clear()
          ..addAll(data));
      } else {
        setState(() => {error = true, errorMsg = 'HTTP ${res.statusCode}'});
      }
    } catch (e) {
      setState(() => {error = true, errorMsg = e.toString()});
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
    if (loading && items.isEmpty)
      return const Center(child: CircularProgressIndicator());
    if (error && items.isEmpty)
      return Center(child: Text(errorMsg ?? 'Gagal memuat'));

    return RefreshIndicator(
      onRefresh: () async => _fetch(),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final r = items[i];
          final buyer = (r['buyer'] is Map)
              ? (r['buyer']['name'] ?? 'Pengguna')
              : 'Pengguna';
          final rating = (r['rating'] ?? 0) as int;
          final visible = (r['is_visible'] ?? true) as bool;

          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text(buyer,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600))),
                      Row(
                          children: List.generate(
                              5,
                              (j) => Icon(
                                  j < rating ? Icons.star : Icons.star_border,
                                  size: 16))),
                    ]),
                    if ((r['comment'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(r['comment']),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text('Tampilkan',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.primary)),
                        Switch(
                          value: visible,
                          onChanged: (v) async {
                            final base = widget.apiBase ?? kApiBase;
                            final h =
                                await (widget.headerProvider ?? defaultHeaders)
                                    .call(multipart: false);
                            final uri = Uri.parse(
                                '$base/seller/reviews/${r['id']}/visibility');
                            final res = await http.patch(uri,
                                headers: h,
                                body: jsonEncode({'is_visible': v}));
                            if (res.statusCode >= 200 && res.statusCode < 300) {
                              setState(() => items[i]['is_visible'] = v);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content:
                                          Text('Gagal update visibilitas')));
                            }
                          },
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () async {
                            final msg = await showDialog<String>(
                              context: context,
                              builder: (_) => const _ReplyDialog(),
                            );
                            if (msg != null && msg.trim().isNotEmpty) {
                              final base = widget.apiBase ?? kApiBase;
                              final h = await (widget.headerProvider ??
                                      defaultHeaders)
                                  .call(multipart: false);
                              final uri = Uri.parse(
                                  '$base/seller/reviews/${r['id']}/respond');
                              final res = await http.post(uri,
                                  headers: h,
                                  body: jsonEncode({'message': msg}));
                              if (res.statusCode >= 200 &&
                                  res.statusCode < 300) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Balasan terkirim')));
                                _fetch();
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Gagal kirim balasan')));
                              }
                            }
                          },
                          child: const Text('Balas'),
                        )
                      ],
                    ),
                  ]),
            ),
          );
        },
      ),
    );
  }
}

class _ReplyDialog extends StatefulWidget {
  const _ReplyDialog();
  @override
  State<_ReplyDialog> createState() => _ReplyDialogState();
}

class _ReplyDialogState extends State<_ReplyDialog> {
  final c = TextEditingController();
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Balas Ulasan'),
      content: TextField(
          controller: c,
          maxLines: 4,
          decoration: const InputDecoration(border: OutlineInputBorder())),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal')),
        ElevatedButton(
            onPressed: () => Navigator.pop(context, c.text),
            child: const Text('Kirim')),
      ],
    );
  }
}
