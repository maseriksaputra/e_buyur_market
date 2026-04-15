// lib/app/presentation/screens/auth/login_screen.dart
import 'package:dio/dio.dart'; // untuk DioException
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;

import 'package:e_buyur_market_flutter_5/app/presentation/providers/auth_provider.dart';
import 'package:e_buyur_market_flutter_5/app/core/theme/app_colors.dart';
import 'package:e_buyur_market_flutter_5/app/core/routes.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailC = TextEditingController();
  final _passC = TextEditingController();

  bool _isPasswordVisible = false;
  bool _didInitFromArgs = false;
  bool _rememberMe = false;
  bool _isBuyerTab = true;

  @override
  void initState() {
    super.initState();
    _loadRemembered();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitFromArgs) return;
    _didInitFromArgs = true;

    final route = ModalRoute.of(context);
    final args = (route?.settings.arguments is Map)
        ? (route!.settings.arguments as Map)
        : const {};
    final roleArg = (args['role'] ?? args['initialRole'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    final routeName = (route?.settings.name ?? '').toLowerCase();

    if (roleArg == 'seller' || routeName.contains('seller')) {
      setState(() => _isBuyerTab = false);
    }
  }

  Future<void> _loadRemembered() async {
    final sp = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _rememberMe = sp.getBool('remember_me') ?? false;
      _emailC.text = sp.getString('remember_email') ?? '';
    });
  }

  @override
  void dispose() {
    _emailC.dispose();
    _passC.dispose();
    super.dispose();
  }

  void _snack(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  String _extractServerMessage(dynamic data) {
    try {
      if (data is Map) {
        // Prefer detail validasi
        final errMap = data['error'];
        if (errMap is Map) {
          final details = errMap['details'];
          if (details != null && details.toString().trim().isNotEmpty) {
            return details.toString();
          }
          final msg = errMap['message'];
          if (msg is String && msg.isNotEmpty) return msg;
        }
        // Laravel style: { errors: { field: [msg] } }
        final errors = data['errors'];
        if (errors is Map && errors.isNotEmpty) {
          final first = errors.values.first;
          if (first is List && first.isNotEmpty) return first.first.toString();
          return first.toString();
        }
        // Generic message
        final msg = data['message'];
        if (msg is String && msg.isNotEmpty) return msg;
      } else if (data is String && data.trim().isNotEmpty) {
        return data;
      }
    } catch (_) {}
    return 'Validasi gagal';
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final auth = context.read<AuthProvider>();
    final role = _isBuyerTab ? 'buyer' : 'seller'; // ✅ selalu kirim role sesuai tab

    try {
      await auth.login(
        email: _emailC.text.trim(),
        password: _passC.text,
        role: role,
      );

      // simpan “ingat saya”
      final sp = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await sp.setBool('remember_me', true);
        await sp.setString('remember_email', _emailC.text.trim());
      } else {
        await sp.remove('remember_me');
        await sp.remove('remember_email');
      }

      if (!mounted) return;

      // Opsional: segarkan profil (kalau perlu sinkron role dari server)
      try {
        await auth.refreshMe();
      } catch (_) {}

      final effectiveRole = auth.effectiveRole; // 'buyer' | 'seller'
      final route = effectiveRole == 'seller'
          ? AppRoutes.sellerHome
          : AppRoutes.buyerHome;

      if (kDebugMode) {
        debugPrint('Login OK. Redirect → $effectiveRole');
      }

      Navigator.of(context, rootNavigator: true)
          .pushNamedAndRemoveUntil(route, (r) => false);
    } on DioException catch (e) {
      // === Penanganan error yang diminta ===
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        _snack('Jaringan tidak stabil / server menolak sambungan. Coba lagi.');
        return;
      }

      final status = e.response?.statusCode ?? 0;
      if (status == 422) {
        final msg = _extractServerMessage(e.response?.data);
        _snack(msg);
        return;
      }

      final detail = (e.error ?? e.message ?? e.toString()).toString();
      _snack(
        kIsWeb
            ? 'Gagal login. Cek alamat API & CORS. Detail: $detail'
            : 'Gagal login: $detail',
      );
    } catch (e) {
      // Bisa dari validasi (throw Exception) di AuthProvider
      final msg = e.toString();
      _snack(msg.isNotEmpty ? msg : 'Terjadi kesalahan tidak dikenal.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.select<AuthProvider, bool>((a) => a.isLoading);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.eco_rounded,
                        size: 40,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'E-Buyur Market',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              const Text(
                'Selamat Datang!',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Masuk ke akun Anda untuk melanjutkan',
                style: TextStyle(fontSize: 14, color: AppColors.textGrey),
              ),
              const SizedBox(height: 32),

              // Toggle pembeli/penjual
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _RoleButton(
                        active: _isBuyerTab,
                        icon: Icons.shopping_bag_outlined,
                        label: 'Pembeli',
                        onTap: () {
                          if (!_isBuyerTab) setState(() => _isBuyerTab = true);
                        },
                      ),
                    ),
                    Expanded(
                      child: _RoleButton(
                        active: !_isBuyerTab,
                        icon: Icons.store_outlined,
                        label: 'Penjual',
                        onTap: () {
                          if (_isBuyerTab) setState(() => _isBuyerTab = false);
                        },
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _emailC,
                      keyboardType: TextInputType.emailAddress,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      inputFormatters: [
                        FilteringTextInputFormatter.deny(RegExp(r'\s')),
                      ],
                      validator: (v) {
                        final raw = v ?? '';
                        final cleaned = raw.replaceAll(RegExp(r'\s'), '').trim();
                        if (cleaned.isEmpty) return 'Email harus diisi';
                        final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$')
                            .hasMatch(cleaned);
                        if (!ok) return 'Format email tidak valid';
                        if (cleaned != raw) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _emailC.value = _emailC.value.copyWith(
                              text: cleaned,
                              selection: TextSelection.collapsed(
                                  offset: cleaned.length),
                              composing: TextRange.empty,
                            );
                          });
                        }
                        return null;
                      },
                      decoration: _inputDecoration(
                        label: 'Email',
                        prefix: const Icon(
                          Icons.email_outlined,
                          color: AppColors.textGrey,
                        ),
                      ),
                      onFieldSubmitted: (_) {
                        if (!isLoading) _handleLogin();
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passC,
                      obscureText: !_isPasswordVisible,
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Password harus diisi' : null,
                      decoration: _inputDecoration(
                        label: 'Password',
                        prefix: const Icon(
                          Icons.lock_outline,
                          color: AppColors.textGrey,
                        ),
                        suffix: IconButton(
                          icon: Icon(
                            _isPasswordVisible
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: AppColors.textGrey,
                          ),
                          onPressed: () => setState(
                              () => _isPasswordVisible = !_isPasswordVisible),
                        ),
                      ),
                      onFieldSubmitted: (_) {
                        if (!isLoading) _handleLogin();
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    Checkbox(
                      value: _rememberMe,
                      onChanged: isLoading
                          ? null
                          : (v) => setState(() => _rememberMe = v ?? false),
                      activeColor: AppColors.primaryGreen,
                    ),
                    const Text(
                      'Ingat saya',
                      style: TextStyle(fontSize: 14, color: AppColors.textGrey),
                    ),
                  ]),
                  TextButton(
                    onPressed: isLoading ? null : () {},
                    child: const Text(
                      'Lupa password?',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.primaryGreen,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: isLoading ? null : _handleLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          _isBuyerTab
                              ? 'Masuk sebagai Pembeli'
                              : 'Masuk sebagai Penjual',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 24),

              Row(children: [
                Expanded(child: Container(height: 1, color: AppColors.lightGrey)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('atau',
                      style: TextStyle(fontSize: 14, color: AppColors.textGrey)),
                ),
                Expanded(child: Container(height: 1, color: AppColors.lightGrey)),
              ]),

              const SizedBox(height: 24),

              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isLoading ? null : () {},
                    icon: Image.network(
                      'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                      height: 20,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.g_mobiledata, size: 20),
                    ),
                    label: const Text('Google'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: AppColors.lightGrey),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isLoading ? null : () {},
                    icon: const Icon(Icons.facebook,
                        color: Color(0xFF1877F2), size: 20),
                    label: const Text('Facebook'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: AppColors.lightGrey),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ]),

              const SizedBox(height: 32),

              Center(
                child: GestureDetector(
                  onTap: isLoading
                      ? null
                      : () {
                          if (!_isBuyerTab) {
                            Navigator.of(context, rootNavigator: true)
                                .pushReplacementNamed(AppRoutes.sellerRegister);
                          } else {
                            Navigator.of(context, rootNavigator: true)
                                .pushReplacementNamed(
                              AppRoutes.register,
                              arguments: const {'role': 'buyer'},
                            );
                          }
                        },
                  child: RichText(
                    text: TextSpan(
                      text: 'Belum punya akun? ',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textGrey,
                        fontFamily: 'Inter',
                      ),
                      children: [
                        TextSpan(
                          text: !_isBuyerTab
                              ? 'Daftar sebagai Penjual'
                              : 'Daftar sekarang',
                          style: const TextStyle(
                            color: AppColors.primaryGreen,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    Widget? prefix,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: prefix,
      suffixIcon: suffix,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.lightGrey),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.lightGrey),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2),
      ),
      filled: true,
      fillColor: const Color(0xFFF8F8F8),
    );
  }
}

class _RoleButton extends StatelessWidget {
  final bool active;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _RoleButton({
    required this.active,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: active ? AppColors.primaryGreen : AppColors.textGrey,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: active ? AppColors.primaryGreen : AppColors.textGrey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
