// lib/app/presentation/widgets/seller_bottom_nav_bar.dart
import 'package:flutter/material.dart';

/// Bottom nav seller yang ringkas, tanpa dependensi eksternal.
/// - Hindari bug baris (line) yang sering muncul karena kurung/komma
/// - currentIndex di-clamp agar tidak out-of-range
/// - onTap: jika tidak disediakan, akan navigate via named routes default
///
/// ROUTES DEFAULT (ubah sesuai rute milikmu):
/// 0 => '/seller/home'
/// 1 => '/seller/orders'
/// 2 => '/seller/products'
/// 3 => '/seller/profile'
class SellerBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int>? onTap;

  const SellerBottomNavBar({
    super.key,
    this.currentIndex = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Pastikan index selalu valid (0..3)
    final int idx = currentIndex.clamp(0, 3);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).bottomNavigationBarTheme.backgroundColor ??
            Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(0.6),
            width: 0.6,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: idx,
          showUnselectedLabels: true,
          landscapeLayout: BottomNavigationBarLandscapeLayout.centered,
          onTap: (i) {
            // Jika parent ingin override (mis. stateful nav), hormati itu.
            if (onTap != null) {
              onTap!(i);
              return;
            }
            if (i == idx) return;

            // >>> SESUAIKAN route name di bawah kalau berbeda <<<
            String target = switch (i) {
              0 => '/seller/home',
              1 => '/seller/orders',
              2 => '/seller/products',
              _ => '/seller/profile',
            };

            // Gunakan pushReplacement agar stack tidak menumpuk.
            Navigator.of(context).pushReplacementNamed(target);
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Beranda',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long_outlined),
              activeIcon: Icon(Icons.receipt_long),
              label: 'Pesanan',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.inventory_2_outlined),
              activeIcon: Icon(Icons.inventory_2),
              label: 'Produk',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Profil',
            ),
          ],
        ),
      ),
    );
  }
}
