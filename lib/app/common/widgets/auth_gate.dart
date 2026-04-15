// lib/app/common/widgets/auth_gate.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/providers/auth_provider.dart';
import '../../../main.dart' show AppRoutes;

class AuthGate extends StatelessWidget {
  final String? requiredRole; // 'buyer' / 'seller' / null (hanya perlu login)
  final Widget child;

  const AuthGate({
    Key? key,
    this.requiredRole,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    // Saat restore session awal
    if (auth.isInitializing) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Belum login -> lempar ke login
    if (!auth.isAuthenticated) {
      // Pakai addPostFrameCallback agar tidak nabrak build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context, rootNavigator: true)
            .pushNamedAndRemoveUntil(AppRoutes.login, (r) => false);
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Sudah login: cek role bila diminta
    final effRole = auth.effectiveRole; // 'buyer' / 'seller'
    if (requiredRole != null && requiredRole!.isNotEmpty) {
      final need = requiredRole!.toLowerCase().trim();
      if (effRole != need) {
        // Arahkan ke rumah sesuai role yang benar
        final target =
            (effRole == 'seller') ? AppRoutes.sellerHome : AppRoutes.buyerHome;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.of(context, rootNavigator: true)
              .pushNamedAndRemoveUntil(target, (r) => false);
        });
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }
    }

    // Lolos semua -> tampilkan konten
    return child;
  }
}
