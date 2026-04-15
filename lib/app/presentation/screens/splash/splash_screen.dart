// lib/app/presentation/screens/splash/splash_screen.dart
@override
void initState() {
  super.initState();
  Future.microtask(() async {
    final auth = context.read<AuthProvider>();
    await auth.init();
    if (!mounted) return;
    final route = auth.isAuthenticated
        ? (auth.effectiveRole == 'seller' ? AppRoutes.sellerHome : AppRoutes.buyerHome)
        : AppRoutes.login;
    Navigator.of(context).pushNamedAndRemoveUntil(route, (r) => false);
  });
}
