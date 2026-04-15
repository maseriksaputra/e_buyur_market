// lib/app/presentation/screens/splash/splash_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:e_buyur_market_flutter_5/app/presentation/providers/auth_provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with WidgetsBindingObserver {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Non-blocking boot — jangan tunggu jaringan
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Jika app balik dari background dan belum sempat navigate, lanjutkan
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_navigated) {
      _gotoNext(); // tidak blocking
    }
  }

  Future<void> _boot() async {
    // Splash minimal 600ms agar transisi halus
    final minShow = Future.delayed(const Duration(milliseconds: 600));

    // Jalankan init/restore di background dengan batas waktu (non-blocking)
    final initOrTimeout = Future(() async {
      final auth = context.read<AuthProvider>() as dynamic;

      // Coba direct dynamic call (lebih aman)
      try { final r = (auth).init(); if (r is Future) await r; } catch (_) {}
      try { final r = (auth).tryRestoreSession(); if (r is Future) await r; } catch (_) {}
      try { final r = (auth).restore(); if (r is Future) await r; } catch (_) {}

      // Opsi kompat: paksa via noSuchMethod bila provider override (akan diabaikan kalau tidak ada)
      try {
        final res = Function.apply(
          (auth as dynamic).noSuchMethod,
          [Invocation.method(#tryRestoreSession, const [])],
        );
        if (res is Future) await res;
      } catch (_) {}
    });

    // Batasi total tunggu agar tidak "stuck" di logo
    await Future.any([
      initOrTimeout,
      Future.delayed(const Duration(milliseconds: 2500)),
    ]);

    await minShow;
    if (!mounted) return;
    _gotoNext();
  }

  void _gotoNext() {
    if (_navigated || !mounted) return;
    _navigated = true;

    final auth = context.read<AuthProvider>() as dynamic;

    final loggedIn = _boolOrFalse(auth.isAuthenticated) ||
        (auth.token is String && (auth.token as String).isNotEmpty);

    final role = (auth.role ?? (auth.user?.role ?? 'buyer')).toString();

    // Sesuaikan nama rute dengan yang kamu pakai
    final route = loggedIn
        ? (role == 'seller' ? '/seller/home' : '/buyer/home')
        : '/login';

    Navigator.of(context).pushReplacementNamed(route);
  }

  bool _boolOrFalse(dynamic v) => v is bool ? v : false;

  @override
  Widget build(BuildContext context) {
    // Splash UI tetap seperti versi kamu
    return Scaffold(
      backgroundColor: const Color(0xFF06923E),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Image(
              image: AssetImage('assets/images/e_buyur_logo.png'),
              width: 120,
              height: 120,
            ),
            SizedBox(height: 24),
            Text(
              'E-Buyur Market',
              style: TextStyle(
                color: Colors.white,
                fontSize: 42,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            CircularProgressIndicator(color: Colors.white),
          ],
        ),
      ),
    );
  }
}
