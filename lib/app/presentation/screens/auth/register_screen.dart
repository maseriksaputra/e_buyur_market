// lib/app/presentation/screens/auth/register_screen.dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:e_buyur_market_flutter_5/app/presentation/providers/auth_provider.dart';
import 'package:e_buyur_market_flutter_5/app/core/theme/app_colors.dart';
import 'package:e_buyur_market_flutter_5/app/core/network/api.dart'; // ⬅️ untuk fallback direct API call

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers (sesuai requirement)
  final _nameC = TextEditingController();
  final _emailC = TextEditingController();
  final _phoneC = TextEditingController(); // opsional
  final _passC = TextEditingController();
  final _pass2C = TextEditingController();

  // UI-only (tidak dikirim)
  final _addressC = TextEditingController();
  DateTime? _dob;

  // State
  bool _isPassVisible = false;
  bool _isPass2Visible = false;
  bool _isLoading = false;
  bool _agree = false;
  String _role = 'buyer'; // default 'buyer' | 'seller'

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null && args['role'] != null) {
      final r = args['role'].toString().toLowerCase();
      if (r == 'buyer' || r == 'seller') {
        _role = r;
      }
    }
  }

  @override
  void dispose() {
    _nameC.dispose();
    _emailC.dispose();
    _phoneC.dispose();
    _passC.dispose();
    _pass2C.dispose();
    _addressC.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(2000, 1, 1),
      firstDate: DateTime(1950, 1, 1),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: AppColors.primaryGreen),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _dob = picked);
    }
  }

  String _extractServerMessage(dynamic data, {String fallback = 'Registrasi gagal'}) {
    try {
      if (data is Map) {
        final err = data['error'];
        if (err is Map) {
          final details = err['details'];
          if (details != null && details.toString().trim().isNotEmpty) {
            return details.toString();
          }
          final msg = err['message'];
          if (msg is String && msg.isNotEmpty) return msg;
        }
        final errors = data['errors'];
        if (errors is Map && errors.isNotEmpty) {
          final first = errors.values.first;
          if (first is List && first.isNotEmpty) return first.first.toString();
          return first.toString();
        }
        final msg = data['message'];
        if (msg is String && msg.isNotEmpty) return msg;
      } else if (data is String && data.trim().isNotEmpty) {
        return data;
      }
    } catch (_) {}
    return fallback;
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_agree) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Anda harus menyetujui syarat & ketentuan.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      // role dari tab
      final role = _role; // 'buyer' | 'seller'

      // =========================
      // 1) Coba panggil Provider.register(...) (unified)
      // =========================
      bool unifiedOk = false;
      try {
        final dynamic authDyn = context.read<AuthProvider>(); // ⬅️ dynamic agar tidak error compile
        await authDyn.register(
          name: _nameC.text.trim(),
          email: _emailC.text.trim(),
          password: _passC.text,
          role: role,
          phone: _phoneC.text.trim().isEmpty ? null : _phoneC.text.trim(),
        );
        unifiedOk = true;
      } on NoSuchMethodError {
        unifiedOk = false; // Provider lama: tidak ada method register(...)
      }

      // =========================
      // 2) Fallback: pukul API langsung kalau Provider lama
      // =========================
      if (!unifiedOk) {
        final res = await API.dio.post(
          'auth/register',
          data: {
            'name': _nameC.text.trim(),
            'email': _emailC.text.trim(),
            'password': _passC.text,
            'role': role,
            if (_phoneC.text.trim().isNotEmpty) 'phone': _phoneC.text.trim(),
          },
          options: Options(headers: {'Accept': 'application/json', 'Content-Type': 'application/json'}),
        );

        if (res.statusCode != 200 && res.statusCode != 201) {
          final msg = _extractServerMessage(res.data, fallback: 'Registrasi gagal');
          throw DioException(
            requestOptions: res.requestOptions,
            response: res,
            type: DioExceptionType.badResponse,
            message: msg,
          );
        }
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Registrasi berhasil. Silakan masuk.'),
          backgroundColor: Colors.green,
        ),
      );

      // Ke layar login setelah sukses
      Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Jaringan tidak stabil / server menolak sambungan. Coba lagi.'),
            backgroundColor: Colors.red,
          ),
        );
      } else if (e.response?.statusCode == 422) {
        final msg = _extractServerMessage(e.response?.data, fallback: 'Validasi gagal');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      } else {
        final msg = _extractServerMessage(e.response?.data, fallback: e.message ?? 'Registrasi gagal');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSeller = _role == 'seller';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(height: 24),
                Text(
                  isSeller ? 'Daftar Sebagai Penjual' : 'Daftar Akun Baru',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isSeller ? 'Mulai jual produk segar Anda' : 'Isi data diri untuk membuat akun',
                  style: const TextStyle(fontSize: 14, color: AppColors.textGrey),
                ),
                const SizedBox(height: 32),

                // Toggle tab Pembeli / Penjual
                _roleToggle(),

                const SizedBox(height: 24),

                _field(
                  controller: _nameC,
                  label: 'Nama Lengkap',
                  icon: Icons.person_outline,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Nama lengkap harus diisi' : null,
                ),
                const SizedBox(height: 16),

                _field(
                  controller: _emailC,
                  label: 'Email',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Email harus diisi';
                    final re = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');
                    if (!re.hasMatch(v.trim())) return 'Format email tidak valid';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Phone opsional
                _field(
                  controller: _phoneC,
                  label: 'Nomor Telepon (Opsional)',
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return null;
                    if (!RegExp(r'^[0-9+\-\s]{6,}$').hasMatch(t)) {
                      return 'Nomor telepon tidak valid';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                _dobPicker(), // opsional UI (tidak dikirim)
                const SizedBox(height: 16),

                _field(
                  controller: _addressC,
                  label: 'Alamat (Opsional)',
                  icon: Icons.home_outlined,
                  maxLines: 2,
                ),
                const SizedBox(height: 16),

                _field(
                  controller: _passC,
                  label: 'Password',
                  icon: Icons.lock_outline,
                  obscureText: !_isPassVisible,
                  suffixIcon: _eye(
                    visible: _isPassVisible,
                    onTap: () => setState(() => _isPassVisible = !_isPassVisible),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Password harus diisi';
                    if (v.length < 6) return 'Password minimal 6 karakter';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                _field(
                  controller: _pass2C,
                  label: 'Konfirmasi Password',
                  icon: Icons.lock_outline,
                  obscureText: !_isPass2Visible,
                  suffixIcon: _eye(
                    visible: _isPass2Visible,
                    onTap: () => setState(() => _isPass2Visible = !_isPass2Visible),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Konfirmasi password harus diisi';
                    if (v != _passC.text) return 'Password tidak cocok';
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                _terms(),
                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleRegister,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : Text(
                            isSeller ? 'Daftar Sebagai Penjual' : 'Daftar',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                  ),
                ),
                const SizedBox(height: 24),

                Center(
                  child: GestureDetector(
                    onTap: () => Navigator.pushReplacementNamed(context, '/login'),
                    child: const Text.rich(
                      TextSpan(
                        text: 'Sudah punya akun? ',
                        style: TextStyle(fontSize: 14, color: AppColors.textGrey, fontFamily: 'Poppins'),
                        children: [
                          TextSpan(
                            text: 'Masuk',
                            style: TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.bold),
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
      ),
    );
  }

  // ----------------- UI Helpers -----------------
  Widget _roleToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _roleItem('Pembeli', 'buyer', Icons.shopping_bag_outlined),
          _roleItem('Penjual', 'seller', Icons.store_outlined),
        ],
      ),
    );
  }

  Widget _roleItem(String label, String role, IconData icon) {
    final sel = _role == role;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _role = role),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: sel ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: sel
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
              Icon(icon, size: 18, color: sel ? AppColors.primaryGreen : AppColors.textGrey),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: sel ? AppColors.primaryGreen : AppColors.textGrey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dobPicker() {
    final text = _dob == null ? 'Pilih tanggal' : '${_dob!.day}/${_dob!.month}/${_dob!.year}';
    return InkWell(
      onTap: _pickDob,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Tanggal Lahir (Opsional)',
          prefixIcon: const Icon(Icons.calendar_today, color: AppColors.textGrey),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.lightGrey),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.lightGrey),
          ),
          filled: true,
          fillColor: const Color(0xFFF8F8F8),
        ),
        child: Text(
          text,
          style: TextStyle(color: _dob == null ? AppColors.textGrey : AppColors.textDark),
        ),
      ),
    );
  }

  Widget _eye({required bool visible, required VoidCallback onTap}) {
    return IconButton(
      icon: Icon(visible ? Icons.visibility_off : Icons.visibility, color: AppColors.textGrey),
      onPressed: onTap,
    );
  }

  Widget _terms() {
    return Row(
      children: [
        Checkbox(
          value: _agree,
          onChanged: (v) => setState(() => _agree = v ?? false),
          activeColor: AppColors.primaryGreen,
        ),
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _agree = !_agree),
            child: const Text.rich(
              TextSpan(
                text: 'Saya setuju dengan ',
                style: TextStyle(fontSize: 12, color: AppColors.textGrey, fontFamily: 'Poppins'),
                children: [
                  TextSpan(
                    text: 'Syarat & Ketentuan',
                    style: TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: ' dan '),
                  TextSpan(
                    text: 'Kebijakan Privasi',
                    style: TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    Widget? suffixIcon,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.textGrey),
        suffixIcon: suffixIcon,
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
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
        filled: true,
        fillColor: const Color(0xFFF8F8F8),
      ),
    );
  }
}
