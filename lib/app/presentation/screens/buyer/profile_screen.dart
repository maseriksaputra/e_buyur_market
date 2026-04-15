// lib/app/presentation/screens/buyer/profile_screen.dart
import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:e_buyur_market_flutter_5/app/presentation/providers/auth_provider.dart';
import 'package:e_buyur_market_flutter_5/app/presentation/providers/cart_provider.dart';
import 'package:e_buyur_market_flutter_5/app/presentation/providers/favorite_provider.dart';

import '../../../core/theme/app_colors.dart';

// Helper: ambil provider TANPA listen (untuk pemanggilan aksi di luar build)
T? maybeProvider<T>(BuildContext context) {
  try {
    return Provider.of<T>(context, listen: false);
  } catch (_) {
    return null;
  }
}

// Helper: ambil provider DENGAN listen (dipakai di build agar widget rebuild)
T? watchMaybe<T>(BuildContext context) {
  try {
    // default listen:true
    return Provider.of<T>(context);
  } catch (_) {
    return null;
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _firstLoaded = false;

  String _firstInitial(String? name) {
    final t = (name ?? '').trim();
    if (t.isEmpty) return 'U';
    return t.substring(0, 1).toUpperCase();
  }

  /// 🔁 Refresh terpusat (HANYA dipanggil dari initState & pull-to-refresh)
  Future<void> _refreshAll({bool force = false}) async {
    final auth = maybeProvider<AuthProvider>(context);
    final cart = maybeProvider<CartProvider>(context);
    final fav  = maybeProvider<FavoriteProvider>(context);

    // 1) Selalu segarkan profil terlebih dahulu (tidak melempar error)
    try { await auth?.refreshMe(); } catch (_) {}

    // 2) Jika role buyer, barulah muat cart & favorit
    if ((auth?.effectiveRole ?? 'buyer') == 'buyer') {
      // cart
      try { await cart?.fetchCart(force: force); } catch (_) {}
      // favorite (perlu token)
      final token = auth?.token;
      if (token != null && token.isNotEmpty) {
        try { await fav?.refresh(token); } catch (_) {}
      }
    }
  }

  void _safePushNamed(String route, {Object? arguments}) {
    try {
      Navigator.of(context).pushNamed(route, arguments: arguments);
    } catch (e, st) {
      dev.log('Route not found or navigator error: $route', error: e, stackTrace: st);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Halaman belum tersedia: $route')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    // 🚫 Tidak ada fetch di build(); hanya sekali di sini + pull-to-refresh
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (_firstLoaded) return;
      _firstLoaded = true;
      try {
        await _refreshAll();
      } catch (e, st) {
        dev.log('refreshAll (init) error', error: e, stackTrace: st);
      }
    });
  }

  // --- UI helpers ---
  Widget _avatar(String? name, String? url) {
    final initial = _firstInitial(name);
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: Colors.white, width: 3),
      ),
      child: ClipOval(
        child: (url != null && url.isNotEmpty)
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallback(initial),
              )
            : _fallback(initial),
      ),
    );
  }

  Widget _fallback(String initial) => Container(
        color: AppColors.primaryGreen.withOpacity(.18),
        child: Center(
          child: Text(
            initial,
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryGreen,
            ),
          ),
        ),
      );

  Widget _stat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: AppColors.primaryGreen, size: 22),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }

  Widget _menuCard({required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(.05), blurRadius: 10, offset: const Offset(0, 2))
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _item({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primaryGreen, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ]
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Divider(height: 1, color: Colors.grey[200]);

  @override
  Widget build(BuildContext context) {
    // 🔎 Pakai watchMaybe agar build hanya rebuild saat provider notifyListeners()
    final auth = watchMaybe<AuthProvider>(context);
    final cart = watchMaybe<CartProvider>(context);
    final fav  = watchMaybe<FavoriteProvider>(context);

    // Jika provider belum terdaftar, tampilkan info (daripada stuck)
    if (auth == null || cart == null || fav == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Profil Saya'),
          backgroundColor: AppColors.primaryGreen,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.orange),
                const SizedBox(height: 12),
                const Text(
                  'Provider belum terpasang di root widget.\nPastikan AuthProvider, CartProvider, dan FavoriteProvider terdaftar di MultiProvider.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => _refreshAll(force: true),
                  child: const Text('Coba Muat Ulang'),
                )
              ],
            ),
          ),
        ),
      );
    }

    final me = auth.user;
    final cartCount = () {
      try { return cart.items.length; } catch (_) { return 0; }
    }();
    final favCount = fav.count;

    final isLoadingBar = auth.isLoading || cart.isLoading || fav.isLoading;
    final isLoading    = auth.isLoading; // status utama untuk penentu konten
    final err          = auth.error;     // ambil error dari AuthProvider

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Profil Saya'),
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.white,
        bottom: isLoadingBar
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      // 🌀 Pull-to-refresh memanggil _refreshAll(force: true)
      body: RefreshIndicator(
        onRefresh: () => _refreshAll(force: true),
        // Urutan prioritas: ERROR -> LOADING -> EMPTY -> CONTENT
        child: (me == null && err != null && err.isNotEmpty)
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  const SizedBox(height: 80),
                  Center(child: Icon(Icons.error_outline, size: 48, color: Colors.red.shade400)),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      err,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black87),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: () => _refreshAll(force: true),
                      child: const Text('Coba lagi'),
                    ),
                  ),
                  const SizedBox(height: 80),
                ],
              )
            : (me == null && isLoading)
                ? const _LoadingPlaceholder()
                : (me == null && !isLoading)
                    ? const _EmptyStateProfile()
                    : SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Column(
                          children: [
                            // Header
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    AppColors.primaryGreen,
                                    AppColors.primaryGreen.withOpacity(.85),
                                  ],
                                ),
                              ),
                              child: Column(
                                children: [
                                  _avatar(me!.name, me.profilePictureUrl),
                                  const SizedBox(height: 16),
                                  Text(
                                    me.name ?? '-',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    me.email ?? '-',
                                    style: const TextStyle(fontSize: 14, color: Colors.white70),
                                  ),
                                  if ((me.phone ?? '').isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      me.phone!,
                                      style: const TextStyle(fontSize: 13, color: Colors.white70),
                                    ),
                                  ],
                                  const SizedBox(height: 14),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(.18),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          (me.isVerified ?? false) ? Icons.verified : Icons.person_outline,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          (me.isVerified ?? false) ? 'Akun Terverifikasi' : 'Akun',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.white,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Ringkasan
                            Container(
                              margin: const EdgeInsets.all(16),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 2),
                                  )
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  _stat('Keranjang', '$cartCount', Icons.shopping_cart_outlined),
                                  Container(width: 1, height: 40, color: Colors.grey[300]),
                                  _stat('Favorit', '$favCount', Icons.favorite_outline),
                                  Container(width: 1, height: 40, color: Colors.grey[300]),
                                  _stat('Pesanan', '-', Icons.shopping_bag_outlined),
                                ],
                              ),
                            ),

                            // Menu
                            _menuCard(children: [
                              _item(
                                icon: Icons.person_outline,
                                title: 'Edit Profil',
                                onTap: () => _safePushNamed(
                                  '/buyer/profile/edit',
                                  arguments: {'name': me.name, 'email': me.email, 'phone': me.phone},
                                ),
                              ),
                              _divider(),
                              _item(
                                icon: Icons.shopping_cart_outlined,
                                title: 'Buka Keranjang',
                                onTap: () => _safePushNamed('/cart'),
                              ),
                              _divider(),
                              _item(
                                icon: Icons.favorite_outline,
                                title: 'Daftar Favorit',
                                onTap: () => _safePushNamed('/favorites'),
                              ),
                              _divider(),
                              _item(
                                icon: Icons.location_on_outlined,
                                title: 'Alamat Pengiriman',
                                onTap: () => _safePushNamed('/addresses'),
                              ),
                              _divider(),
                              _item(
                                icon: Icons.lock_outline,
                                title: 'Keamanan Akun',
                                onTap: () => _safePushNamed('/security'),
                              ),
                            ]),

                            // Logout
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        title: const Text('Logout'),
                                        content: const Text('Keluar dari akun ini?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(context, false),
                                            child: const Text('Batal'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () => Navigator.pop(context, true),
                                            child: const Text('Logout'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (ok == true) {
                                      try {
                                        await maybeProvider<AuthProvider>(context)?.logout();
                                      } catch (e, st) {
                                        dev.log('logout error', error: e, stackTrace: st);
                                      }
                                      if (!mounted) return;
                                      try {
                                        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
                                      } catch (e, st) {
                                        dev.log('push /login error', error: e, stackTrace: st);
                                      }
                                    }
                                  },
                                  icon: const Icon(Icons.logout),
                                  label: const Text('Logout'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    side: const BorderSide(color: Colors.red),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
      ),
    );
  }
}

class _LoadingPlaceholder extends StatelessWidget {
  const _LoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 80),
        Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
        SizedBox(height: 16),
        Center(
          child: Text(
            'Memuat profil...',
            style: TextStyle(color: Colors.black54),
          ),
        ),
        SizedBox(height: 80),
      ],
    );
  }
}

class _EmptyStateProfile extends StatelessWidget {
  const _EmptyStateProfile();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 80),
        Center(child: Icon(Icons.person_outline, size: 48, color: Colors.black26)),
        SizedBox(height: 12),
        Center(
          child: Text(
            'Belum ada data profil.\nTarik ke bawah untuk memuat ulang.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
        ),
        SizedBox(height: 80),
      ],
    );
  }
}
