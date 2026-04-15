// lib/app/presentation/providers/auth_provider.dart
import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/services/product_api_service.dart';
import '../../core/services/auth_api_service.dart'; // ✅ pakai service login yg sudah kirim device_name
import '../../core/auth/token_store.dart';
import '../../core/network/api.dart';
import '../../common/models/user_model.dart' as models;

// Model User project-mu
typedef UserModel = models.User;

/// =============================================================
/// AuthProvider — Single source of truth token per role
///  - token_buyer, token_seller, active_role
///  - switchRole() ganti Authorization header instan
///  + Persist user di secure storage & auto-restore saat app start
/// =============================================================
class AuthProvider with ChangeNotifier {
  // ---------- Storage Keys ----------
  static const _kTokenBuyer   = 'token_buyer';
  static const _kTokenSeller  = 'token_seller';
  static const _kActiveRole   = 'active_role'; // buyer|seller|guest
  static const _kLastRoute    = 'auth_last_route';
  // 🔰 Tambahan: cache data user per role agar bisa auto-login instan
  static const _kUserBuyer    = 'user_buyer';
  static const _kUserSeller   = 'user_seller';

  // ---------- Services ----------
  final ProductApiService _api = ProductApiService();
  final AuthApiService _authApi = AuthApiService(); // ✅ service login
  final FlutterSecureStorage? _secure = kIsWeb
      ? null
      : const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
          iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
        );

  // ---------- State ----------
  bool _initializing = true;
  bool _loading = false;
  bool _loggingIn = false;
  String? _error;

  String? _token;          // token aktif untuk _role
  String  _role = 'guest'; // 'buyer' | 'seller' | 'guest'
  UserModel? _user;

  // (opsional) rute terakhir untuk direct routing setelah login
  String? _lastRoute;

  // Throttle refresh profil
  bool _refreshing = false;
  DateTime? _lastRefreshAt;

  // ---------- Getters lama (kompat) ----------
  bool get isInitializing => _initializing;
  bool get isLoading => _loading;
  bool get loggingIn => _loggingIn;
  String? get error => _error;

  String? get token => _token;
  UserModel? get user => _user;

  bool get isAuthenticated => (_token != null && _token!.isNotEmpty && _user != null);

  /// role “server”/aktif sekarang. Gunakan ini untuk routing.
  String get role => _role;

  /// Kompat lama
  String? get userRole => _role;

  String? get lastRoute => _lastRoute;

  /// Kompat lama: effective role → default buyer bila guest
  String get effectiveRole => (_role == 'guest') ? 'buyer' : _role;

  // ---------- Setters kecil ----------
  void _setInitializing(bool v) { _initializing = v; notifyListeners(); }
  void _setLoading(bool v)      { _loading = v; notifyListeners();    }
  void _setError(String? e)     { _error = e; notifyListeners();      }

  // =============================================================
  // Storage helpers (secure dulu → fallback prefs di web)
  // =============================================================
  Future<void> _write(String key, String? value) async {
    if (!kIsWeb && _secure != null) {
      if (value == null) {
        await _secure!.delete(key: key);
      } else {
        await _secure!.write(key: key, value: value);
      }
    } else {
      final sp = await SharedPreferences.getInstance();
      if (value == null) {
        await sp.remove(key);
      } else {
        await sp.setString(key, value);
      }
    }
  }

  Future<String?> _read(String key) async {
    if (!kIsWeb && _secure != null) {
      return _secure!.read(key: key);
    } else {
      final sp = await SharedPreferences.getInstance();
      return sp.getString(key);
    }
  }

  // 🔰 helper simpan/ambil USER per role (JSON string)
  Future<void> _writeUserForRole(String role, Map<String, dynamic>? userMap) async {
    final key = (role == 'seller') ? _kUserSeller : _kUserBuyer;
    await _write(key, userMap == null ? null : jsonEncode(userMap));
  }

  Future<Map<String, dynamic>?> _readUserMapForRole(String role) async {
    final key = (role == 'seller') ? _kUserSeller : _kUserBuyer;
    final s = await _read(key);
    if (s == null || s.isEmpty) return null;
    try {
      final m = jsonDecode(s);
      return (m is Map) ? Map<String, dynamic>.from(m) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _clearAllTokens() async {
    await _write(_kTokenBuyer, null);
    await _write(_kTokenSeller, null);
    await _write(_kActiveRole, null);
    await _write(_kLastRoute, null);
    // 🔰 bersihkan cache user juga
    await _write(_kUserBuyer, null);
    await _write(_kUserSeller, null);
  }

  Future<String?> _readTokenForRole(String role) async {
    switch (role) {
      case 'seller': return _read(_kTokenSeller);
      case 'buyer':  return _read(_kTokenBuyer);
      default:       return null;
    }
  }

  Future<void> _writeTokenForRole(String role, String token) async {
    switch (role) {
      case 'seller': await _write(_kTokenSeller, token); break;
      case 'buyer':  await _write(_kTokenBuyer, token);  break;
    }
  }

  // =============================================================
  // Init / Hydrate session
  // =============================================================
  Future<void> hydrate() async => init();

  Future<void> init() async {
    _setInitializing(true);
    _setError(null);
    try {
      // role aktif
      _role  = (await _read(_kActiveRole)) ?? 'guest';
      // token untuk role aktif
      _token = await _readTokenForRole(_role);
      _lastRoute = await _read(_kLastRoute);

      // 🔰 restore cached user (jika ada) agar UI bisa langsung jalan
      final cachedUser = await _readUserMapForRole(_role);
      if (cachedUser != null) {
        _user = UserModel.fromJson(cachedUser);
      }

      // set ke API/TokenStore
      if (_token != null && _token!.isNotEmpty) {
        // pastikan header Authorization juga terpasang untuk API.dio
        API.dio.options.headers['Authorization'] = 'Bearer $_token';
        try { API.setBearer(_token!); } catch (_) {}
        _api.setAuthToken(_token);
        await TokenStore.write(_token!);
        // fetch profil (validasi token). bila sukses → simpan lagi ke cache user.
        await _fetchAndStoreMe();
      } else {
        _api.setAuthToken(null);
        await TokenStore.clear();
        _user = null;
      }
    } on DioException catch (e) {
      debugPrint('[AUTH] init DioException: ${e.response?.statusCode} -> ${e.response?.data}');
      if (e.response?.statusCode == 401) {
        await logout();
      }
    } catch (e) {
      debugPrint('[AUTH] init error: $e');
      await logout();
    } finally {
      _setInitializing(false);
    }
  }

  // =============================================================
  // Session control API (Single source of truth)
  // =============================================================
  Future<void> loadSession() => init();

  /// Simpan token+user untuk role aktif, set header Bearer, cache & notify
  Future<void> _saveSession(String token, Map<String, dynamic> userMap) async {
    final normRole = _normalizeRole(userMap['role'] ?? _role);
    _role = normRole;
    _token = token;

    // pasang bearer di semua layer
    API.dio.options.headers['Authorization'] = 'Bearer $token';
    try { API.setBearer(token); } catch (_) {}
    _api.setAuthToken(token);
    await TokenStore.write(token);

    // persist token & role
    await _writeTokenForRole(normRole, token);
    await _write(_kActiveRole, normRole);

    // cache user per role
    await _writeUserForRole(normRole, userMap);

    // set user model
    _user = UserModel.fromJson(userMap);

    // default route
    _lastRoute ??= _defaultRouteForRole(normRole);
    await _write(_kLastRoute, _lastRoute);

    _setError(null);
    notifyListeners();
  }

  /// Set token + role aktif, simpan ke storage & set header Authorization.
  Future<void> setSession({required String token, required String role}) async {
    final norm = _normalizeRole(role);
    _role  = norm;
    _token = token;

    await _writeTokenForRole(norm, token);
    await _write(_kActiveRole, norm);

    // pasang bearer di semua layer
    API.dio.options.headers['Authorization'] = 'Bearer $token';
    try { API.setBearer(token); } catch (_) {}
    _api.setAuthToken(token);
    await TokenStore.write(token);

    // Fetch profil setelah set sesi (akan men-cache user juga)
    await _fetchAndStoreMe(force: true);

    // Atur default route sesuai role
    final route = _defaultRouteForRole(_role);
    _lastRoute = route;
    await _write(_kLastRoute, route);

    notifyListeners();
  }

  /// Ganti role (misal buyer <-> seller). Mengatur header Authorization sesuai token role itu.
  Future<void> switchRole(String role) async {
    final norm = _normalizeRole(role);
    _role = norm;
    await _write(_kActiveRole, norm);

    _token = await _readTokenForRole(norm);
    if (_token != null && _token!.isNotEmpty) {
      API.dio.options.headers['Authorization'] = 'Bearer $_token';
      try { API.setBearer(_token!); } catch (_) {}
      _api.setAuthToken(_token);
      await TokenStore.write(_token!);

      // 🔰 coba pakai cached user dulu agar UI cepat
      final cachedUser = await _readUserMapForRole(_role);
      if (cachedUser != null) {
        _user = UserModel.fromJson(cachedUser);
        notifyListeners();
      }

      await _fetchAndStoreMe(force: true);
    } else {
      _api.setAuthToken(null);
      await TokenStore.clear();
      _user = null;
      // bersihkan header bearer
      API.dio.options.headers.remove('Authorization');
    }

    // lastRoute default sesuai role baru (jika belum ada)
    _lastRoute ??= _defaultRouteForRole(_role);
    await _write(_kLastRoute, _lastRoute);

    notifyListeners();
  }

  /// Logout total: hapus kedua token & role aktif
  Future<void> logout() async {
    try { await API.dio.post('auth/logout', options: Options(headers: {'Accept': 'application/json'})); } catch (_) {}
    _api.setAuthToken(null);
    await TokenStore.clear();
    await _clearAllTokens();

    _token = null;
    _role  = 'guest';
    _user  = null;
    _lastRoute = null;

    // hapus Authorization header global
    API.dio.options.headers.remove('Authorization');

    notifyListeners();
  }

  // =============================================================
  // Auth flows (RAPIKAN: pakai AuthApiService.login)
  // =============================================================
  /// Login via /auth/login (JSON only).
  Future<void> login({
    required String email,
    required String password,
    required String role, // 'buyer' | 'seller'
  }) async {
    if (_loggingIn) return;
    _loggingIn = true;
    _setLoading(true);
    _setError(null);

    try {
      // ✅ pakai AuthApiService → sudah kirim device_name & handle 4xx
      final data = await _authApi.login(email: email, password: password, role: role);
      final token = data['token'] as String;
      final user  = (data['user'] as Map?) ?? <String, dynamic>{};

      // ✅ simpan token & role + pasang Authorization (memenuhi poin #2)
      await _saveSession(token, Map<String, dynamic>.from(
        user.isNotEmpty ? user : {'role': role},
      ));
    } on DioException catch (e) {
      _setError(_extractDioErrorMessage(e, defaultMessage: 'Login gagal.'));
      rethrow;
    } catch (e) {
      _setError(e.toString());
      rethrow;
    } finally {
      _setLoading(false);
      _loggingIn = false;
    }
  }

  // =============================================================
  // Registrasi (tetap, tidak diubah)
  // =============================================================
  Future<bool> registerBuyer({
    required String name,
    required String email,
    required String password,
    String? passwordConfirmation,
    String? phone,
    String? address,
    String? city,
    String? postalCode,
  }) async {
    _setLoading(true);
    _setError(null);
    try {
      final body = <String, dynamic>{
        'name': name,
        'email': email,
        'password': password,
        if (passwordConfirmation != null) 'password_confirmation': passwordConfirmation,
        if (phone != null) 'phone': phone,
        if (address != null) 'address': address,
        if (city != null) 'city': city,
        if (postalCode != null) 'postal_code': postalCode,
      };

      final res = await API.postJson('auth/register-buyer', data: body);

      if ((res.statusCode ?? 500) >= 200 && (res.statusCode ?? 500) < 300) {
        final dynamic decoded = (res.data is String) ? jsonDecode(res.data) : res.data;
        final Map data = (decoded is Map) ? decoded : <String, dynamic>{};

        String? tok = (data['token'] ?? data['access_token'])?.toString();
        if ((tok == null || tok.isEmpty) && data['data'] is Map) {
          final d = data['data'] as Map;
          tok = (d['token'] ?? d['access_token'])?.toString();
        }

        if (tok != null && tok.isNotEmpty) {
          await setSession(token: tok, role: 'buyer');
          _setError(null);
          return true;
        }
        // fallback: login manual bila API register tidak auto-login
        await login(email: email, password: password, role: 'buyer');
        return true;
      } else {
        final bodyStr = res.data is String ? res.data as String : jsonEncode(res.data);
        _setError('HTTP ${res.statusCode}: $bodyStr');
        return false;
      }
    } on DioException catch (e) {
      _setError(_extractDioErrorMessage(e, defaultMessage: 'Registrasi buyer gagal.'));
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> registerSeller({
    required String name,
    required String email,
    required String password,
    required String passwordConfirmation,
    required String storeName,
    String? storeDescription,
    required String storeAddress,
    String? phone,
  }) async {
    _setLoading(true);
    _setError(null);
    try {
      final body = <String, dynamic>{
        'name': name,
        'email': email,
        'password': password,
        'password_confirmation': passwordConfirmation,
        'store_name': storeName,
        'store_address': storeAddress,
        if (storeDescription != null && storeDescription.isNotEmpty) 'store_description': storeDescription,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
      };

      final res = await API.postJson('auth/register-seller', data: body);

      if ((res.statusCode ?? 500) >= 200 && (res.statusCode ?? 500) < 300) {
        final dynamic decoded = (res.data is String) ? jsonDecode(res.data) : res.data;
        final Map data = (decoded is Map) ? decoded : <String, dynamic>{};

        String? tok = (data['token'] ?? data['access_token'])?.toString();
        if ((tok == null || tok.isEmpty) && data['data'] is Map) {
          final d = data['data'] as Map;
          tok = (d['token'] ?? d['access_token'])?.toString();
        }

        if (tok != null && tok.isNotEmpty) {
          await setSession(token: tok, role: 'seller');
          _setError(null);
          return true;
        }
        await login(email: email, password: password, role: 'seller');
        return true;
      } else {
        final bodyStr = res.data is String ? res.data as String : jsonEncode(res.data);
        _setError('HTTP ${res.statusCode}: $bodyStr');
        return false;
      }
    } on DioException catch (e) {
      _setError(_extractDioErrorMessage(e, defaultMessage: 'Registrasi seller gagal.'));
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // =============================================================
  // Profile / refresh
  // =============================================================
  Future<void> refreshMe({bool force = false}) async {
    _setLoading(true);
    await refreshMeOnce(force: force);
    _setLoading(false);
  }

  Future<void> refreshMeOnce({bool force = false}) async {
    if (_refreshing) return;
    final now = DateTime.now();
    if (!force && _lastRefreshAt != null && now.difference(_lastRefreshAt!) < const Duration(seconds: 45)) {
      return; // throttle 45s
    }
    _refreshing = true;
    try {
      await _fetchAndStoreMe();
      _lastRefreshAt = now;
    } on DioException catch (e) {
      debugPrint('[AUTH] refreshMeOnce DioException: ${e.response?.statusCode} -> ${e.message}');
      if (e.response?.statusCode == 401) {
        await logout();
      }
    } catch (e) {
      debugPrint('[AUTH] refreshMeOnce error: $e');
    } finally {
      _refreshing = false;
    }
  }

  /// ✅ Publik: fetch profil (alias memenuhi contoh pemanggilan)
  Future<void> fetchProfile() async => _fetchAndStoreMe(force: true);

  Future<void> _fetchAndStoreMe({bool force = false}) async {
    if (_token == null || _token!.isEmpty) {
      _user = null;
      return;
    }
    final res = await API.dio.get('auth/me', options: Options(headers: {'Accept':'application/json'}));
    final dynamic decoded = (res.data is String) ? jsonDecode(res.data) : res.data;
    final m = _extractUserMap(decoded);

    if (m != null) {
      _user = UserModel.fromJson(m);

      // === NEW: Samakan role dengan yang dilaporkan server & persist ===
      final apiRole = _normalizeRole(m['role'] ?? m['level'] ?? m['type']);
      if (apiRole == 'buyer' || apiRole == 'seller') {
        _role = apiRole;
        await _write(_kActiveRole, _role);
        // optional: pastikan default route sesuai role terkini
        _lastRoute ??= _defaultRouteForRole(_role);
        await _write(_kLastRoute, _lastRoute);
      }

      // 🔰 simpan cache user per role agar auto-restore instan saat app dibuka lagi
      await _writeUserForRole(_role, m);

      _setError(null);
      notifyListeners();
    } else {
      _setError('Data profil kosong dari server.');
    }
  }

  // =============================================================
  // Utilities
  // =============================================================
  String _normalizeRole(dynamic raw) {
    final s = (raw ?? '').toString().toLowerCase().trim();
    if (s.contains('sell') || s == 'seller' || s == 'penjual' || s == 'vendor') return 'seller';
    if (s == 'buyer' || s == 'pembeli' || s == 'customer' || s == 'user') return 'buyer';
    return 'buyer'; // default aman
  }

  String _defaultRouteForRole(dynamic r) {
    final role = _normalizeRole(r);
    return role == 'seller' ? '/seller/home' : '/home';
  }

  String _extractDioErrorMessage(DioException e, {String defaultMessage = 'Terjadi kesalahan.'}) {
    if (e.response?.data is Map) {
      final data = e.response!.data as Map;
      if (data['message'] is String && (data['message'] as String).isNotEmpty) return data['message'] as String;
      if (data['error'] is String && (data['error'] as String).isNotEmpty) return data['error'] as String;
      if (data['errors'] is Map && (data['errors'] as Map).isNotEmpty) {
        final first = (data['errors'] as Map).values.first;
        if (first is List && first.isNotEmpty) return first.first.toString();
        return first.toString();
      }
    }
    return e.message ?? defaultMessage;
  }

  Map<String, dynamic>? _extractUserMap(dynamic data) {
    if (data is Map<String, dynamic>) {
      if (data['user'] is Map) return Map<String, dynamic>.from(data['user'] as Map);
      if (data['data'] is Map) return Map<String, dynamic>.from(data['data'] as Map);
      return data;
    }
    return null;
  }

  // Opsional: simpan lastRoute dari FE
  Future<void> rememberLastRoute(String route) async {
    _lastRoute = route;
    await _write(_kLastRoute, route);
    notifyListeners();
  }

  // =============================================================
  // ✅ Pulihkan sesi saat app start — memenuhi poin #3
  // =============================================================
  Future<void> tryRestoreSession() async {
    _setInitializing(true);
    try {
      final savedRole  = (await _read(_kActiveRole)) ?? 'guest';
      if (savedRole == 'guest') { _setInitializing(false); return; }

      final savedToken = await _readTokenForRole(savedRole);
      if (savedToken == null || savedToken.isEmpty) { _setInitializing(false); return; }

      _role  = savedRole;
      _token = savedToken;

      // Pasang Bearer ke semua layer
      API.dio.options.headers['Authorization'] = 'Bearer $savedToken';
      try { API.setBearer(savedToken); } catch (_) {}
      _api.setAuthToken(savedToken);

      // Restore cached user agar UI bisa lanjut tanpa nunggu jaringan
      final cachedUser = await _readUserMapForRole(_role);
      if (cachedUser != null) {
        _user = UserModel.fromJson(cachedUser);
        notifyListeners();
      }
    } finally {
      // ← penting: jangan blok layar pertama
      _setInitializing(false);
    }

    // Sinkron profil di background (kalau offline, diam saja)
    // ignore: unawaited_futures
    _fetchAndStoreMe(force: true);
  }
}
