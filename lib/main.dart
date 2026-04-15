// lib/main.dart

// Dart & Flutter
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Packages
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:url_strategy/url_strategy.dart';

// Theme
import 'package:e_buyur_market_flutter_5/app/core/theme/app_theme.dart';

// Providers
import 'package:e_buyur_market_flutter_5/app/presentation/providers/auth_provider.dart';
import 'package:e_buyur_market_flutter_5/app/presentation/providers/cart_provider.dart';
import 'package:e_buyur_market_flutter_5/app/presentation/providers/product_provider.dart';
import 'package:e_buyur_market_flutter_5/app/presentation/providers/seller_provider.dart';
import 'package:e_buyur_market_flutter_5/app/presentation/providers/buyer_stats_provider.dart';
import 'package:e_buyur_market_flutter_5/app/presentation/providers/favorite_provider.dart';

// ✅ Pakai provider versi PRESENTATION (ini yang dipakai SellerHomeScreen/SellerDashboard)
import 'package:e_buyur_market_flutter_5/app/presentation/providers/seller_dashboard_provider.dart'
    as dash_p;

// ✅ Provider list produk seller (alias lama; tidak dipakai lagi di routes)
import 'package:e_buyur_market_flutter_5/app/presentation/providers/seller_products_provider.dart';
// ✅ NEW: CheckoutProvider di-root
import 'package:e_buyur_market_flutter_5/app/presentation/providers/checkout_provider.dart';

// ✅ Tambahan: service API untuk dipakai provider
import 'package:e_buyur_market_flutter_5/app/core/services/product_api_service.dart';

// ✅ Bootstrap Authorization dari token tersimpan
import 'package:e_buyur_market_flutter_5/app/presentation/auth/token_store.dart';

// Auth Screens
import 'package:e_buyur_market_flutter_5/app/presentation/screens/auth/login_screen.dart';
import 'package:e_buyur_market_flutter_5/app/presentation/screens/auth/register_screen.dart'
    show RegisterScreen;

// Common Screens
import 'package:e_buyur_market_flutter_5/app/presentation/screens/common/onboarding_screen.dart';
import 'package:e_buyur_market_flutter_5/app/presentation/screens/splash_screen.dart';

// Buyer Screens
import 'package:e_buyur_market_flutter_5/app/presentation/screens/buyer/buyer_dashboard.dart';
// ⬇️ Import dengan alias supaya aman dari tabrakan nama
import 'package:e_buyur_market_flutter_5/app/presentation/screens/buyer/product_detail_screen.dart'
    as buyer;
import 'package:e_buyur_market_flutter_5/app/presentation/screens/buyer/search/buyer_search_page.dart';
import 'package:e_buyur_market_flutter_5/app/presentation/screens/buyer/profile_screen.dart';
// ✅ Gunakan CartScreen YANG BENAR (bukan placeholder)
import 'package:e_buyur_market_flutter_5/app/presentation/screens/buyer/cart_screen.dart';
// ✅ Import layar checkout modern
import 'package:e_buyur_market_flutter_5/app/presentation/screens/buyer/checkout_screen.dart'
    show BuyerCheckoutScreen;

// Seller Screens
import 'package:e_buyur_market_flutter_5/app/presentation/screens/seller/seller_dashboard.dart';
import 'package:e_buyur_market_flutter_5/app/presentation/screens/seller/seller_register_screen.dart';
import 'package:e_buyur_market_flutter_5/app/presentation/screens/seller/create_product_from_scan_page.dart';
// ⬇️ Pakai alias "seller" agar aman (ada kelas SellerProductDetailScreen)
import 'package:e_buyur_market_flutter_5/app/presentation/screens/seller/product_detail_screen.dart'
    as seller;

// Models
import 'package:e_buyur_market_flutter_5/app/common/models/product_model.dart';

// ✅ AuthGate (role guard untuk halaman proteksi)
import 'package:e_buyur_market_flutter_5/app/common/widgets/auth_gate.dart';

// ⬇️ Tambahan penting: panggil ping AI via dart-define
import 'package:e_buyur_market_flutter_5/ml/hybrid_ai_service.dart';
import 'package:e_buyur_market_flutter_5/ml/hybrid_ai_dev_ping.dart';

// ✅ ✅ Tambahan (FITUR BARU “Produk Saya” yang benar)
import 'package:e_buyur_market_flutter_5/app/features/seller/screens/seller_manage_products_screen.dart';
import 'package:e_buyur_market_flutter_5/app/features/providers/seller_products_provider.dart'
    as features;

// ⬅️⬅️ Tambahkan alias import untuk core router agar tidak tabrakan dengan AppRoutes lokal
import 'package:e_buyur_market_flutter_5/app/core/routes.dart' as core;

// ✅ Tambahan agar bisa panggil API.init()
import 'package:e_buyur_market_flutter_5/app/core/network/api.dart' show API;

import 'dart:async'; // <-- untuk Future.sync

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 0) URL web tanpa '#'
  setPathUrlStrategy();

  // 1) Load .env (sebelum apa pun yang baca env) — PENTING
  await dotenv.load(fileName: ".env");

  // 1.a) Error hook (hindari white screen)
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
  };
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    // ignore: avoid_print
    print('Uncaught: $error\n$stack');
    return true;
  };

  // 🔐 Inisialisasi client API global (base URL + interceptors internal)
  // (Jika API.init() bertipe Future, pakai await; kalau sinkron, biarkan saja)
await Future.sync(() => API.init());

  // 1.1) Bootstrap TokenStore — pasang Authorization global jika ada token
  await TokenStore.bootstrap();

  // ✅ Pulihkan sesi TANPA memblokir frame pertama
  final auth = AuthProvider();
  unawaited(auth.tryRestoreSession());

  // 2) Lock portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // 3) System UI
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // 🔔 AI Ping optional via dart-define: --dart-define=AI_PING=true
  const doPing = bool.fromEnvironment('AI_PING', defaultValue: false);
  if (doPing) {
    await HybridAIDevPing.pingLog();
    // lanjut runApp agar app tetap jalan
  }

  // 4) Dio client (opsional untuk use-case legacy)
  final baseUrl = ApiConfig.baseUrl; // SELALU berakhiran '/'
  final bearer = dotenv.maybeGet('API_BEARER')?.trim();
  final headers = <String, String>{
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    if (bearer != null && bearer.isNotEmpty) 'Authorization': 'Bearer $bearer',
  };

  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl, // contoh: https://api.ebuyurmarket.com/api/
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: headers,
      validateStatus: (_) => true,
    ),
  )..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.next(options),
        onError: (e, handler) => handler.next(e),
      ),
    );

  // ✅ 4.1) Satu instance ProductApiService untuk DI
  final productApiService = ProductApiService();

  // 5) Root providers — MultiProvider HARUS di luar MaterialApp
  runApp(
    MultiProvider(
      providers: [
        // Dependencies / services
        Provider<Dio>.value(value: dio),
        Provider<ApiClient>(create: (_) => ApiClient(dio)),
        Provider<ProductApiService>.value(value: productApiService),

        // ✅ Auth hasil bootstrap dipakai sebagai provider global
        ChangeNotifierProvider<AuthProvider>.value(value: auth),

        // ✅ CartProvider global (biarkan constructor kosong sesuai project saat ini)
        ChangeNotifierProvider<CartProvider>(
          create: (_) => CartProvider(),
        ),

        // Provider lain tetap
        ChangeNotifierProvider<BuyerStatsProvider>(
          create: (_) => BuyerStatsProvider(),
        ),
        ChangeNotifierProvider<ProductProvider>(
          create: (_) => ProductProvider(),
        ),

        // ✅ Opsi A — CheckoutProvider memakai ApiClient.of(ctx).dio
        ChangeNotifierProvider<CheckoutProvider>(
          create: (_) => CheckoutProvider(),
        ),

        ChangeNotifierProvider<FavoriteProvider>(
          create: (_) => FavoriteProvider(),
        ),
        ChangeNotifierProvider<SellerProvider>(
          create: (_) => SellerProvider(baseUrl: ApiConfig.baseUrl),
        ),

        // ✅ Provider dashboard SELLER pakai PRESENTATION + DI ProductApiService
        ChangeNotifierProvider<dash_p.SellerDashboardProvider>(
          create: (ctx) =>
              dash_p.SellerDashboardProvider(ctx.read<ProductApiService>()),
        ),

        // ⬇️ Provider produk seller versi features (DI dengan ProductApiService)
        ChangeNotifierProvider<features.SellerProductsProvider>(
          create: (ctx) =>
              features.SellerProductsProvider(ctx.read<ProductApiService>()),
        ),
      ],
      // ⬇️ MaterialApp berada DI DALAM MultiProvider (bukan sebaliknya)
      child: const MyApp(),
    ),
  );
}

//// ROUTES

/// Pusat penamaan route agar konsisten (LOKAL ke main.dart)
/// *Tetap dibiarkan* untuk kompatibilitas dengan bagian app yang lain.
/// Core seller routes kini disediakan juga oleh lib/app/core/routes.dart (diimport sbg `core`).
class AppRoutes {
  // ⚠️ ubah splash ke '/splash' supaya '/' dipakai untuk resolver
  static const splash = '/splash';
  static const onboarding = '/onboarding';
  static const login = '/login';
  static const register = '/register';

  // Buyer
  static const buyerHome = '/buyer/home';
  static const cart = '/cart';
  static const profile = '/profile';
  static const history = '/history';
  static const buyerProductDtl = '/buyer-product-detail';

  // Buyer Search
  static const buyerSearch = '/buyer/search';

  // Edit Profil
  static const buyerProfileEdit = '/buyer/profile/edit';

  // Seller
  static const sellerHome = '/seller/home';
  static const sellerRegister = '/seller-register';
  static const sellerProducts = '/seller-products';
  static const sellerAdd = '/seller-add-product';
  static const sellerOrders = '/seller-orders';
  static const sellerProfile = '/seller-profile';
  static const createFromScan = '/create-from-scan';
  static const sellerProductDetail = '/seller/product/detail';

  // Publik lain
  static const products = '/products';

  // Legacy aliases (ditangani di onGenerateRoute)
  static const _legacyBuyerDash = '/buyer-dashboard';
  static const _legacySellerDash = '/seller-dashboard';
  static const _legacySellerReg = '/seller/register';
  static const _legacyHome = '/home';
}

class ApiConfig {
  static String get baseUrl {
    final candidates = [
      dotenv.maybeGet('API_BASE_URL'),
      dotenv.maybeGet('API_BASE'),
      dotenv.maybeGet('API_ROOT'),
      dotenv.maybeGet('API_ROOT_WEB'),
    ]
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);

    final fromEnv = candidates.isNotEmpty ? candidates.first : null;
    final chosen = fromEnv ?? _defaultBaseUrl();
    // ✅ pastikan SELALU berakhiran '/'
    return chosen.replaceFirst(RegExp(r'/+$'), '') + '/';
  }

  static String _defaultBaseUrl() {
    // ✅ tambahkan '/' di akhir agar aman
    if (kIsWeb) return 'http://127.0.0.1:8000/api/v1/';
    return 'http://127.0.0.1:8000/api/v1/';
  }
}

class ApiClient {
  final Dio dio;
  ApiClient(this.dio);

  // ✅ path TANPA leading slash agar tidak menimpa baseUrl
  Future<Response> getProducts() => dio.get('products');
  Future<Response> getProductDetail(String id) => dio.get('products/$id');

  // Opsional: gaya snippet `ApiClient.of(ctx)` (helper singkat)
  static ApiClient of(BuildContext ctx) =>
      Provider.of<ApiClient>(ctx, listen: false);
}

Future<http.Response> exampleFetchWithHttp() async {
  // ✅ hindari '//' ganda
  final url = '${ApiConfig.baseUrl}products';
  return http.get(Uri.parse(url));
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'E-Buyur Market',
      debugShowCheckedModeBanner: false,

      // ErrorWidget builder supaya error tidak jadi layar putih
      builder: (context, child) {
        ErrorWidget.builder = (FlutterErrorDetails details) {
          return Scaffold(
            appBar: AppBar(title: const Text('Terjadi Kesalahan')),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Text(details.exceptionAsString()),
            ),
          );
        };
        return child!;
      },

      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,

      // ⬇️ Start di resolver (bisa kamu ganti ke core.AppRoutes.sellerHome kalau mau)
      initialRoute: '/',

      routes: {
        // ===== Resolver root =====
        '/': (_) => const _RouteResolver(), // CHANGED: pakai lastRoute

        // Publik / Auth
        AppRoutes.splash: (_) => const SplashScreen(),
        AppRoutes.onboarding: (_) => const OnboardingScreen(),
        AppRoutes.login: (_) => const LoginScreen(),
        AppRoutes.register: (_) => const RegisterScreen(),

        // ===== Buyer protected =====
        AppRoutes.buyerHome: (_) => AuthGate(
              requiredRole: 'buyer',
              // NEW: simpan "beranda terakhir" otomatis
              child: const _RememberRoute(
                routeName: AppRoutes.buyerHome,
                child: BuyerDashboard(),
              ),
            ),

        // ✅ Route cart menunjuk ke CartScreen YANG BENAR (tanpa const di AuthGate)
        AppRoutes.cart: (_) =>
            AuthGate(requiredRole: 'buyer', child: CartScreen()),

        AppRoutes.profile: (_) =>
            AuthGate(requiredRole: 'buyer', child: const ProfilePage()),
        AppRoutes.history: (_) =>
            AuthGate(requiredRole: 'buyer', child: const OrderHistoryPage()),
        AppRoutes.buyerProfileEdit: (_) => AuthGate(
              requiredRole: 'buyer',
              child: const EditProfileScreen(),
            ),
        AppRoutes.buyerSearch: (_) => const BuyerSearchPage(),

        // ✅ Tambahan rute checkout modern + success (sesuai snippet)
        '/checkout': (_) => const BuyerCheckoutScreen(),
        '/order-success': (_) => const _OrderSuccessPage(),

        // ===== Seller protected =====
        AppRoutes.sellerHome: (_) => AuthGate(
              requiredRole: 'seller',
              child: const _RememberRoute(
                routeName: AppRoutes.sellerHome,
                child: SellerDashboard(),
              ),
            ),
        AppRoutes.sellerRegister: (_) => const SellerRegisterScreen(), // publik

        // ⬇️ GANTI ke layar “Produk Saya” yang benar
        AppRoutes.sellerProducts: (_) => AuthGate(
              requiredRole: 'seller',
              child: const SellerManageProductsScreen(),
            ),

        AppRoutes.sellerAdd: (_) =>
            AuthGate(requiredRole: 'seller', child: const AddProductPage()),
        AppRoutes.sellerOrders: (_) =>
            AuthGate(requiredRole: 'seller', child: const SellerOrdersPage()),
        AppRoutes.sellerProfile: (_) =>
            AuthGate(requiredRole: 'seller', child: const SellerProfilePage()),
        AppRoutes.createFromScan: (_) => AuthGate(
              requiredRole: 'seller',
              child: const CreateProductFromScanPage(),
            ),
        AppRoutes.sellerProductDetail: (_) => AuthGate(
              requiredRole: 'seller',
              // ⬇️ Tetap pakai alias seller.
              child: seller.SellerProductDetailScreen(),
            ),

        // Publik lain
        AppRoutes.products: (_) => const ProductListPage(),

        // ====== Alias /buyer dan /seller ======
        '/buyer': (_) => AuthGate(
              requiredRole: 'buyer',
              child: const _RememberRoute(
                routeName: AppRoutes.buyerHome,
                child: BuyerDashboard(),
              ),
            ),

        // ✅ Alias lama diarahkan ke CartScreen yang benar (tanpa const di AuthGate)
        '/buyer/cart': (_) =>
            AuthGate(requiredRole: 'buyer', child: CartScreen()),
        '/buyer/profile': (_) =>
            AuthGate(requiredRole: 'buyer', child: const ProfilePage()),
        '/buyer/orders': (_) =>
            AuthGate(requiredRole: 'buyer', child: const OrderHistoryPage()),

        '/seller': (_) => AuthGate(
              requiredRole: 'seller',
              child: const _RememberRoute(
                routeName: AppRoutes.sellerHome,
                child: SellerDashboard(),
              ),
            ),

        // ⬇️ GANTI alias lama juga → layar manajemen yang benar
        '/seller/products': (_) => AuthGate(
              requiredRole: 'seller',
              child: const SellerManageProductsScreen(),
            ),
        '/seller/add': (_) =>
            AuthGate(requiredRole: 'seller', child: const AddProductPage()),
        '/seller/orders': (_) =>
            AuthGate(requiredRole: 'seller', child: const SellerOrdersPage()),
        '/seller/create-from-scan': (_) => AuthGate(
              requiredRole: 'seller',
              child: const CreateProductFromScanPage(),
            ),
      },

      // 🔴🔴 PENTING: gunakan core router dulu → jika null, fallback ke handler lama
      onGenerateRoute: (settings) {
        final r = core.AppRoutes.onGenerateRoute(settings);
        if (r != null) return r;

        // ----- ALIAS LEGACY (fallback lama) -----
        switch (settings.name) {
          case AppRoutes._legacyBuyerDash:
            return MaterialPageRoute(
              builder: (_) => const BuyerDashboard(),
              settings: const RouteSettings(name: AppRoutes.buyerHome),
            );
          case AppRoutes._legacySellerDash:
            return MaterialPageRoute(
              builder: (_) => const SellerDashboard(),
              settings: const RouteSettings(name: AppRoutes.sellerHome),
            );
          case AppRoutes._legacySellerReg:
            return MaterialPageRoute(
              builder: (_) => const SellerRegisterScreen(),
              settings: const RouteSettings(name: AppRoutes.sellerRegister),
            );
          case AppRoutes._legacyHome:
            return MaterialPageRoute(
              builder: (_) => const BuyerDashboard(),
              settings: const RouteSettings(name: AppRoutes.buyerHome),
            );
        }

        // ----- Dynamic pages (argumen) -----
        if (settings.name == AppRoutes.buyerProductDtl) {
          final p = settings.arguments as Product;
          return MaterialPageRoute(
            builder: (_) => buyer.BuyerProductDetailScreen(product: p),
            settings: settings,
          );
        }

        if (settings.name == '/product-detail') {
          final product = settings.arguments as Product;
          return MaterialPageRoute(
            builder: (_) => buyer.BuyerProductDetailScreen(product: product),
            settings: settings,
          );
        }

        if (settings.name == '/order-detail') {
          final orderId = settings.arguments as String;
          return MaterialPageRoute(
            builder: (_) => OrderDetailPage(orderId: orderId),
            settings: settings,
          );
        }

        if (settings.name == '/edit-product') {
          final product = settings.arguments as Product;
          return MaterialPageRoute(
            builder: (_) => EditProductPage(product: product),
            settings: settings,
          );
        }

        // biarkan null → lanjut ke onUnknownRoute
        return null;
      },

      // ⬇️ jika route tidak dikenal, arahkan sesuai role/lastRoute (bukan 404)
      onUnknownRoute: (settings) =>
          MaterialPageRoute(builder: (_) => const _RouteResolver()),
    );
  }
}

// ======= Route Resolver: '/' & fallback unknown route =======
class _RouteResolver extends StatelessWidget {
  const _RouteResolver({super.key});
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    // Tahan navigasi sampai init selesai supaya tidak flicker
    if (auth.isInitializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // ✅ Navigasi berdasarkan isAuthenticated (tanpa 'return' di dalam callback)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;

      // Tentukan tujuan sekali
      String dest;
      if (!auth.isAuthenticated) {
        dest = AppRoutes.login;
      } else {
        final last = auth.lastRoute;
        if (last != null && last.isNotEmpty) {
          dest = last;
        } else {
          final role = (auth.userRole ?? auth.role ?? '').toLowerCase();
          dest = role == 'seller' ? AppRoutes.sellerHome : AppRoutes.buyerHome;
        }
      }

      // Hindari push berulang kalau sudah di route yang sama
      final current = ModalRoute.of(context)?.settings.name;
      if (current != dest) {
        Navigator.of(context).pushReplacementNamed(dest);
      }
    });

    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

// =======================
// Home + Search section (placeholder demo)
// =======================

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              elevation: 0,
              backgroundColor: Colors.green,
              expandedHeight: 60,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: EdgeInsets.zero,
                title: Container(
                  height: 60,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                      const SizedBox(width: 12),
                      const Text(
                        'E-Buyur Market',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.shopping_cart_outlined,
                            color: Colors.white),
                        onPressed: () =>
                            Navigator.pushNamed(context, AppRoutes.cart),
                      ),
                      IconButton(
                        icon: const Icon(Icons.person_outline,
                            color: Colors.white),
                        onPressed: () =>
                            Navigator.pushNamed(context, AppRoutes.profile),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Search box
            SliverToBoxAdapter(
              child: GestureDetector(
                onTap: () => Navigator.of(context, rootNavigator: true)
                    .pushNamed(AppRoutes.buyerSearch),
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search, color: Colors.grey[400], size: 20),
                      const SizedBox(width: 12),
                      Text('Cari buah dan sayur segar...',
                          style:
                              TextStyle(color: Colors.grey[400], fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ),

            // Promo
            SliverToBoxAdapter(
              child: Container(
                height: 150,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: PageView(
                  children: [
                    _buildPromoBanner('Promo Banner 1', const Color(0xFF4CAF50)),
                    _buildPromoBanner('Promo Banner 2', const Color(0xFF8BC34A)),
                  ],
                ),
              ),
            ),

            // Section title
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Produk Terbaru',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A)),
                    ),
                    TextButton(
                      onPressed: () =>
                          Navigator.pushNamed(context, AppRoutes.products),
                      child: const Text('Lihat Semua',
                          style: TextStyle(fontSize: 13, color: Colors.green)),
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(
              child: SizedBox(
                height: 200,
                child: Center(
                  child: Text('Products will be loaded here',
                      style: TextStyle(color: Colors.grey, fontSize: 16)),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),

      // Bottom nav
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, -2))
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) {
            setState(() => _selectedIndex = index);
            _handleNavigation(index);
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: Colors.green,
          unselectedItemColor: Colors.grey,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          items: const [
            BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home),
                label: 'Beranda'),
            BottomNavigationBarItem(
                icon: Icon(Icons.search_outlined),
                activeIcon: Icon(Icons.search),
                label: 'Cari'),
            BottomNavigationBarItem(
                icon: Icon(Icons.shopping_cart_outlined),
                activeIcon: Icon(Icons.shopping_cart),
                label: 'Keranjang'),
            BottomNavigationBarItem(
                icon: Icon(Icons.history_outlined),
                activeIcon: Icon(Icons.history),
                label: 'Riwayat'),
            BottomNavigationBarItem(
                icon: Icon(Icons.person_outline),
                activeIcon: Icon(Icons.person),
                label: 'Profil'),
          ],
        ),
      ),
    );
  }

  Widget _buildPromoBanner(String text, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
          color: color.withOpacity(0.3),
          borderRadius: BorderRadius.circular(16)),
      child: Center(
          child: Text(text,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: color))),
    );
  }

  void _handleNavigation(int index) {
    switch (index) {
      case 0:
        break;
      case 1:
        Navigator.of(context, rootNavigator: true)
            .pushNamed(AppRoutes.buyerSearch);
        break;
      case 2:
        Navigator.pushNamed(context, AppRoutes.cart);
        break;
      case 3:
        Navigator.pushNamed(context, AppRoutes.history);
        break;
      case 4:
        Navigator.pushNamed(context, AppRoutes.profile);
        break;
    }
  }
}

// =======================
// Placeholder SearchPage (boleh dibiarkan)
// =======================

class SearchPage extends StatefulWidget {
  const SearchPage({Key? key}) : super(key: key);
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'Semua';
  bool _isGridView = true;

  final List<String> _categories = [
    'Semua',
    'Sayuran',
    'Buah',
    'Organik',
    'Diskon'
  ];
  final List<String> _popularSearches = [
    'Apel',
    'Pisang',
    'Wortel',
    'Tomat',
    'Jeruk',
    'Bayam',
    'Brokoli',
    'Kentang'
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Column(
          children: const [
            // (konten search dipersingkat)
          ],
        ),
      ),
    );
  }
}

// =======================
// Placeholder pages
// =======================

class ProductListPage extends StatelessWidget {
  const ProductListPage({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daftar Produk')),
      body: const Center(child: Text('Product List Page - Coming Soon')),
    );
  }
}

// ❌ CartPage placeholder DIHAPUS — gunakan CartScreen dari cart_screen.dart

class ProfilePage extends StatelessWidget {
  const ProfilePage({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('Profil')),
        body: const Center(child: Text('Profile Page - Coming Soon')));
  }
}

class OrderHistoryPage extends StatelessWidget {
  const OrderHistoryPage({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('Riwayat Pesanan')),
        body: const Center(child: Text('Order History - Coming Soon')));
  }
}

class SellerProductsPage extends StatelessWidget {
  const SellerProductsPage({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('Produk Saya')),
        body: const Center(child: Text('Seller Products - Coming Soon')));
  }
}

class AddProductPage extends StatelessWidget {
  const AddProductPage({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('Tambah Produk')),
        body: const Center(child: Text('Add Product - Coming Soon')));
  }
}

class EditProductPage extends StatelessWidget {
  final Product product;
  const EditProductPage({Key? key, required this.product}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text('Edit ${product.name}')),
        body: const Center(child: Text('Edit Product - Coming Soon')));
  }
}

class SellerOrdersPage extends StatelessWidget {
  const SellerOrdersPage({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('Pesanan Masuk')),
        body: const Center(child: Text('Seller Orders - Coming Soon')));
  }
}

class SellerProfilePage extends StatelessWidget {
  const SellerProfilePage({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('Profil Toko')),
        body: const Center(child: Text('Seller Profile - Coming Soon')));
  }
}

class OrderDetailPage extends StatelessWidget {
  final String orderId;
  const OrderDetailPage({Key? key, required this.orderId}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text('Order #$orderId')),
        body: const Center(child: Text('Order Detail - Coming Soon')));
  }
}

// =======================
// EditProfile placeholder
// =======================

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({Key? key}) : super(key: key);

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameC;
  late final TextEditingController _emailC;
  late final TextEditingController _phoneC;

  @override
  void initState() {
    super.initState();
    _nameC = TextEditingController();
    _emailC = TextEditingController();
    _phoneC = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      _nameC.text = '${args['name'] ?? ''}';
      _emailC.text = '${args['email'] ?? ''}';
      _phoneC.text = '${args['phone'] ?? args['hp'] ?? args['no_hp'] ?? ''}';
    }
  }

  @override
  void dispose() {
    _nameC.dispose();
    _emailC.dispose();
    _phoneC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profil')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameC,
              decoration: const InputDecoration(labelText: 'Nama'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Nama wajib diisi' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailC,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Email wajib diisi';
                final ok = RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v.trim());
                return ok ? null : 'Format email tidak valid';
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneC,
              decoration: const InputDecoration(labelText: 'No. HP (opsional)'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                if (_formKey.currentState?.validate() ?? false) {
                  Navigator.pop(context, {
                    'name': _nameC.text.trim(),
                    'email': _emailC.text.trim(),
                    'phone': _phoneC.text.trim(),
                  });
                }
              },
              icon: const Icon(Icons.save),
              label: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }
}

/// =======================
/// NEW: Wrapper kecil untuk menyimpan "beranda terakhir"
/// Dipakai di route buyer/seller agar selalu tercatat saat halaman dibuka.
/// =======================
class _RememberRoute extends StatefulWidget {
  final String routeName;
  final Widget child;
  const _RememberRoute(
      {super.key, required this.routeName, required this.child});

  @override
  State<_RememberRoute> createState() => _RememberRouteState();
}

class _RememberRouteState extends State<_RememberRoute> {
  bool _done = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_done) return;
    _done = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AuthProvider>().rememberLastRoute(widget.routeName);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// =======================
/// NEW: Halaman sukses sederhana untuk '/order-success'
/// =======================
class _OrderSuccessPage extends StatelessWidget {
  const _OrderSuccessPage({super.key});
  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    return Scaffold(
      appBar: AppBar(title: const Text('Pesanan Berhasil')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, size: 72, color: Colors.green),
              const SizedBox(height: 12),
              const Text('Terima kasih! Pesanan kamu sudah dibuat.',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                args is Map && args.isNotEmpty
                    ? 'Order: ${args['order_code'] ?? args['order_id'] ?? '-'}'
                    : 'Order diproses.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, AppRoutes.history),
                icon: const Icon(Icons.receipt_long),
                label: const Text('Lihat Riwayat Pesanan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
