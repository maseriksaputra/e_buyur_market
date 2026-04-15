import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:e_buyur_market_flutter_5/app/presentation/providers/auth_provider.dart';

class AuthGate extends StatefulWidget {
  final Widget Function(BuildContext ctx) loginBuilder;  // halaman login
  final Widget Function(BuildContext ctx) splashBuilder; // splash mungil saat bootstrap
  final Widget Function(BuildContext ctx) homeBuilder;   // fallback home buyer

  const AuthGate({
    super.key,
    required this.loginBuilder,
    required this.splashBuilder,
    required this.homeBuilder,
  });

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _redirected = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final auth = context.read<AuthProvider>();

    // === Bootstrap session ===
    // Kompat lama: AuthProvider punya isInitializing + tryRestoreSession()
    if (auth.isInitializing) {
      try {
        await auth.tryRestoreSession();
      } catch (_) {}
    }

    // === Optional redirect ke lastRoute (jika ada di provider kamu) ===
    if (!mounted) return;

    // Baca lastRoute secara dinamis (tidak wajib ada di provider)
    String? lastRoute;
    try {
      lastRoute = (auth as dynamic).lastRoute as String?;
    } catch (_) {
      lastRoute = null; // provider lama tidak punya lastRoute
    }

    // Jika sudah login & ada lastRoute → arahkan sekali
    if (!_redirected && auth.isAuthenticated && lastRoute != null && lastRoute.isNotEmpty) {
      _redirected = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil(lastRoute!, (r) => false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (_, auth, __) {
        // Saat masih init → tampilkan splash
        if (auth.isInitializing) {
          return widget.splashBuilder(context);
        }

        // Belum login → ke halaman login
        if (!auth.isAuthenticated) {
          return widget.loginBuilder(context);
        }

        // Sudah login, tapi belum diarahkan khusus → fallback home
        return widget.homeBuilder(context);
      },
    );
  }
}
