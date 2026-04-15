// lib/app/core/network/http_helpers.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

// AuthProvider kamu
import 'package:e_buyur_market_flutter_5/app/presentation/providers/auth_provider.dart'
    as auth;

/// ====== PUBLIC HELPERS ======
/// Semua request endpoint yang butuh token sebaiknya lewat fungsi-fungsi ini.
/// 401/419 akan auto-logout + redirect ke '/login'.

Future<http.Response> authedGet(
  BuildContext context,
  Uri uri, {
  Map<String, String>? headers,
}) async {
  final h = await _authHeaders(context, headers: headers);
  final res = await http.get(uri, headers: h);
  await _checkUnauthorized(context, res.statusCode);
  return res;
}

Future<http.Response> authedDelete(
  BuildContext context,
  Uri uri, {
  Map<String, String>? headers,
}) async {
  final h = await _authHeaders(context, headers: headers);
  final res = await http.delete(uri, headers: h);
  await _checkUnauthorized(context, res.statusCode);
  return res;
}

Future<http.Response> authedPost(
  BuildContext context,
  Uri uri, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) async {
  final h = await _authHeaders(context, headers: headers);
  final res = await http.post(uri, headers: h, body: body, encoding: encoding);
  await _checkUnauthorized(context, res.statusCode);
  return res;
}

Future<http.Response> authedPut(
  BuildContext context,
  Uri uri, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) async {
  final h = await _authHeaders(context, headers: headers);
  final res = await http.put(uri, headers: h, body: body, encoding: encoding);
  await _checkUnauthorized(context, res.statusCode);
  return res;
}

Future<http.Response> authedPatch(
  BuildContext context,
  Uri uri, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) async {
  final h = await _authHeaders(context, headers: headers);
  final res = await http.patch(uri, headers: h, body: body, encoding: encoding);
  await _checkUnauthorized(context, res.statusCode);
  return res;
}

/// JSON helpers (auto set Content-Type: application/json)
Future<http.Response> authedPostJson(
  BuildContext context,
  Uri uri,
  Map<String, dynamic> jsonBody, {
  Map<String, String>? headers,
}) {
  final merged = <String, String>{
    'Content-Type': 'application/json',
    ...?headers,
  };
  return authedPost(context, uri, headers: merged, body: jsonEncode(jsonBody));
}

Future<http.Response> authedPutJson(
  BuildContext context,
  Uri uri,
  Map<String, dynamic> jsonBody, {
  Map<String, String>? headers,
}) {
  final merged = <String, String>{
    'Content-Type': 'application/json',
    ...?headers,
  };
  return authedPut(context, uri, headers: merged, body: jsonEncode(jsonBody));
}

/// Multipart helper (JANGAN set Content-Type manual—biar MultipartRequest yang set)
Future<http.StreamedResponse> authedMultipart(
  BuildContext context,
  Uri uri, {
  Map<String, String>? fields,
  List<http.MultipartFile>? files,
  Map<String, String>? headers,
  String method = 'POST', // POST / PUT
}) async {
  final h = await _authHeaders(context, headers: headers, forMultipart: true);
  final req = http.MultipartRequest(method, uri)..headers.addAll(h);
  if (fields != null && fields.isNotEmpty) req.fields.addAll(fields);
  if (files != null && files.isNotEmpty) req.files.addAll(files);
  final res = await req.send();

  await _checkUnauthorized(context, res.statusCode);
  return res;
}

/// ====== INTERNAL ======

Future<Map<String, String>> _authHeaders(
  BuildContext context, {
  Map<String, String>? headers,
  bool forMultipart = false,
}) async {
  final Map<String, String> base = {
    'Accept': 'application/json',
  };

  // Content-Type otomatis untuk JSON; untuk Multipart jangan diset manual
  if (!forMultipart) {
    base.putIfAbsent('Content-Type', () => 'application/json');
  }

  // Ambil token: primary dari AuthProvider, fallback dari .env
  String? token;
  try {
    final ap = Provider.of<auth.AuthProvider>(context, listen: false);
    final t = (ap as dynamic).token;
    if (t is String && t.trim().isNotEmpty) token = t.trim();
  } catch (_) {}

  token ??= dotenv.maybeGet('API_BEARER')?.trim();

  if (token != null && token.isNotEmpty) {
    base['Authorization'] = 'Bearer $token';
  }

  // Merge custom headers
  if (headers != null && headers.isNotEmpty) {
    base.addAll(headers);
  }
  return base;
}

Future<void> _checkUnauthorized(BuildContext context, int statusCode) async {
  if (statusCode == 401 || statusCode == 419) {
    // 1) coba logout/clear session di AuthProvider
    try {
      final ap = Provider.of<auth.AuthProvider>(context, listen: false);
      // dukung berbagai nama method yang mungkin ada
      try {
        await (ap as dynamic).logout();
      } catch (_) {}
      try {
        await (ap as dynamic).clearSession();
      } catch (_) {}
      try {
        (ap as dynamic).setToken(null);
      } catch (_) {}
    } catch (_) {}

    // 2) redirect aman ke /login
    Future.microtask(() {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
      } else {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
      }
    });
  }
}
