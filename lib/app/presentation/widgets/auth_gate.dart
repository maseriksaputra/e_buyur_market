import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../presentation/providers/auth_provider.dart';
import '../../core/routes.dart'; // berisi AppRoutes.buyerHome & sellerHome

class AuthGate extends StatefulWidget {
  final Widget child; // halaman saat sudah di tempat yang benar
  const AuthGate({super.key, required this.child});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _redirecting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeRedirect();
  }

  Future<void> _maybeRedirect() async {
    if (_redirecting) return;
    final ap = context.read<AuthProvider>();

    // contoh: jika belum login → ke login
    if (ap.user == null) {
      _redirecting = true;
      Future.microtask(() =>
        Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (r) => false)
      );
      return;
    }

    // kalau kamu bedakan shell buyer/seller, kamu bisa cek route saat ini
    // atau cukup biarkan widget.child tampil (gate dipakai di root masing2 shell)
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
