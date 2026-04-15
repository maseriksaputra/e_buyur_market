import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../../core/theme/app_colors.dart' as theme;

class SellerProfileScreen extends StatefulWidget {
  const SellerProfileScreen({Key? key}) : super(key: key);

  @override
  State<SellerProfileScreen> createState() => _SellerProfileScreenState();
}

class _SellerProfileScreenState extends State<SellerProfileScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  bool _notifEnabled = true;

  // ==== NEW: state untuk avatar & upload =====
  Uint8List? _pickedAvatarBytes;
  bool _uploadingPhoto = false;

  // ==== NEW: override lokal agar UI langsung berubah setelah save store info ====
  String? _storeNameOverride;
  String? _storeDescOverride;
  String? _storeAddrOverride;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // ==== helpers API ====
  String get _apiBase =>
      const String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:8000');

  Map<String, String> _authHeaders(AuthProvider auth) {
    String? token;
    try {
      token = (auth as dynamic).token as String?;
    } catch (_) {}
    try {
      token ??= (auth as dynamic).accessToken as String?;
    } catch (_) {}
    try {
      token ??= (auth as dynamic).bearer as String?;
    } catch (_) {}
    return token != null && token.isNotEmpty ? {'Authorization': 'Bearer $token'} : {};
  }

  Future<void> _pickAndUploadPhoto() async {
    final auth = context.read<AuthProvider>();
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal membaca file gambar')),
        );
        return;
      }

      setState(() => _uploadingPhoto = true);

      final dio = Dio(BaseOptions(baseUrl: _apiBase, headers: _authHeaders(auth)));
      final form = FormData.fromMap({
        'photo': MultipartFile.fromBytes(bytes, filename: file.name),
      });

      Response resp;
      try {
        resp = await dio.post('seller/profile/photo', data: form);
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) {
          resp = await dio.post('profile/photo', data: form);
        } else {
          rethrow;
        }
      }

      if (resp.statusCode != null && resp.statusCode! >= 200 && resp.statusCode! < 300) {
        setState(() {
          _pickedAvatarBytes = bytes;
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Foto profil diperbarui')),
        );

        try {
          await (auth as dynamic).reload?.call();
        } catch (_) {}
        try {
          await (auth as dynamic).fetchProfile?.call();
        } catch (_) {}
      } else {
        throw Exception('Upload gagal (${resp.statusCode})');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal upload foto: $e')),
      );
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _openStoreEditSheet() async {
    final auth = context.read<AuthProvider>();
    final user = auth.user;

    final nameCtl = TextEditingController(text: _storeNameOverride ?? user?.storeName ?? '');
    final descCtl =
        TextEditingController(text: _storeDescOverride ?? user?.storeDescription ?? '');
    final addrCtl =
        TextEditingController(text: _storeAddrOverride ?? user?.storeAddress ?? '');

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Edit Informasi Toko',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtl,
                decoration: const InputDecoration(
                  labelText: 'Nama Toko',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtl,
                decoration: const InputDecoration(
                  labelText: 'Deskripsi Toko',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addrCtl,
                decoration: const InputDecoration(
                  labelText: 'Alamat Toko',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Batal'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        final name = nameCtl.text.trim();
                        if (name.isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('Nama toko tidak boleh kosong')),
                          );
                          return;
                        }
                        try {
                          final dio = Dio(BaseOptions(
                            baseUrl: _apiBase,
                            headers: _authHeaders(auth),
                          ));
                          final payload = {
                            'store_name': name,
                            'store_description': descCtl.text.trim(),
                            'store_address': addrCtl.text.trim(),
                          };
                          Response resp;
                          try {
                            resp = await dio.put('seller/store', data: payload);
                          } on DioException catch (e) {
                            if (e.response?.statusCode == 404) {
                              resp = await dio.put('store', data: payload);
                            } else {
                              rethrow;
                            }
                          }

                          if (resp.statusCode != null &&
                              resp.statusCode! >= 200 &&
                              resp.statusCode! < 300) {
                            if (!mounted) return;
                            setState(() {
                              _storeNameOverride = nameCtl.text.trim();
                              _storeDescOverride = descCtl.text.trim();
                              _storeAddrOverride = addrCtl.text.trim();
                            });
                            Navigator.pop(ctx, true);
                          } else {
                            throw Exception('Gagal menyimpan (${resp.statusCode})');
                          }
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Gagal menyimpan: $e')),
                          );
                        }
                      },
                      child: const Text('Simpan'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Tambahan spacer anti-overflow saat keyboard/gesture bar
              SizedBox(height: MediaQuery.of(ctx).padding.bottom + 16),
            ],
          ),
        );
      },
    );

    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informasi toko diperbarui')),
      );

      try {
        await (auth as dynamic).reload?.call();
      } catch (_) {}
      try {
        await (auth as dynamic).fetchProfile?.call();
      } catch (_) {}
      setState(() {});
    }
  }

  Widget _buildDefaultAvatar(String name) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.9),
            Colors.white.withOpacity(0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.bold,
            color: theme.AppColors.primaryGreen,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ====== PERHITUNGAN HEADER + VARIABEL (BARU) ======
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final avatarUrl = user?.profilePictureUrl;

    final storeName = _storeNameOverride ?? user?.storeName ?? 'Nama Toko';
    final storeDesc = _storeDescOverride ?? user?.storeDescription;
    final storeAddr = _storeAddrOverride ?? user?.storeAddress;

    final media = MediaQuery.of(context);
    final statusBar = media.padding.top;
    final textScale = media.textScaleFactor.clamp(1.0, 1.25);
    // Header adaptif: lebih tinggi sedikit + aware textScale
    final double headerHeight = ((media.size.height < 700) ? 320 : 360) * textScale;
    // ruang aman bawah untuk konten (sudah ada padBottom di filemu)
    final padBottom = media.padding.bottom + kBottomNavigationBarHeight + 32;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      extendBody: true,
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        top: false,
        bottom: true,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ===== HEADER =====
            SliverAppBar(
              expandedHeight: statusBar + headerHeight + 16, // +margin kecil biar aman
              floating: false,
              pinned: true,
              elevation: 0,
              backgroundColor: theme.AppColors.primaryGreen,
              title: const Text('Profil'),
              centerTitle: true,
              actions: [
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
                    ),
                    child: const Icon(Icons.edit, size: 20, color: Colors.white),
                  ),
                  onPressed: _openStoreEditSheet,
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        theme.AppColors.primaryGreen,
                        theme.AppColors.primaryGreenDark,
                      ],
                    ),
                  ),
                  child: Stack(
                    children: [
                      // dekorasi
                      Positioned(
                        top: -80,
                        right: -80,
                        child: Container(
                          width: 250,
                          height: 250,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.1),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: -50,
                        left: -50,
                        child: Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.08),
                          ),
                        ),
                      ),
                      // lengkungan putih di bawah header (sedikit lebih tipis)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 22, // was 28
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(30),
                              topRight: Radius.circular(30),
                            ),
                          ),
                        ),
                      ),

                      // ===== KONTEN HEADER (dirapatkan ke atas sedikit) =====
                      SafeArea(
                        child: Align(
                          alignment: const Alignment(0, 0.78), // was 0.85 -> geser naik
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Avatar + tombol kamera (tetap)
                                  Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Container(
                                        width: 116,
                                        height: 116,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.white, width: 4),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.2),
                                              blurRadius: 20,
                                              offset: const Offset(0, 10),
                                            ),
                                          ],
                                        ),
                                        child: ClipOval(
                                          child: _pickedAvatarBytes != null
                                              ? Image.memory(_pickedAvatarBytes!, fit: BoxFit.cover)
                                              : (avatarUrl != null && avatarUrl.isNotEmpty)
                                                  ? Image.network(
                                                      avatarUrl,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (_, __, ___) =>
                                                          _buildDefaultAvatar(user?.name ?? 'User'),
                                                    )
                                                  : _buildDefaultAvatar(user?.name ?? 'User'),
                                        ),
                                      ),
                                      Positioned(
                                        bottom: 5,
                                        right: 5,
                                        child: InkWell(
                                          onTap: _uploadingPhoto ? null : _pickAndUploadPhoto,
                                          borderRadius: BorderRadius.circular(99),
                                          child: Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: const BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Colors.white,
                                            ),
                                            child: _uploadingPhoto
                                                ? const SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child: CircularProgressIndicator(strokeWidth: 2),
                                                  )
                                                : Icon(Icons.camera_alt,
                                                    size: 20,
                                                    color: theme.AppColors.primaryGreen),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    user?.name ?? 'Nama Penjual',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: -0.5,
                                      shadows: [Shadow(blurRadius: 8, color: Colors.black26)],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 8),
                                  // badge nama toko
                                  Container(
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.22),
                                      borderRadius: BorderRadius.circular(22),
                                      border: Border.all(color: Colors.white.withOpacity(0.28)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.store, size: 16, color: Colors.white),
                                        const SizedBox(width: 6),
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(maxWidth: 220),
                                          child: Text(
                                            _storeNameOverride ?? user?.storeName ?? 'Nama Toko',
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  if ((user?.email ?? '').isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.18),
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.email, size: 14, color: Colors.white),
                                          const SizedBox(width: 6),
                                          ConstrainedBox(
                                            constraints:
                                                const BoxConstraints(maxWidth: 260),
                                            child: Text(
                                              user!.email!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.calendar_today,
                                          size: 12, color: Colors.white.withOpacity(0.9)),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Bergabung ${_formatDate(user?.createdAt)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.white.withOpacity(0.95),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 24), // jarak ekstra anti-kepotong
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ===== KONTEN DI BAWAH HEADER =====
            SliverToBoxAdapter(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Padding(
                    // biar lega & anti nabrak bottom-nav
                    padding: EdgeInsets.only(bottom: padBottom),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Verification Status Card
                        Container(
                          margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                theme.AppColors.primaryGreen,
                                theme.AppColors.primaryGreenLight,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: theme.AppColors.primaryGreen.withOpacity(0.3),
                                blurRadius: 15,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.25),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.verified, color: Colors.white, size: 26),
                              ),
                              const SizedBox(width: 16),
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: const [
                                    Text('Toko Terverifikasi',
                                        style: TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white)),
                                    SizedBox(height: 4),
                                    Text(
                                      'Toko Anda telah terverifikasi dan dipercaya',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Personal Information
                        _buildModernSectionCard(
                          title: 'Informasi Pribadi',
                          icon: Icons.person,
                          gradient: [
                            theme.AppColors.primaryGreen.withOpacity(0.1),
                            theme.AppColors.primaryGreenLight.withOpacity(0.05),
                          ],
                          children: [
                            _buildModernInfoItem(
                              icon: Icons.email,
                              label: 'Email',
                              value: user?.email ?? '-',
                              iconColor: theme.AppColors.primaryGreen,
                              onTap: () {},
                            ),
                            _buildModernDivider(),
                            _buildModernInfoItem(
                              icon: Icons.phone,
                              label: 'Nomor Telepon',
                              value: user?.phone ?? '-',
                              iconColor: theme.AppColors.primaryGreen,
                              onTap: () {},
                            ),
                            _buildModernDivider(),
                            _buildModernInfoItem(
                              icon: Icons.calendar_today,
                              label: 'Tanggal Lahir',
                              value: _formatDate(user?.dateOfBirth),
                              iconColor: theme.AppColors.primaryGreen,
                              onTap: () {},
                            ),
                            _buildModernDivider(),
                            _buildModernInfoItem(
                              icon: Icons.location_on,
                              label: 'Alamat',
                              value: user?.address ?? 'Belum diatur',
                              iconColor: theme.AppColors.primaryGreen,
                              onTap: () {},
                            ),
                          ],
                        ),

                        // Store Information
                        _buildModernSectionCard(
                          title: 'Informasi Toko',
                          icon: Icons.store,
                          gradient: [
                            const Color(0xFF66BB6A).withOpacity(0.1),
                            const Color(0xFF81C784).withOpacity(0.05),
                          ],
                          children: [
                            _buildModernInfoItem(
                              icon: Icons.store_mall_directory,
                              label: 'Nama Toko',
                              value: storeName,
                              iconColor: const Color(0xFF66BB6A),
                              onTap: _openStoreEditSheet,
                            ),
                            _buildModernDivider(),
                            _buildModernInfoItem(
                              icon: Icons.description,
                              label: 'Deskripsi Toko',
                              value: (storeDesc?.isNotEmpty ?? false)
                                  ? storeDesc!
                                  : 'Tambahkan deskripsi toko',
                              iconColor: const Color(0xFF66BB6A),
                              onTap: _openStoreEditSheet,
                            ),
                            _buildModernDivider(),
                            _buildModernInfoItem(
                              icon: Icons.location_city,
                              label: 'Alamat Toko',
                              value: storeAddr ?? 'Belum diatur',
                              iconColor: const Color(0xFF66BB6A),
                              onTap: _openStoreEditSheet,
                            ),
                            _buildModernDivider(),
                            _buildModernInfoItem(
                              icon: Icons.schedule,
                              label: 'Jam Operasional',
                              value: 'Senin - Sabtu, 08:00 - 20:00',
                              iconColor: const Color(0xFF66BB6A),
                              onTap: () {},
                            ),
                          ],
                        ),

                        // Settings
                        _buildModernSectionCard(
                          title: 'Pengaturan',
                          icon: Icons.settings,
                          gradient: [
                            theme.AppColors.primaryGreenDark.withOpacity(0.1),
                            theme.AppColors.primaryGreen.withOpacity(0.05),
                          ],
                          children: [
                            _buildModernSettingItem(
                              icon: Icons.notifications,
                              title: 'Notifikasi',
                              subtitle: 'Kelola preferensi notifikasi',
                              iconColor: theme.AppColors.primaryGreenDark,
                              trailing: Switch(
                                value: _notifEnabled,
                                onChanged: (v) => setState(() => _notifEnabled = v),
                                activeColor: theme.AppColors.primaryGreen,
                                activeTrackColor: theme.AppColors.primaryGreenLight,
                              ),
                            ),
                            _buildModernDivider(),
                            _buildModernSettingItem(
                              icon: Icons.lock,
                              title: 'Keamanan Akun',
                              subtitle: 'Ubah password dan pengaturan keamanan',
                              iconColor: theme.AppColors.primaryGreenDark,
                              onTap: () {},
                            ),
                            _buildModernDivider(),
                            _buildModernSettingItem(
                              icon: Icons.payment,
                              title: 'Rekening Bank',
                              subtitle: 'Kelola rekening untuk pencairan dana',
                              iconColor: theme.AppColors.primaryGreenDark,
                              onTap: () {},
                            ),
                            _buildModernDivider(),
                            _buildModernSettingItem(
                              icon: Icons.help,
                              title: 'Bantuan & Dukungan',
                              subtitle: 'FAQ dan hubungi customer service',
                              iconColor: theme.AppColors.primaryGreenDark,
                              onTap: () {},
                            ),
                            _buildModernDivider(),
                            _buildModernSettingItem(
                              icon: Icons.info,
                              title: 'Tentang Aplikasi',
                              subtitle: 'Versi 1.0.0',
                              iconColor: theme.AppColors.primaryGreenDark,
                              onTap: () {},
                            ),
                          ],
                        ),

                        // Logout Button
                        Container(
                          margin: const EdgeInsets.all(20),
                          width: double.infinity,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFE53935), Color(0xFFD32F2F)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withOpacity(0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _showModernLogoutDialog(context, auth),
                              child: const Center(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.logout, color: Colors.white),
                                    SizedBox(width: 8),
                                    Text(
                                      'Keluar',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _maybeNavigate(BuildContext context, String routeName) async {
    try {
      await Navigator.of(context).pushNamed(routeName);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Rute "$routeName" belum tersedia.'),
          backgroundColor: theme.AppColors.primaryGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  // === Modern Widget Helpers ===
  Widget _buildModernSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
    required List<Color> gradient,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: gradient[0].withOpacity(0.2),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Icon(icon, color: gradient[0].withOpacity(1), size: 22),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildModernInfoItem({
    required IconData icon,
    required String label,
    required String value,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 16),
              // Flexible agar tidak memaksa tinggi
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernSettingItem({
    required IconData icon,
    required String title,
    String? subtitle,
    required Color iconColor,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap != null
            ? () {
                HapticFeedback.lightImpact();
                onTap();
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 16),
              // Flexible agar teks bisa wrap tanpa memaksa tinggi parent
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ],
                ),
              ),
              if (trailing != null)
                trailing
              else
                Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Divider(
        height: 1,
        thickness: 0.5,
        color: Colors.grey[200],
      ),
    );
  }

  // === Helpers ===
  String _formatDate(dynamic date) {
    DateTime dt;
    if (date == null) {
      dt = DateTime.now();
    } else if (date is DateTime) {
      dt = date;
    } else if (date is String) {
      dt = DateTime.tryParse(date) ?? DateTime.now();
    } else {
      dt = DateTime.now();
    }

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  void _showModernLogoutDialog(BuildContext context, AuthProvider auth) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [Colors.white, Colors.grey[50]!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.logout, size: 32, color: Colors.red),
              ),
              const SizedBox(height: 20),
              const Text(
                'Konfirmasi Keluar',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Apakah Anda yakin ingin keluar dari akun ini?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey[300]!),
                        ),
                      ),
                      child: Text(
                        'Batal',
                        style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () async {
                        HapticFeedback.mediumImpact();
                        try {
                          await auth.logout();
                        } catch (_) {}
                        if (!mounted) return;
                        Navigator.of(ctx).pop();
                        Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
                      },
                      child: const Text('Keluar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
