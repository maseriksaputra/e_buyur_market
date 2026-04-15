// lib/app/core/routes.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Screens
import '../presentation/screens/seller/seller_home_screen.dart';
import '../presentation/screens/buyer/buyer_home_entry.dart' as buyer_entry; // ⬅️ pakai alias
import '../presentation/screens/seller/seller_manage_products.dart'
    show SellerManageProductsScreen;

// ✅ Detail produk (seller) yang BARU
import '../presentation/screens/seller/seller_product_detail_screen.dart';

import '../presentation/screens/auth/register_screen.dart';
import '../presentation/screens/seller/seller_register_screen.dart';
// Provider & Service
import '../presentation/providers/seller_dashboard_provider.dart';
import '../core/services/product_api_service.dart';

class AppRoutes {
  static const String buyerHome = '/buyer/home';
  static const String sellerHome = '/seller/home';

  static const String sellerManageProducts = '/seller/manage-products';
  static const String sellerScanProduct    = '/seller/scan-product';
  static const String sellerAddProduct     = '/seller/add-product';
  static const String sellerOrders         = '/seller/orders';
  static const String sellerReports        = '/seller/reports';
  static const String sellerInventory      = '/seller/inventory';
  static const String sellerShipping       = '/seller/shipping';
  static const String sellerPromotions     = '/seller/promotions';
  static const String sellerSupport        = '/seller/support';

  static const String sellerProductDetail  = '/seller/product/detail';
  static const String sellerEditProduct    = '/seller/product/edit';

  static const String register       = '/auth/register';
  static const String sellerRegister = '/auth/seller-register';

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case buyerHome:
        return MaterialPageRoute(
          settings: settings,
          // ⬇️ panggil class yang benar dari buyer_home_entry.dart
          builder: (_) => buyer_entry.BuyerHomeEntry(),
        );

      case sellerHome:
        return MaterialPageRoute(
          settings: settings,
          builder: (ctx) {
            SellerDashboardProvider? existing;
            try {
              existing = ctx.read<SellerDashboardProvider>();
            } catch (_) {
              existing = null;
            }

            if (existing != null) {
              return ChangeNotifierProvider<SellerDashboardProvider>.value(
                value: existing,
                child: const SellerHomeScreen(),
              );
            } else {
              ProductApiService? svc;
              try {
                svc = ctx.read<ProductApiService>();
              } catch (_) {
                svc = ProductApiService();
              }
              return ChangeNotifierProvider(
                create: (_) => SellerDashboardProvider(svc!),
                child: const SellerHomeScreen(),
              );
            }
          },
        );

      case sellerManageProducts:
        return MaterialPageRoute(
          settings: settings,
          builder: (ctx) {
            try {
              final existing = ctx.read<SellerDashboardProvider>();
              return ChangeNotifierProvider<SellerDashboardProvider>.value(
                value: existing,
                child: const SellerManageProductsScreen(),
              );
            } catch (_) {
              ProductApiService? svc;
              try {
                svc = ctx.read<ProductApiService>();
              } catch (_) {
                svc = ProductApiService();
              }
              return ChangeNotifierProvider(
                create: (_) => SellerDashboardProvider(svc!),
                child: const SellerManageProductsScreen(),
              );
            }
          },
        );

      // ✅ DETAIL: gunakan screen baru, bukan bridge
      case sellerProductDetail:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const SellerProductDetailScreen(),
        );

      // ✳️ EDIT: sementara tetap bridge bila screen edit asli belum siap
      case sellerEditProduct:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const _SellerEditProductBridge(),
        );

      case register:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) {
            final args = (settings.arguments is Map)
                ? (settings.arguments as Map)
                : const {};
            final role = (args['role'] ?? 'buyer').toString();
            return _RegisterBridge(role: role);
          },
        );

      case sellerRegister:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const _RegisterBridge(role: 'seller'),
        );

      default:
        return null;
    }
  }
}

class _RegisterBridge extends StatelessWidget {
  const _RegisterBridge({super.key, required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Daftar (${role.toUpperCase()})')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Halaman Register (Bridge)'),
            const SizedBox(height: 8),
            Text('role: $role'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pushReplacementNamed(
                role == 'seller' ? AppRoutes.sellerHome : AppRoutes.buyerHome,
              ),
              child: const Text('Lanjut (dummy)'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SellerEditProductBridge extends StatelessWidget {
  const _SellerEditProductBridge({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;

    int? productId;
    Map<String, dynamic>? productMap;
    bool disableImage = false;

    if (args is Map) {
      productId = (args['id'] as num?)?.toInt();
      disableImage = args['disableImage'] == true;
      final p = args['product'];
      if (p is Map) productMap = Map<String, dynamic>.from(p);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Produk (Bridge)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: DefaultTextStyle(
          style: const TextStyle(fontSize: 14, color: Colors.black87),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Ini hanya BRIDGE sementara.',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('ID: ${productId ?? '-'}'),
              Text('disableImage: $disableImage'),
              const SizedBox(height: 8),
              const Text('Product (prefill):'),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$productMap'),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Kembali'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
