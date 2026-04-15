// lib/app/presentation/screens/seller/seller_dashboard.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart' as theme;

import 'seller_home_screen.dart' show SellerHomeScreen;
import 'seller_manage_products.dart' show SellerManageProductsScreen;
import 'seller_history_screen.dart' show SellerHistoryScreen;
import 'seller_scan_screen.dart' show ScanScreen;
import 'seller_profile_screen.dart' show SellerProfileScreen; // ✅ FIX: hapus tanda kutip ekstra

// Providers
import '../../providers/auth_provider.dart';
import '../../providers/seller_provider.dart';
import '../../providers/seller_dashboard_provider.dart';

class SellerDashboard extends StatefulWidget {
  const SellerDashboard({Key? key}) : super(key: key);

  @override
  State<SellerDashboard> createState() => _SellerDashboardState();
}

class _SellerDashboardState extends State<SellerDashboard> {
  int _index = 0;

  // Urutan: Beranda, Kelola, Scan (tengah), Riwayat, Profil
  final _pages = const [
    SellerHomeScreen(),
    SellerManageProductsScreen(),
    ScanScreen(),
    SellerHistoryScreen(),
    SellerProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();

    // ⬇⬇ Defer akses ke provider agar aman dari "during build"
    Future.microtask(() async {
      if (!mounted) return;

      final ap = context.read<AuthProvider>();
      final token = ap.token;

      // Set token ke semua provider yang perlu Authorization
      final sellerProv = context.read<SellerProvider>();
      final dash = context.read<SellerDashboardProvider>();
      sellerProv.setAuthToken(token);
      dash.setAuthToken(token);

      // Jika dashboard/stack ini juga memunculkan angka/daftar, load di sini
      await Future.wait([
        sellerProv.refreshProducts(page: 1),
        dash.loadDashboard(),
      ]);
    });
  }

  void _onTap(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),

      // === GANTI NavigationBar bawaan dengan nav kustom ala buyer ===
      bottomNavigationBar: SellerBottomNav(
        currentIndex: _index,
        onTap: _onTap,
      ),
    );
  }
}

/// ===================================================================
/// BottomNav kustom: selaras dengan buyer (ikon & label hijau, lingkaran
/// highlight, animasi scale, Scan di tengah)
/// ===================================================================
class SellerBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const SellerBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final items = <_NavItemData>[
      const _NavItemData(
        label: 'Beranda',
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
      ),
      const _NavItemData(
        label: 'Kelola',
        icon: Icons.inventory_2_outlined,
        selectedIcon: Icons.inventory_2,
      ),
      const _NavItemData(
        label: 'Scan',
        icon: Icons.qr_code_scanner_outlined,
        selectedIcon: Icons.qr_code_scanner,
        isCenter: true, // tengah
      ),
      const _NavItemData(
        label: 'Riwayat',
        icon: Icons.history,
        selectedIcon: Icons.history_rounded,
      ),
      const _NavItemData(
        label: 'Profil',
        icon: Icons.person_outline,
        selectedIcon: Icons.person,
      ),
    ];

    return SafeArea(
      top: false,
      child: Container(
        height: 68,
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(
            top: BorderSide(color: Color(0xFFECECEC)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: List.generate(items.length, (i) {
            final data = items[i];
            final selected = i == currentIndex;
            return Expanded(
              child: _NavItem(
                data: data,
                selected: selected,
                onTap: () => onTap(i),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _NavItemData {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool isCenter;
  const _NavItemData({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.isCenter = false,
  });
}

class _NavItem extends StatelessWidget {
  final _NavItemData data;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // gaya buyer: hijau saat selected, abu saat tidak
    final activeColor = theme.AppColors.primaryGreen;
    final inactiveColor = Colors.grey[600];

    // center (Scan) diberi lingkaran lebih besar
    final bgSize = data.isCenter ? 44.0 : 36.0;
    final iconSize = data.isCenter ? 26.0 : 22.0;

    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // background lingkaran + icon dengan animasi
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: bgSize,
            height: bgSize,
            decoration: BoxDecoration(
              color: selected ? activeColor.withOpacity(0.12) : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: AnimatedScale(
                duration: const Duration(milliseconds: 200),
                scale: selected ? 1.0 : 0.96,
                curve: Curves.easeOut,
                child: Icon(
                  selected ? data.selectedIcon : data.icon,
                  size: iconSize,
                  color: selected ? activeColor : inactiveColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? activeColor : inactiveColor,
            ),
            child: Text(data.label),
          ),
        ],
      ),
    );
  }
}
