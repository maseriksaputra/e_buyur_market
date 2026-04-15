// lib/app/presentation/screens/seller/seller_home_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart' as theme;
import '../../../core/routes.dart';
import '../../providers/auth_provider.dart';
import '../../providers/seller_dashboard_provider.dart';
// Boleh dibiarkan, meski tidak dipakai langsung, agar kompatibel dengan struktur lama
import '../../providers/seller_provider.dart';

// Event bus (PATH sesuai struktur lib-mu)
import '../../../core/event/app_event.dart';

class SellerHomeScreen extends StatefulWidget {
  const SellerHomeScreen({super.key});

  @override
  State<SellerHomeScreen> createState() => _SellerHomeScreenState();
}

class _SellerHomeScreenState extends State<SellerHomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final ScrollController _scrollController = ScrollController();
  bool _isScrolled = false;

  // Future dummy agar FutureBuilder tidak melakukan side-effect saat build
  late Future<void> _init;

  // Subscription event bus
  StreamSubscription<AppEvent>? _eventSub;

  @override
  void initState() {
    super.initState();

    // Animations
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _animationController.forward();

    // Scroll listener
    _scrollController.addListener(() {
      final scrolled = _scrollController.offset > 10;
      if (scrolled != _isScrolled) {
        setState(() => _isScrolled = scrolled);
      }
    });

    _init = Future.value();

    // ⬇⬇ BACA PROVIDER SETELAH FRAME PERTAMA (hindari read di initState)
    Future.microtask(() async {
      if (!mounted) return;
      final ap = context.read<AuthProvider>();
      final dash = context.read<SellerDashboardProvider>();
      dash.setAuthToken(ap.token);
      await dash.loadDashboard();

      // Event bus aman dipasang setelah microtask
      _eventSub = AppEventBus.I.stream
          .where((e) =>
              e == AppEvent.productCreated || e == AppEvent.productUpdated)
          .listen((_) {
        if (!mounted) return;
        context.read<SellerDashboardProvider>().loadDashboard();
      });
    });

    // (opsional) cek role via post-frame agar tidak mengganggu build awal
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final ap = context.read<AuthProvider>();
      final roleNow = (ap.user?.role ?? '').toLowerCase();

      if (roleNow != 'seller') {
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Akses ditolak: hanya penjual yang bisa membuka halaman ini.'),
            duration: Duration(seconds: 2),
          ),
        );
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.buyerHome,
          (r) => false,
        );
      }
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _animationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nf =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    final auth = context.watch<AuthProvider>();

    final storeName =
        (auth.user?.storeName?.toString().trim().isNotEmpty ?? false)
            ? auth.user!.storeName!
            : (auth.user?.name ?? 'Toko Saya');

    final bottomPad = MediaQuery.of(context).viewPadding.bottom +
        kBottomNavigationBarHeight +
        24;

    const pendingOrders = 0;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: FutureBuilder<void>(
        future: _init,
        builder: (context, _) {
          return CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                expandedHeight: 140,
                floating: false,
                pinned: true,
                elevation: _isScrolled ? 4 : 0,
                backgroundColor: _isScrolled
                    ? theme.AppColors.primaryGreen
                    : Colors.transparent,
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
                  title: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _isScrolled ? 1.0 : 0.0,
                    child: Text(
                      storeName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        shadows: [
                          Shadow(
                            blurRadius: 8,
                            color: Colors.black26,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          theme.AppColors.primaryGreen,
                          theme.AppColors.primaryGreenDark,
                        ],
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          top: -50,
                          right: -50,
                          child: Container(
                            width: 200,
                            height: 200,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.1),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: -30,
                          left: -30,
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.08),
                            ),
                          ),
                        ),
                        SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'Selamat datang kembali',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.9),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        storeName,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 26,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.5,
                                          shadows: [
                                            Shadow(
                                              blurRadius: 10,
                                              color: Colors.black26,
                                              offset: Offset(0, 3),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  children: [
                                    _buildHeaderIcon(
                                      Icons.notifications_outlined,
                                      onTap: () {},
                                      hasBadge: pendingOrders > 0,
                                    ),
                                    const SizedBox(width: 8),
                                    _buildHeaderIcon(
                                      Icons.settings_outlined,
                                      onTap: () {},
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ===================== DASHBOARD CONTENT =====================
              SliverPadding(
                padding: EdgeInsets.only(bottom: bottomPad),
                sliver: SliverToBoxAdapter(
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: Consumer<SellerDashboardProvider>(
                        builder: (context, dash, _) {
                          return RefreshIndicator(
                            color: theme.AppColors.primaryGreen,
                            onRefresh: () => context
                                .read<SellerDashboardProvider>()
                                .loadDashboard(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 16),

                                if (dash.error != null) _errorChip(dash.error!),

                                // ====== METRIC CARDS ======
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20),
                                  child: Column(
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _modernMetricCard(
                                              context: context,
                                              title: 'Total Nilai Stok',
                                              value: nf.format(
                                                  dash.stockValueTotal),
                                              icon: Icons
                                                  .account_balance_wallet_outlined,
                                              gradient: [
                                                theme.AppColors.primaryGreen,
                                                theme.AppColors
                                                    .primaryGreenLight,
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: _modernMetricCard(
                                              context: context,
                                              title: 'Produk',
                                              value: '${dash.productCount}',
                                              icon: Icons.inventory_2_outlined,
                                              gradient: const [
                                                Color(0xFF66BB6A),
                                                Color(0xFF81C784),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _modernMetricCard(
                                              context: context,
                                              title: 'Stok (Unit)',
                                              value: '${dash.stockUnits}',
                                              icon: Icons.all_inbox_outlined,
                                              gradient: const [
                                                Color(0xFF43A047),
                                                Color(0xFF66BB6A),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: _modernMetricCard(
                                              context: context,
                                              title: 'Rata² Kesegaran',
                                              value:
                                                  '${dash.freshnessAvg.toStringAsFixed(0)}%',
                                              icon: Icons.eco_outlined,
                                              gradient: [
                                                theme
                                                    .AppColors.primaryGreenDark,
                                                theme.AppColors.primaryGreen,
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 28),

                                // ====== MENU CEPAT ======
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 4,
                                            height: 24,
                                            decoration: BoxDecoration(
                                              color: theme
                                                  .AppColors.primaryGreen,
                                              borderRadius:
                                                  BorderRadius.circular(2),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          const Text(
                                            'Menu Cepat',
                                            style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: -0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 20),

                                      Builder(
                                        builder: (context) {
                                          final m = MediaQuery.of(context);
                                          const menuCols = 4;
                                          const menuHPad = 20.0;
                                          const menuSpacing = 16.0;
                                          final menuTileW = (m.size.width -
                                                  (menuHPad * 2) -
                                                  menuSpacing *
                                                      (menuCols - 1)) /
                                              menuCols;

                                          final iconBlockH = 26.0 + 24.0;
                                          final labelH =
                                              14.0 * m.textScaleFactor + 6.0;
                                          final menuExtraH =
                                              iconBlockH + 8.0 + labelH;

                                          final menuAspect =
                                              (menuTileW / (menuTileW +
                                                      menuExtraH))
                                                  .clamp(0.60, 0.80) as double;

                                          return GridView.count(
                                            shrinkWrap: true,
                                            physics:
                                                const NeverScrollableScrollPhysics(),
                                            crossAxisCount: menuCols,
                                            mainAxisSpacing: menuSpacing,
                                            crossAxisSpacing: menuSpacing,
                                            childAspectRatio: menuAspect,
                                            children: [
                                              _modernQuickAction(
                                                icon: Icons.qr_code_scanner,
                                                label: 'Scan',
                                                color: theme
                                                    .AppColors.primaryGreen,
                                                onTap: () =>
                                                    Navigator.pushNamed(
                                                        context,
                                                        AppRoutes
                                                            .sellerScanProduct),
                                              ),
                                              _modernQuickAction(
                                                icon: Icons.add_box,
                                                label: 'Tambah',
                                                color:
                                                    const Color(0xFF2196F3),
                                                onTap: () =>
                                                    Navigator.pushNamed(
                                                        context,
                                                        AppRoutes
                                                            .sellerAddProduct),
                                              ),
                                              _modernQuickAction(
                                                icon: Icons.receipt_long,
                                                label: 'Pesanan',
                                                color: theme.AppColors
                                                    .secondaryOrange,
                                                onTap: () =>
                                                    Navigator.pushNamed(context,
                                                        AppRoutes.sellerOrders),
                                              ),
                                              _modernQuickAction(
                                                icon: Icons.analytics,
                                                label: 'Laporan',
                                                color:
                                                    const Color(0xFF009688),
                                                onTap: () =>
                                                    Navigator.pushNamed(
                                                        context,
                                                        AppRoutes
                                                            .sellerReports),
                                              ),
                                              _modernQuickAction(
                                                icon: Icons.inventory_2,
                                                label: 'Stok',
                                                color:
                                                    const Color(0xFF673AB7),
                                                onTap: () =>
                                                    Navigator.pushNamed(
                                                        context,
                                                        AppRoutes
                                                            .sellerInventory),
                                              ),
                                              _modernQuickAction(
                                                icon: Icons.local_shipping,
                                                label: 'Kirim',
                                                color:
                                                    const Color(0xFF4CAF50),
                                                onTap: () =>
                                                    Navigator.pushNamed(
                                                        context,
                                                        AppRoutes
                                                            .sellerShipping),
                                              ),
                                              _modernQuickAction(
                                                icon: Icons.discount,
                                                label: 'Promo',
                                                color:
                                                    const Color(0xFFE91E63),
                                                onTap: () =>
                                                    Navigator.pushNamed(
                                                        context,
                                                        AppRoutes
                                                            .sellerPromotions),
                                              ),
                                              _modernQuickAction(
                                                icon: Icons.support_agent,
                                                label: 'Bantuan',
                                                color:
                                                    const Color(0xFF795548),
                                                onTap: () =>
                                                    Navigator.pushNamed(
                                                        context,
                                                        AppRoutes
                                                            .sellerSupport),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 28),

                                // ====== PRODUK TERBARU ======
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 4,
                                            height: 24,
                                            decoration: BoxDecoration(
                                              color: theme
                                                  .AppColors.primaryGreen,
                                              borderRadius:
                                                  BorderRadius.circular(2),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          const Text(
                                            'Produk Terbaru',
                                            style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: -0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                      TextButton.icon(
                                        onPressed: () => Navigator.pushNamed(
                                            context,
                                            AppRoutes.sellerManageProducts),
                                        icon: Text(
                                          'Lihat Semua',
                                          style: TextStyle(
                                            color: theme
                                                .AppColors.primaryGreen,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        label: Icon(
                                          Icons.arrow_forward_ios,
                                          size: 14,
                                          color:
                                              theme.AppColors.primaryGreen,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // === B4: Gunakan dash.myProducts (horizontal)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  child: _buildLatest(),
                                ),

                                const SizedBox(height: 100),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ====== Widgets ======

  /// ✅ A. List Produk Terbaru dengan tinggi adaptif
  Widget _buildLatest() {
    final dash = context.watch<SellerDashboardProvider>();

    if (dash.isLoading && dash.myProducts.isEmpty) {
      return const SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (dash.myProducts.isEmpty) {
      return const _EmptyLatestCard();
    }

    // jika ada bar "freshness", butuh tinggi lebih besar
    final needFreshRow = dash.myProducts.any((p) {
      final v = p['freshness_score'] ?? p['suitability_percent'];
      if (v is num) return v > 0;
      if (v is String) return double.tryParse(v) != null;
      return false;
    });
    final listHeight = needFreshRow ? 200.0 : 168.0;

    return SizedBox(
      height: listHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (_, i) => _MiniProductCard(product: dash.myProducts[i]),
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemCount: dash.myProducts.length,
      ),
    );
  }

  Widget _errorChip(String message) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withOpacity(0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 16, color: Colors.red),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Gagal memuat, menampilkan data 0/cache. ($message)',
                style: const TextStyle(fontSize: 12, color: Colors.red),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderIcon(IconData icon,
      {required VoidCallback onTap, bool hasBadge = false}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
          ),
          child: Stack(
            children: [
              Icon(icon, color: Colors.white, size: 24),
              if (hasBadge)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: theme.AppColors.secondaryOrange,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modernQuickAction({
    required IconData icon,
    required String label,
    required Color color,
    String? badge,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.15),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(color: color.withOpacity(0.1), width: 1),
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            color.withOpacity(0.15),
                            color.withOpacity(0.08)
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icon, color: color, size: 26),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
              if (badge != null)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ====== UPDATED: _modernMetricCard anti-overflow (FittedBox + mainAxisSize) ======
  Widget _modernMetricCard({
    required BuildContext context,
    required String title,
    required String value,
    required IconData icon,
    required List<Color> gradient,
  }) {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: gradient[0].withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min, // kunci tambahan
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.9),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // angka auto-scale supaya tidak overflow
                      FittedBox(
                        alignment: Alignment.centerLeft,
                        fit: BoxFit.scaleDown,
                        child: Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.left,
                          style: const TextStyle(
                            fontSize: 20, // aman untuk textScale besar
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===== Komponen tambahan lokal =====

class _MiniProductCard extends StatelessWidget {
  const _MiniProductCard({required this.product});

  /// Bisa Map<String,dynamic> ATAU model (akan diubah ke Map untuk tampilan),
  /// dan saat membuka detail kita kirim **prefill lengkap** via arguments.
  final dynamic product;

  // Ubah objek produk apa pun menjadi Map prefill yang simpel (untuk tampilan kartu)
  Map<String, dynamic> _asProductMap(dynamic p) {
    if (p is Map<String, dynamic>) return Map<String, dynamic>.from(p);

    // Coba gunakan toJson()
    try {
      final tj = p.toJson();
      if (tj is Map<String, dynamic>) return Map<String, dynamic>.from(tj);
    } catch (_) {}

    T? _try<T>(T? Function() fn) {
      try {
        return fn();
      } catch (_) {
        return null;
      }
    }

    final map = <String, dynamic>{
      'id': _try(() => (p as dynamic).id) ??
          _try(() => (p as dynamic).productId),
      'name': _try(() => (p as dynamic).name),
      'price': _try(() => (p as dynamic).price),
      'stock': _try(() => (p as dynamic).stock),
      'image_url': _try(() => (p as dynamic).imageUrl) ??
          _try(() => (p as dynamic).primaryImageUrl),
      'description': _try(() => (p as dynamic).description),
      'suitability_percent': _try(() => (p as dynamic).suitabilityPercent),
      'freshness_score': _try(() => (p as dynamic).freshnessScore),
      'image': _try(() => (p as dynamic).image),
      'primary_image_url': _try(() => (p as dynamic).primary_image_url),
    };

    return map;
  }

  int? _parseId(dynamic id) {
    if (id == null) return null;
    if (id is int) return id;
    if (id is num) return id.toInt();
    return int.tryParse('$id');
  }

  /// Bangun prefill lengkap sesuai instruksi (aman untuk Map atau model).
  Map<String, dynamic> _buildPrefill(dynamic p) {
    // Raw map: langsung dari Map, atau coba dari toJson()
    Map<String, dynamic> raw = {};
    if (p is Map<String, dynamic>) {
      raw = Map<String, dynamic>.from(p);
    } else {
      try {
        final tj = (p as dynamic).toJson?.call();
        if (tj is Map<String, dynamic>) raw = Map<String, dynamic>.from(tj);
      } catch (_) {}
    }

    // Helper pilih nilai pertama yang non-null dari beberapa kandidat key
    dynamic pick(List<dynamic> candidates) {
      for (final c in candidates) {
        if (c != null) return c;
      }
      return null;
    }

    // Ambil id & konversi ke int?
    final id = _parseId(pick([
      raw['id'],
      raw['product_id'],
      (p is Map ? null : _tryDyn(() => (p as dynamic).id)),
      (p is Map ? null : _tryDyn(() => (p as dynamic).productId)),
    ]));

    // created_at → ke ISO string bila memungkinkan
    final createdRaw = pick([
      raw['created_at'],
      raw['createdAt'],
      (p is Map ? null : _tryDyn(() => (p as dynamic).createdAt)),
    ]);
    String? createdIso;
    if (createdRaw is DateTime) {
      createdIso = createdRaw.toIso8601String();
    } else if (createdRaw is String) {
      final dt = DateTime.tryParse(createdRaw);
      createdIso = dt?.toIso8601String() ?? createdRaw;
    }

    final prefill = <String, dynamic>{
      'id': id,
      'seller_id': pick([
        raw['seller_id'],
        raw['sellerId'],
        (p is Map ? null : _tryDyn(() => (p as dynamic).sellerId)),
      ]),
      'name': pick([
        raw['name'],
        (p is Map ? null : _tryDyn(() => (p as dynamic).name)),
      ]),
      'category': pick([
        raw['category'],
        (p is Map ? null : _tryDyn(() => (p as dynamic).category)),
      ]),
      'category_slug': pick([
        raw['category_slug'],
        raw['categorySlug'],
        (p is Map ? null : _tryDyn(() => (p as dynamic).categorySlug)),
      ]),
      'price': pick([
        raw['price'],
        (p is Map ? null : _tryDyn(() => (p as dynamic).price)),
      ]),
      'unit': pick([
        raw['unit'],
        (p is Map ? null : _tryDyn(() => (p as dynamic).unit)),
      ]),
      'stock': pick([
        raw['stock'],
        (p is Map ? null : _tryDyn(() => (p as dynamic).stock)),
      ]),
      'description': pick([
        raw['description'],
        (p is Map ? null : _tryDyn(() => (p as dynamic).description)),
      ]),
      'freshness_score': pick([
        raw['freshness_score'],
        raw['freshnessScore'],
        (p is Map ? null : _tryDyn(() => (p as dynamic).freshnessScore)),
      ]),
      'freshness_label': pick([
        raw['freshness_label'],
        raw['freshnessLabel'],
        (p is Map ? null : _tryDyn(() => (p as dynamic).freshnessLabel)),
      ]),
      'suitability_percent': pick([
        raw['suitability_percent'],
        raw['suitabilityPercent'],
        (p is Map ? null : _tryDyn(() => (p as dynamic).suitabilityPercent)),
      ]),
      'nutrition': pick([
        raw['nutrition'],
        (p is Map ? null : _tryDyn(() => (p as dynamic).nutrition)),
      ]),
      'storage_tips': pick([
        raw['storage_tips'],
        raw['storageTips'],
        (p is Map ? null : _tryDyn(() => (p as dynamic).storageTips)),
      ]),
      'image_url': pick([
        raw['image_url'],
        raw['image'],
        raw['primary_image_url'],
        raw['primaryImageUrl'],
        (p is Map ? null : _tryDyn(() => (p as dynamic).imageUrl)),
        (p is Map ? null : _tryDyn(() => (p as dynamic).primaryImageUrl)),
      ]),
      'status': pick([
        raw['status'],
        (p is Map ? null : _tryDyn(() => (p as dynamic).status)),
      ]),
      'is_active': pick([
        raw['is_active'],
        raw['isActive'],
        (p is Map ? null : _tryDyn(() => (p as dynamic).isActive)),
      ]),
      'created_at': createdIso,
    };

    return prefill;
  }

  static T? _tryDyn<T>(T? Function() fn) {
    try {
      return fn();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // peta untuk tampilan (nama, harga, gambar, freshness, dst.)
    final pmap = _asProductMap(product);

    final nf =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    final name = (pmap['name'] ?? '').toString();

    // cari image dengan beberapa fallback key
    final image = (pmap['image'] ??
            pmap['image_url'] ??
            pmap['primary_image_url'] ??
            '')
        .toString();

    final price =
        (pmap['price'] is num) ? (pmap['price'] as num).toDouble() : null;

    final fresh = (pmap['freshness_score'] is num)
        ? (pmap['freshness_score'] as num).toDouble()
        : (pmap['suitability_percent'] is num)
            ? (pmap['suitability_percent'] as num).toDouble()
            : null;

    final id = _parseId(pmap['id']);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      // ✅ Kirim prefill lengkap + rootNavigator, sesuai instruksi
      onTap: () {
        HapticFeedback.lightImpact();
        final prefill = _buildPrefill(product);
        Navigator.of(context, rootNavigator: true).pushNamed(
          AppRoutes.sellerProductDetail,
          arguments: {
            'id': id,
            'product': prefill,
            'source': 'seller',
          },
        );
      },
      child: Container(
        width: 150,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
          border: Border.all(
            color: theme.AppColors.primaryGreen.withOpacity(0.08),
          ),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Gambar (diperkecil sedikit)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                height: 86, // was 90
                width: double.infinity,
                color: theme.AppColors.primaryGreen.withOpacity(0.06),
                child: image.isEmpty
                    ? Icon(Icons.shopping_basket,
                        color: theme.AppColors.primaryGreen, size: 28)
                    : Image.network(
                        image,
                        height: 86,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.shopping_basket,
                          color: theme.AppColors.primaryGreen,
                          size: 28,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 6), // was 8

            // Nama
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4), // was 6

            // Harga
            if (price != null)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2), // was 3
                decoration: BoxDecoration(
                  color: theme.AppColors.primaryGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  nf.format(price),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.AppColors.primaryGreen,
                  ),
                ),
              ),

            // Freshness bar (opsional) + trimming spacing
            if (fresh != null) ...[
              const SizedBox(height: 6), // was 8
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (fresh.clamp(0, 100)) / 100,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          theme.AppColors.freshnessColor(fresh),
                        ),
                        minHeight: 6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${fresh.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.AppColors.freshnessColor(fresh),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyLatestCard extends StatelessWidget {
  const _EmptyLatestCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white,
            theme.AppColors.primaryGreen.withOpacity(0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.AppColors.primaryGreen.withOpacity(0.2),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.AppColors.primaryGreen.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.inventory_2_outlined,
              size: 48,
              color: theme.AppColors.primaryGreen,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Belum ada produk',
            style: TextStyle(
              color: Colors.grey[700],
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Scan atau tambah produk pertama Anda',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
