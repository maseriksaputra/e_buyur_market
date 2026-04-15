// ignore_for_file: use_build_context_synchronously, avoid_print
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Dio & API base
import 'package:dio/dio.dart';
import 'package:e_buyur_market_flutter_5/app/core/network/api.dart';

import 'package:e_buyur_market_flutter_5/app/core/theme/app_colors.dart';
import 'package:e_buyur_market_flutter_5/app/common/widgets/primary_app_bar.dart';
import 'package:e_buyur_market_flutter_5/app/core/routes.dart';

// ambil token dari AuthProvider
import 'package:e_buyur_market_flutter_5/app/presentation/providers/auth_provider.dart';

// gunakan SellerProvider untuk refresh daftar produk seller
import 'package:e_buyur_market_flutter_5/app/presentation/providers/seller_provider.dart';

// enum kategori satu sumber kebenaran
import 'package:e_buyur_market_flutter_5/app/common/models/product_category.dart';

// HYBRID-AI (kita pakai QUALITY saja di halaman ini)
import 'package:e_buyur_market_flutter_5/ml/hybrid_ai_service.dart';

import 'package:http_parser/http_parser.dart'; // untuk MediaType multipart (fallback Gemini)

// ===== tambahan untuk refresh fitur "Produk Saya"
import 'package:e_buyur_market_flutter_5/app/features/providers/seller_products_provider.dart'
    as features;

// ===== B5: Event bus untuk notifikasi create product =====
import 'package:e_buyur_market_flutter_5/app/core/event/app_event.dart';

class CreateProductFromScanPage extends StatefulWidget {
  const CreateProductFromScanPage({Key? key}) : super(key: key);

  @override
  State<CreateProductFromScanPage> createState() =>
      _CreateProductFromScanPageState();
}

class _CreateProductFromScanPageState extends State<CreateProductFromScanPage> {
  // -------- argumen dari ScanScreen --------
  bool _parsedArgs = false;
  Uint8List? _initialImageBytes;
  String? _initialFilename;
  double? _aiScore; // 0..100 (double)
  String? _aiLabel;
  List<String>? _aiAnalysis;
  String? _initialName;

  // Tambahan sesuai patch
  double? _suitability; // 0..100 dari hasil scan / arguments
  bool _argsApplied = false; // mencegah double-apply saat rebuild

  // HYBRID-AI local inference state
  HybridAI? _ai;
  bool _localScanDone = false;
  bool _scanning = false;
  bool _geminiTried = false; // hindari fallback berulang

  String _scanLabel = 'Tidak Terdeteksi';
  double _scanConf = 0.0; // 0..1 (YOLO tidak dipakai di halaman ini)
  int _scanQualityPct = 0; // 0..100

  // -------- form controllers --------
  final _formKey = GlobalKey<FormState>();
  final _nameC = TextEditingController();
  final _priceC = TextEditingController(text: '10000');
  final _unitC = TextEditingController(text: 'kg');
  final _stockC = TextEditingController(text: '10');
  final _descC = TextEditingController();

  // State kategori enum
  ProductCategory? _category = ProductCategory.buah; // default

  // Gizi & penyimpanan
  final List<String> _nutrientOptions = const [
    'Vitamin C',
    'Vitamin A',
    'Serat',
    'Kalium',
    'Zat Besi',
    'Antioksidan',
    'Kalsium',
    'Protein',
    'Magnesium',
    'Folat',
  ];
  final Set<String> _selectedNutrients = {};

  String _storageMethod = 'room'; // room|chiller|freezer|dry|other
  final Map<String, String> _storageMethodLabel = const {
    'room': 'Suhu ruang',
    'chiller': 'Chiller/Kulkas',
    'freezer': 'Freezer',
    'dry': 'Kering/Sejuk',
    'other': 'Lainnya',
  };
  final _storageNotesC = TextEditingController();

  // Jika user ganti gambar manual (mis. dari galeri), simpan di sini
  Uint8List? _pickedImageBytes;
  String? _pickedFilename;

  bool _submitting = false;

  // ---------- helpers ----------
  // Ambil angka pertama yang tersedia dari beberapa kunci
  num? _firstNum(Map m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is num) return v;
      if (v is String) {
        final p = double.tryParse(v);
        if (p != null) return p;
      }
    }
    return null;
  }

  // Pastikan menjadi double 0..100
  double _clampPct(num v) {
    final d = v.toDouble();
    if (d.isNaN) return 0.0;
    if (d < 0) return 0.0;
    if (d > 100) return 100.0;
    return d;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_parsedArgs) {
      if (!_argsApplied) {
        final Object? raw = ModalRoute.of(context)?.settings.arguments;
        final Map args = (raw is Map) ? raw : const {};
        final s = _firstNum(args, [
          'initialSuitabilityPercent',
          'freshness_score',
          'suitability_percent',
          'score',
        ]);
        _suitability = _clampPct(s ?? 0);
        _aiScore = _suitability;

        final predicted = (args['predictedLabel'] ?? args['label'])?.toString();
        if ((predicted ?? '').isNotEmpty) {
          _nameC.text = _nameC.text.isEmpty ? predicted! : _nameC.text;
          _aiLabel = predicted;
        }

        _autoDescriptionFromScan();
        _argsApplied = true;
      }
      return;
    }

    final Object? argsRaw = ModalRoute.of(context)?.settings.arguments;
    if (argsRaw is Map) {
      // Gambar: utamakan capturedImageBytes lalu imageBytes
      _initialImageBytes =
          (argsRaw['capturedImageBytes'] as Uint8List?) ?? (argsRaw['imageBytes'] as Uint8List?);
      _initialFilename = (argsRaw['filename'] as String?) ?? 'scan.jpg';

      _initialName = argsRaw['name'] as String?;
      _aiAnalysis = (argsRaw['analysis'] as List?)?.cast<String>();

      // Skor dari berbagai kunci (tanpa default 5%)
      final s = _firstNum(argsRaw, [
        'initialSuitabilityPercent',
        'freshness_score',
        'suitability_percent',
        'score',
      ]);
      _suitability = _clampPct(s ?? 0);
      _aiScore = _suitability;

      // Label / predicted label
      _aiLabel = (argsRaw['predictedLabel'] ?? argsRaw['label']) as String?;

      // Isi nama default
      if (_initialName != null && _nameC.text.isEmpty) {
        _nameC.text = _initialName!;
      } else if ((_aiLabel ?? '').isNotEmpty && _nameC.text.isEmpty) {
        _nameC.text = _aiLabel!;
      }

      // Default deskripsi dari analisis AI
      _autoDescriptionFromScan();

      // (opsional) jika label AI bisa dipetakan, set kategori default
      final mapped = ProductCategoryX.fromAny(_aiLabel);
      if (mapped != null) _category = mapped;
    }

    _parsedArgs = true;
    setState(() {});

    // Jalankan local scan (QUALITY only) bila ada gambar awal
    _runLocalScanIfNeeded();
  }

  void _autoDescriptionFromScan() {
    if (_descC.text.trim().isEmpty) {
      final double s = _clampPct((_suitability ?? _aiScore ?? 0));
      final label = s >= 70 ? 'Cukup Layak' : 'Tidak Layak';
      final parts = <String>['Hasil pemindaian AI: $label (${s.toStringAsFixed(1)}%).'];
      if (_aiAnalysis?.isNotEmpty ?? false) {
        parts.add(_aiAnalysis!.join(' • '));
      }
      _descC.text = parts.join(' ');
    }
  }

  @override
  void dispose() {
    _nameC.dispose();
    _priceC.dispose();
    _unitC.dispose();
    _stockC.dispose();
    _descC.dispose();
    _storageNotesC.dispose();
    super.dispose();
  }

  Future<void> _ensureAi() async {
    _ai ??= await HybridAI.load();
  }

  // ================== QUALITY-ONLY, tanpa YOLO ==================
  Future<void> _runLocalScanIfNeeded() async {
    if (_localScanDone) return;
    final bytes = _pickedImageBytes ?? _initialImageBytes;
    if (bytes == null) return;

    _localScanDone = true;
    if (mounted) setState(() => _scanning = true);

    try {
      // Hitung QUALITY lokal
      await _ensureAi();
      final qPct = await _ai!.quality.percentFromBytes(bytes); // num/double kemungkinan
      final double incoming = _clampPct(_suitability ?? 0);
      final double local = _clampPct(qPct);

      // Strategi merge:
      // 1) Jika ada nilai dari Scan (incoming >= 1), JANGAN ditimpa mentah.
      // 2) Jika selisih kecil (<= 7 poin) -> rata-rata halus.
      // 3) Jika selisih besar  -> PERCAYA nilai dari Scan (hindari kasus turun jadi 5%).
      double finalS;
      if (incoming >= 1) {
        final double delta = (local - incoming).abs();
        finalS = (delta <= 7) ? ((incoming + local) / 2.0) : incoming;
      } else {
        finalS = local; // tidak ada nilai dari Scan, pakai lokal
      }

      if (mounted) {
        setState(() {
          _scanLabel = '-'; // di halaman ini kita tidak pakai label deteksi
          _scanConf = 0.0;
          _scanQualityPct = local.round();
          _aiLabel = _scanLabel;
          _aiScore = local;
          _suitability = finalS; // nilai yang dipakai UI & upload
        });
      }
    } catch (e) {
      debugPrint('[Scan] local quality error: $e');
      // Jika gagal, pertahankan nilai dari Scan agar tidak turun ke default
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }
  // =============================================================

  // ====== multipart + guard login + Options multipart ======
  Future<void> _maybeFallbackGemini(Uint8List bytes) async {
    final token = context.read<AuthProvider>().token;
    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masuk dulu untuk validasi AI (Gemini).')),
      );
      return;
    }

    try {
      API.setBearer(token); // set Authorization ke Dio

      final res = await API.dio.post(
        'ai/gemini/validate-image',
        data: FormData.fromMap({
          'image': MultipartFile.fromBytes(
            bytes,
            filename: _initialFilename ?? 'scan.jpg',
            contentType: MediaType('image', 'jpeg'),
          ),
          'percent': _scanQualityPct,
        }),
        // biarkan Dio set boundary multipart
        options: Options(
          contentType: 'multipart/form-data',
          headers: {
            'Accept': 'application/json',
          },
        ),
      );

      if (res.statusCode == 200 && res.data is Map) {
        final data = res.data as Map;
        final detected = (data['detected_item'] ?? '') as String;
        final conf = (data['confidence'] as num?)?.toDouble();
        final q = (data['quality_score'] as num?)?.toDouble();

        setState(() {
          if (detected.isNotEmpty) {
            _scanLabel = detected;
            _aiLabel = detected;
          }
          if (conf != null) _scanConf = conf;
          if (q != null) {
            _scanQualityPct = (q * 100).round().clamp(0, 100);
            _aiScore = _scanQualityPct.toDouble();
            _suitability = _aiScore; // sinkronkan ke variabel baru
          }
        });
      } else {
        debugPrint('[Gemini] status=${res.statusCode} body=${res.data}');
      }
    } catch (e) {
      debugPrint('[Gemini] fallback error: $e');
    }
  }
  // ==========================================================

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final double s = _clampPct(_suitability ?? 0);
    final suitabilityLabel = s >= 70 ? 'Cukup Layak' : 'Tidak Layak';

    return Scaffold(
      appBar: const PrimaryAppBar(title: 'Buat Produk dari Hasil Scan'),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              // ======= Ringkasan AI =======
              _AiSummaryCard(score: s, label: suitabilityLabel),

              const SizedBox(height: 12),
              // ======= Gambar Produk (+ badge label di atasnya) =======
              _SectionCard(
                title: 'Gambar Produk',
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _buildImagePreviewWithBadge(),
                  ),
                ),
              ),

              const SizedBox(height: 12),
              // ======= Informasi Produk =======
              _SectionCard(
                title: 'Informasi Produk',
                child: Column(
                  children: [
                    _LabeledField(
                      label: 'Nama Produk *',
                      child: TextFormField(
                        controller: _nameC,
                        textInputAction: TextInputAction.next,
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Wajib diisi' : null,
                        decoration: const InputDecoration(
                          hintText: 'Contoh: Mangga Arumanis',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _LabeledField(
                            label: 'Kategori *',
                            child: DropdownButtonFormField<ProductCategory>(
                              value: _category,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                              ),
                              items: ProductCategory.values.map((pc) {
                                return DropdownMenuItem(
                                  value: pc,
                                  child: Text(pc.label),
                                );
                              }).toList(),
                              onChanged: (v) => setState(() => _category = v),
                              validator: (v) =>
                                  v == null ? 'Pilih kategori' : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _LabeledField(
                            label: 'Satuan',
                            child: TextFormField(
                              controller: _unitC,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(hintText: 'kg'),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _LabeledField(
                            label: 'Harga *',
                            child: TextFormField(
                              controller: _priceC,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.next,
                              validator: _mustNumber,
                              decoration: const InputDecoration(
                                  prefixText: 'Rp ', hintText: 'contoh: 12000'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _LabeledField(
                            label: 'Stok *',
                            child: TextFormField(
                              controller: _stockC,
                              keyboardType: TextInputType.number,
                              validator: _mustInt,
                              decoration:
                                  const InputDecoration(hintText: 'contoh: 10'),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _LabeledField(
                      label: 'Deskripsi',
                      child: TextFormField(
                        controller: _descC,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText:
                              'Tuliskan kualitas, ukuran, atau catatan penting lainnya…',
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),
              // ======= Informasi Gizi / Nutrisi =======
              _SectionCard(
                title: 'Informasi Gizi / Nutrisi',
                subtitle:
                    'Pilih kandungan gizi utama pada produk (bisa lebih dari satu).',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _nutrientOptions.map((n) {
                    final active = _selectedNutrients.contains(n);
                    return ChoiceChip(
                      label: Text(n),
                      selected: active,
                      onSelected: (_) {
                        setState(() {
                          if (active) {
                            _selectedNutrients.remove(n);
                          } else {
                            _selectedNutrients.add(n);
                          }
                        });
                      },
                      selectedColor: AppColors.primaryGreen,
                      labelStyle: TextStyle(
                          color: active ? Colors.white : AppColors.textDark),
                      backgroundColor: AppColors.backgroundGrey,
                      shape: StadiumBorder(
                        side: BorderSide(
                          color: active
                              ? AppColors.primaryGreen
                              : AppColors.lightGrey,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 12),
              // ======= Saran Penyimpanan =======
              _SectionCard(
                title: 'Saran Penyimpanan',
                child: Column(
                  children: [
                    _LabeledField(
                      label: 'Metode Penyimpanan',
                      child: DropdownButtonFormField<String>(
                        value: _storageMethod,
                        decoration: const InputDecoration(),
                        items: _storageMethodLabel.entries
                            .map(
                              (e) => DropdownMenuItem<String>(
                                value: e.key,
                                child: Text(e.value),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() {
                          _storageMethod = v ?? 'room';
                        }),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _LabeledField(
                      label: 'Catatan (opsional)',
                      child: TextFormField(
                        controller: _storageNotesC,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          hintText: 'Misal: simpan di tempat sejuk & kering',
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              // ======= Submit =======
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: _submitting ? null : _submitCreate,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                  ),
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.cloud_upload_outlined),
                  label: Text(_submitting ? 'Mengunggah…' : 'Unggah Produk'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ========== widgets kecil ==========
  Widget _buildImagePreviewWithBadge() {
    final bytes = _pickedImageBytes ?? _initialImageBytes;
    if (bytes == null) {
      return Container(
        color: Colors.grey[200],
        child: const Center(
          child: Text('Tidak ada gambar'),
        ),
      );
    }

    // Overlay menampilkan suitability percent (sesuai patch)
    final String sText = _clampPct(_suitability ?? 0).toStringAsFixed(1);

    return Stack(
      children: [
        Positioned.fill(
          child: Image.memory(bytes, fit: BoxFit.cover),
        ),
        Positioned(
          left: 12,
          bottom: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.35),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$sText%',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickImage() async {
    // Tombol Ganti Foto disembunyikan — fungsi dibiarkan untuk kompatibilitas
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Picker gambar dinonaktifkan.')),
    );
  }

  String? _mustNumber(String? v) {
    if (v == null || v.trim().isEmpty) return 'Wajib diisi';
    final n = double.tryParse(v.replaceAll('.', '').replaceAll(',', '.'));
    if (n == null) return 'Harus angka';
    if (n < 0) return 'Tidak boleh negatif';
    return null;
  }

  String? _mustInt(String? v) {
    if (v == null || v.trim().isEmpty) return 'Wajib diisi';
    final n = int.tryParse(v);
    if (n == null) return 'Harus bilangan bulat';
    if (n < 0) return 'Tidak boleh negatif';
    return null;
  }

  // ========== submit -> multipart form langsung ==========
  Future<void> _submitCreate() async {
    // Validasi form
    if (!_formKey.currentState!.validate()) return;

    // Pastikan ada gambar
    final bytesForUpload = _pickedImageBytes ?? _initialImageBytes;
    final filenameForUpload =
        _pickedFilename ?? _initialFilename ?? 'photo.jpg';
    if (bytesForUpload == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto produk wajib diisi')),
      );
      return;
    }

    // Threshold kualitas minimal
    final int sNow = _clampPct(_suitability ?? 0).round();
    if (sNow < 70) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Skor kualitas < 70%. Produk tidak dapat diunggah'),
        ),
      );
      return;
    }
    final String freshnessLabel = sNow >= 70 ? 'Cukup Layak' : 'Tidak Layak';

    setState(() => _submitting = true);
    try {
      // Multipart image
      final imagePart = MultipartFile.fromBytes(
        bytesForUpload,
        filename: filenameForUpload,
        contentType: MediaType('image', 'jpeg'),
      );

      // Bangun form lengkap (dengan deskripsi, nutrisi, storage)
      final form = FormData.fromMap({
        'name': _nameC.text.trim().isEmpty
            ? (_aiLabel ?? 'Produk')
            : _nameC.text.trim(),
        'category': (_category ?? ProductCategory.buah).slug,
        'price': int.tryParse(_priceC.text.trim()) ?? 0,
        'unit': _unitC.text.trim().isEmpty ? 'kg' : _unitC.text.trim(),
        'stock': int.tryParse(_stockC.text.trim()) ?? 0,

        // AI
        'suitability_percent': sNow,
        'freshness_score': sNow,
        'freshness_label': freshnessLabel,

        // ====== penting: kirim field deskripsi/nutrisi/storage ======
        if (_descC.text.trim().isNotEmpty) 'description': _descC.text.trim(),
        if (_selectedNutrients.isNotEmpty)
          'nutrition': _selectedNutrients.join(', '),
        'storage_method': _storageMethod,
        if (_storageNotesC.text.trim().isNotEmpty)
          'storage_tips': _storageNotesC.text.trim(),

        // status
        'is_active': true,
        'status': 'published',

        // file
        'image': imagePart,
      });

      // Token
      final token = context.read<AuthProvider>().token;
      API.setBearer(token);

      // Kirim
      final res = await API.dio.post(
        'seller/products',
        data: form,
        options: Options(contentType: 'multipart/form-data'),
      );

      // Ambil payload product untuk dikirim balik (opsional)
      dynamic product;
      if (res.data is Map) {
        final map = res.data as Map;
        product = map['data'] ?? res.data;
      } else {
        product = res.data;
      }

      // Refresh daftar “Produk Saya”
      try {
        await context.read<features.SellerProductsProvider>().loadProducts();
      } catch (_) {
        // provider features belum dipasang → abaikan
      }
      try {
        final sellerProv = context.read<SellerProvider>();
        sellerProv.setAuthToken(token);
        await sellerProv.refreshProducts(page: 1);
      } catch (_) {
        // provider lama tidak dipakai → abaikan
      }

      // === B5: Beri tahu seluruh app bahwa produk baru dibuat ===
      AppEventBus.I.emit(AppEvent.productCreated);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Produk berhasil diunggah')),
      );

      // Kembali/redirect
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(product);
      } else {
        Navigator.of(context)
            .pushNamedAndRemoveUntil(AppRoutes.sellerHome, (r) => false);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

// ====== UI helpers ======
class _AiSummaryCard extends StatelessWidget {
  const _AiSummaryCard({required this.score, required this.label});
  final double score;
  final String label;

  Color _color(double pct) {
    if (pct >= 90) return const Color(0xFF16A34A);
    if (pct >= 80) return const Color(0xFF22C55E);
    if (pct >= 70) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    final c = _color(score);
    final sText = '${score.toStringAsFixed(1)}%';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.withOpacity(0.08),
        border: Border.all(color: c.withOpacity(0.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.eco, color: c),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              // Sumber nilai dari _suitability (score) + label sederhana
              'Kelayakan: $label ($sText)',
              style: TextStyle(
                color: c,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style:
                            TextStyle(color: Colors.grey[600], fontSize: 12.5),
                      ),
                    ],
                  ],
                ),
              ),
              // trailing dihilangkan (tombol Ganti Foto disembunyikan)
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: AppColors.textDark)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
