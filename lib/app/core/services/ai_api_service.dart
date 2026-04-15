// lib/app/core/services/ai_api_service.dart
import 'dart:async';
import 'dart:convert' show jsonDecode;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http_parser/http_parser.dart'; // MediaType('image','jpeg')

class AiApiService {
  AiApiService({Dio? dio, String? baseUrl})
      : _dio = dio ??
            Dio(
              BaseOptions(
                // base sudah dinormalisasi (auto tambah /api/ dan trailing slash)
                baseUrl: _normalizeBase(baseUrl ?? _defaultBaseUrl),
                // ⬇️ Timeout default
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 45),
                headers: const {
                  'Accept': 'application/json',
                  'X-Requested-With': 'XMLHttpRequest',
                },
                followRedirects: false,
                // Jangan buat global validateStatus true — kita set per-request
              ),
            );

  final Dio _dio;

  /// Base URL default (akan dinormalisasi)
  static String get _defaultBaseUrl {
    const defined = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://api.ebuyurmarket.com',
    );
    if (kReleaseMode) return defined;
    return defined.isNotEmpty ? defined : 'http://10.0.2.2:8000';
  }

  /// Normalisasi base:
  /// - buang trailing '/'
  /// - sisipkan '/api' bila belum ada
  /// - pastikan diakhiri '/'
  static String _normalizeBase(String raw) {
    var cleaned = raw.trim().replaceFirst(RegExp(r'/+$'), '');
    final hasApi =
        RegExp(r'(^|/)(api)(/|$)', caseSensitive: false).hasMatch(cleaned);
    if (!hasApi) cleaned = '$cleaned/api';
    return '$cleaned/';
  }

  // ========= Flexible extractors (untuk berbagai bentuk payload) =========

  static String? _pickLabel(Map m) {
    for (final k in ['label', 'detected_item', 'name', 'class', 'prediction']) {
      final v = (m[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return null;
  }

  static double? _pickDouble(Map m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is num) return v.toDouble();
      final s = (v ?? '').toString();
      final d = double.tryParse(s);
      if (d != null) return d;
    }
    return null;
  }

  static double? _pickQuality01(Map data) {
    final d = _pickDouble(data, ['quality', 'quality_score', 'quality01']);
    if (d != null) return d > 1 ? (d / 100.0).clamp(0.0, 1.0) : d.clamp(0.0, 1.0);
    final sp = _pickDouble(data, ['suitability_percent', 'suitability', 'score_percent']);
    if (sp != null) return (sp / 100.0).clamp(0.0, 1.0);
    return null;
  }

  static int? _pickSuitabilityPct(Map data) {
    final sp = _pickDouble(data, ['suitability_percent', 'suitability', 'score_percent']);
    if (sp != null) {
      final v = sp <= 1 ? (sp * 100.0) : sp;
      return v.round().clamp(0, 100);
    }
    final q01 = _pickQuality01(data);
    if (q01 != null) return (q01 * 100).round().clamp(0, 100);
    return null;
  }

  static bool? _pickIsProduce(Map data) {
    final keys = ['is_fruit_or_vegi', 'is_fruit_or_veg', 'is_produce'];
    for (final k in keys) {
      final v = data[k];
      if (v is bool) return v;
      if (v is String) {
        final s = v.toLowerCase().trim();
        if (s == 'true' || s == '1') return true;
        if (s == 'false' || s == '0') return false;
      }
      if (v is num) return v != 0;
    }
    return null;
  }

  /// Parser aman menjadi Map
  Map<String, dynamic> _toMap(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String) {
      try {
        final j = jsonDecode(data);
        if (j is Map) return Map<String, dynamic>.from(j);
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  /// POST /api/ai/gemini/validate-image
  ///
  /// ✅ Perbaikan:
  /// - validateStatus: (s) => true → tidak throw untuk 4xx/5xx
  /// - followRedirects: false → bila server kirim HTML redirect, kita tangkap & kembalikan error map
  /// - responseType: ResponseType.json (tetap graceful kalau server kirim string/HTML)
  /// - Retry ringan untuk timeout/429/503
  Future<Map<String, dynamic>> validateImage(
    Uint8List jpegBytes, {
    String? bearerToken,
    Map<String, dynamic>? meta,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'X-Requested-With': 'XMLHttpRequest',
    };
    if (bearerToken != null && bearerToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $bearerToken';
    }

    // FormData dari bytes aman direuse untuk 1 retry karena bukan stream file.
    final form = FormData.fromMap({
      'image': MultipartFile.fromBytes(
        jpegBytes,
        filename: 'scan.jpg',
        contentType: MediaType('image', 'jpeg'),
      ),
      if (meta != null) ...meta,
    });

    const int maxAttempts = 2; // 1 retry
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final res = await _dio.post(
          'ai/gemini/validate-image',
          data: form,
          options: Options(
            headers: headers,
            contentType: 'multipart/form-data',
            followRedirects: false,
            validateStatus: (s) => true,           // ✅ JANGAN THROW utk 4xx/5xx
            responseType: ResponseType.json,       // ✅ prefer JSON
            // request-level timeouts
            sendTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(seconds: 20),
          ),
        );

        final status = res.statusCode ?? 0;
        final ctype = (res.headers.value('content-type') ?? '').toLowerCase();

        // Deteksi HTML/redirect
        final dataAny = res.data;
        final bodyStr = dataAny?.toString() ?? '';
        final isHtml = ctype.contains('text/html') ||
            (dataAny is String && (dataAny.contains('<!DOCTYPE html') || dataAny.contains('<html')));

        if (status >= 300 && status < 400 || isHtml) {
          return {
            'status': 'error',
            'error': isHtml ? 'html_response' : 'redirect',
            'error_code': status == 0 ? 502 : status,
            'message': isHtml
                ? 'Server mengembalikan HTML (kemungkinan redirect ke halaman web).'
                : 'Server melakukan redirect.',
            'raw': bodyStr,
          };
        }

        // Graceful parse ke Map
        final body = _toMap(res.data);

        // Bila HTTP bukan 200/201 → kembalikan error terstruktur (tanpa throw)
        if (status != 200 && status != 201) {
          return {
            'status': 'error',
            'error': status == 429
                ? 'rate_limited'
                : status == 503
                    ? 'service_busy'
                    : 'server_error',
            'error_code': status,
            'raw': body.isNotEmpty ? body : {'text': bodyStr},
          };
        }

        // ==== Sukses (200/201) → normalisasi output ke skema yang dipakai FE ====
        Map<String, dynamic> result = {};
        if (body['result'] is Map) {
          result = Map<String, dynamic>.from(body['result'] as Map);
        }
        Map<String, dynamic> rawRes = {};
        if (body['raw'] is Map && (body['raw'] as Map)['result'] is Map) {
          rawRes = Map<String, dynamic>.from((body['raw'] as Map)['result'] as Map);
        }

        // pilih core dengan isi paling berguna
        Map<String, dynamic> core = result;
        final hasCore = core.values.any((v) {
          if (v is num) return v != 0;
          if (v is String) return v.trim().isNotEmpty;
          if (v is bool) return true;
          return false;
        });
        if (!hasCore && rawRes.isNotEmpty) core = rawRes;

        final llmLabel = _pickLabel(core);
        double conf = _pickDouble(core, ['confidence', 'conf', 'score', 'prob']) ?? 0.0;
        if (conf > 1.0) conf = (conf / 100.0).clamp(0.0, 1.0);

        final q01 = _pickQuality01(core) ?? 0.0;
        final suitPct = _pickSuitabilityPct(core) ?? (q01 * 100).round();
        final isProduce = _pickIsProduce(core);

        return <String, dynamic>{
          'status': 'success',
          'detected_item': llmLabel,
          'confidence': conf,             // 0..1
          'quality_score': q01,           // 0..1
          'suitability_percent': suitPct, // 0..100
          if (isProduce != null) 'is_fruit_or_vegi': isProduce,
          'raw': body.isNotEmpty ? body : {'text': bodyStr},
        };
      } on DioException catch (e) {
        // Hanya network/timeout yang sampai sini (4xx/5xx tidak karena validateStatus: true)
        final code = e.response?.statusCode ?? 0;
        final body = _toMap(e.response?.data);
        final isTimeout = e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout;
        final isRetriable = isTimeout || code == 429 || code == 503;

        if (attempt < maxAttempts && isRetriable) {
          // Backoff singkat: 0.6s, lalu 1.2s
          final backoffMs = (600 * attempt);
          await Future.delayed(Duration(milliseconds: backoffMs));
          continue;
        }

        if (isTimeout) {
          return {
            'status': 'error',
            'error_code': 504,
            'error': 'timeout',
            'raw': body.isNotEmpty ? body : null,
          };
        }

        if (code == 429 || code == 503) {
          return {
            'status': 'error',
            'error': code == 429 ? 'rate_limited' : 'service_busy',
            'error_code': code,
            'raw': body.isNotEmpty ? body : null,
          };
        }

        String msg;
        switch (e.type) {
          case DioExceptionType.connectionTimeout:
          case DioExceptionType.sendTimeout:
          case DioExceptionType.receiveTimeout:
            msg = 'Koneksi ke server timeout';
            break;
          case DioExceptionType.badResponse:
            msg = 'HTTP $code: ${e.response?.data}';
            break;
          default:
            msg = e.message ?? 'Gagal terhubung ke server';
        }
        return {
          'status': 'error',
          'error_code': code == 0 ? 500 : code,
          'error': 'service_error',
          'message': msg,
          'raw': body.isNotEmpty ? body : null,
        };
      }
    }

    // fallback jika loop keluar tanpa return
    return {
      'status': 'error',
      'error_code': 500,
      'error': 'unknown_error',
      'message': 'Tidak dapat memproses permintaan LLM.',
    };
  }
}
