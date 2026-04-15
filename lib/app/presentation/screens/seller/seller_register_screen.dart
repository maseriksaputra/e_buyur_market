// lib/app/presentation/screens/seller/seller_register_screen.dart
// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:e_buyur_market_flutter_5/app/presentation/providers/auth_provider.dart';
import 'package:e_buyur_market_flutter_5/app/common/widgets/custom_text_field.dart';
import 'package:e_buyur_market_flutter_5/app/common/widgets/custom_button.dart';
import 'package:e_buyur_market_flutter_5/app/core/theme/app_colors.dart';
import 'package:e_buyur_market_flutter_5/app/core/routes.dart'; // ✅ gunakan konstanta rute

/// Endpoint base; bisa dioverride via --dart-define=API_BASE=https://domain
const String _kApiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://localhost:8000',
);

class SellerRegisterScreen extends StatefulWidget {
  const SellerRegisterScreen({Key? key}) : super(key: key);

  @override
  State<SellerRegisterScreen> createState() => _SellerRegisterScreenState();
}

class _SellerRegisterScreenState extends State<SellerRegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  // Akun
  final _nameC = TextEditingController();
  final _emailC = TextEditingController();
  final _phoneC = TextEditingController();
  final _passC = TextEditingController();
  final _pass2C = TextEditingController();

  // Toko
  final _storeNameC = TextEditingController();
  final _pickupAddrC = TextEditingController(); // alamat pickup / toko
  final _storeDescC = TextEditingController();

  // Wilayah minimal (hardcode contoh: Grobogan)
  String? _selectedDistrict; // Purwodadi / Wirosari / dst
  final _province = 'Jawa Tengah';
  final _regency = 'Grobogan';

  // (opsional) koordinat jika ada map picker
  double? _pickedLat;
  double? _pickedLng;

  bool _isLoading = false;
  bool _showPass = false;
  bool _showPass2 = false;

  @override
  void dispose() {
    _nameC.dispose();
    _emailC.dispose();
    _phoneC.dispose();
    _passC.dispose();
    _pass2C.dispose();
    _storeNameC.dispose();
    _pickupAddrC.dispose();
    _storeDescC.dispose();
    super.dispose();
  }

  // =================== SUBMIT ===================
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final token =
          context.read<AuthProvider>().token; // wajib utk endpoint proteksi

      // ====== WAJIB: snake_case sesuai backend ======
      final body = <String, dynamic>{
        // data toko
        'store_name': _storeNameC.text.trim(),
        'store_address': _pickupAddrC.text.trim(),
        'store_description':
            _storeDescC.text.trim().isEmpty ? null : _storeDescC.text.trim(),
        'phone': _phoneC.text.trim(),
        'province': _province,
        'regency': _regency,
        'district': _selectedDistrict ?? '',
        'lat': _pickedLat?.toStringAsFixed(6),
        'lng': _pickedLng?.toStringAsFixed(6),

        // jika endpoint kamu perlu mendaftarkan akun sekaligus, sertakan juga:
        'name': _nameC.text.trim(),
        'email': _emailC.text.trim(),
        'password': _passC.text,
        'password_confirmation': _pass2C.text,
      };

      final uri = Uri.parse('$_kApiBase/api/sellers');
      final res = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if ((token).toString().isNotEmpty) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      // ✅ LETAKKAN PERIKSA 201 DI SINI (langsung setelah post)
      if (res.statusCode == 201) {
        await context
            .read<AuthProvider>()
            .refreshMe(); // agar role jadi 'seller'
        Navigator.pushNamedAndRemoveUntil(
            context, AppRoutes.sellerHome, (route) => false);
        return;
      }

      // (fallback) beberapa backend mungkin mengembalikan 200
      if (res.statusCode >= 200 && res.statusCode < 300) {
        await context.read<AuthProvider>().refreshMe();
        Navigator.pushNamedAndRemoveUntil(
            context, AppRoutes.sellerHome, (route) => false);
        return;
      }

      if (res.statusCode == 422) {
        final msg = _extractValidationMessage(res.body);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
        return;
      }

      // selain itu, tampilkan kode dan sebagian body
      String bodyPreview = res.body;
      if (bodyPreview.length > 240)
        bodyPreview = '${bodyPreview.substring(0, 240)}…';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal (${res.statusCode}): $bodyPreview')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Terjadi kesalahan: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _extractValidationMessage(String body) {
    try {
      final m = jsonDecode(body);
      if (m is Map) {
        // Laravel: { message: "...", errors: { field: ["msg"] } }
        if (m['errors'] is Map && (m['errors'] as Map).isNotEmpty) {
          final first = (m['errors'] as Map).values.first;
          if (first is List && first.isNotEmpty) return first.first.toString();
        }
        if (m['message'] != null) return m['message'].toString();
      }
    } catch (_) {}
    return 'Data tidak valid (422)';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daftar Sebagai Penjual')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Lengkapi data akun & toko Anda untuk mulai berjualan.',
                  style: TextStyle(fontSize: 16, color: AppColors.textGrey),
                ),

                const SizedBox(height: 24),
                // ================== DATA AKUN ==================
                const _SectionTitle('Data Akun'),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _nameC,
                  label: 'Nama Lengkap',
                  hint: 'Mis: Budi Santoso',
                  prefixIcon: Icons.person_outline,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Nama harus diisi'
                      : null,
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: _emailC,
                  label: 'Email',
                  hint: 'nama@contoh.com',
                  prefixIcon: Icons.email_outlined,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty)
                      return 'Email harus diisi';
                    // ✅ akhiri dengan $ (tanpa escaping)
                    final re = RegExp(r'^[\w\.-]+@([\w-]+\.)+[\w-]{2,4}$');
                    if (!re.hasMatch(v.trim()))
                      return 'Format email tidak valid';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: _phoneC,
                  label: 'Nomor Telepon',
                  hint: '08xxxxxxxxxx',
                  prefixIcon: Icons.phone_outlined,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Nomor telepon harus diisi'
                      : null,
                ),
                const SizedBox(height: 16),

                // Password
                _passwordField(
                  controller: _passC,
                  label: 'Password',
                  isObscure: !_showPass,
                  onToggle: () => setState(() => _showPass = !_showPass),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Password harus diisi';
                    if (v.length < 6) return 'Password minimal 6 karakter';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _passwordField(
                  controller: _pass2C,
                  label: 'Konfirmasi Password',
                  isObscure: !_showPass2,
                  onToggle: () => setState(() => _showPass2 = !_showPass2),
                  validator: (v) {
                    if (v == null || v.isEmpty)
                      return 'Konfirmasi password harus diisi';
                    if (v != _passC.text) return 'Password tidak cocok';
                    return null;
                  },
                ),

                const SizedBox(height: 28),
                // ================== DATA TOKO ==================
                const _SectionTitle('Data Toko'),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _storeNameC,
                  label: 'Nama Toko',
                  hint: 'Mis: Toko Sayur Segar',
                  prefixIcon: Icons.store_outlined,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Nama toko harus diisi'
                      : null,
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: _pickupAddrC,
                  label: 'Alamat/Pickup Toko',
                  hint: 'Masukkan alamat lengkap toko / lokasi pickup',
                  prefixIcon: Icons.location_on_outlined,
                  maxLines: 3,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Alamat toko harus diisi'
                      : null,
                ),
                const SizedBox(height: 16),

                // Dropdown Kecamatan (contoh)
                DropdownButtonFormField<String>(
                  value: _selectedDistrict,
                  items: const [
                    DropdownMenuItem(
                        value: 'Purwodadi', child: Text('Purwodadi')),
                    DropdownMenuItem(
                        value: 'Wirosari', child: Text('Wirosari')),
                  ],
                  onChanged: (v) => setState(() => _selectedDistrict = v),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Pilih kecamatan' : null,
                  decoration: InputDecoration(
                    labelText: 'Kecamatan',
                    prefixIcon: const Icon(Icons.map_outlined,
                        color: AppColors.textGrey),
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
                ),
                const SizedBox(height: 16),

                CustomTextField(
                  controller: _storeDescC,
                  label: 'Deskripsi Toko (opsional)',
                  hint: 'Ceritakan seputar toko Anda',
                  prefixIcon: Icons.description_outlined,
                  maxLines: 5,
                ),

                const SizedBox(height: 32),
                CustomButton(
                  text: 'Daftar Sekarang',
                  onPressed: _isLoading ? null : _submit,
                  isLoading: _isLoading,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Password field helper
  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool isObscure,
    required VoidCallback onToggle,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isObscure,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline, color: AppColors.textGrey),
        suffixIcon: IconButton(
          icon: Icon(isObscure ? Icons.visibility : Icons.visibility_off,
              color: AppColors.textGrey),
          onPressed: onToggle,
        ),
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

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 16,
        color: AppColors.textDark,
      ),
    );
  }
}
