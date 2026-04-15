// lib/app/core/utils/url_fix.dart
const _placeholder =
    'https://via.placeholder.com/600x600.png?text=No+Image';

// Host API kamu (tanpa trailing slash)
const _host = 'https://api.ebuyurmarket.com';

String fixImageUrl(String? raw) {
  var s = (raw ?? '').trim();
  if (s.isEmpty) return _placeholder;

  // blokir data URL / svg
  if (s.startsWith('data:') || s.toLowerCase().endsWith('.svg')) {
    return _placeholder;
  }

  // normalisasi host dev → prod
  s = s.replaceFirst(RegExp(r'^https?://127\.0\.0\.1:\d+'), _host);
  s = s.replaceFirst(RegExp(r'^https?://[^/]+:8000'), _host);

  // jika sudah absolut, langsung pakai
  if (s.startsWith('http://') || s.startsWith('https://')) {
    return s;
  }

  // relatif → absolut; map storage→pub & products→pub/products
  var p = s.startsWith('/') ? s.substring(1) : s;
  p = p.replaceFirst(RegExp(r'^storage/'), 'pub/');
  p = p.replaceFirst(RegExp(r'^products/'), 'pub/products/'); // ✅ tambah

  return '$_host/$p';
}
