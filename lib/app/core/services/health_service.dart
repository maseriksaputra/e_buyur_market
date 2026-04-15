// lib/app/core/services/health_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Single Dio khusus health-check.
/// Catatan:
/// - baseUrl bisa 'https://host' ATAU 'https://host/api'
/// - Karena semua request memakai path ABSOLUT (diawali '/'), join URL akan tetap benar.
///   Contoh:
///   baseUrl = https://host/api   + '/api/health' => https://host/api/health
///   baseUrl = https://host       + '/api/health' => https://host/api/health
final Dio _dio = Dio(
  BaseOptions(
    baseUrl: dotenv.get('API_BASE_URL', fallback: 'http://127.0.0.1:8000'),
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    headers: const {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    },
  ),
);

/// Ping endpoint kesehatan backend.
/// Backend Laravel umumnya berada di routes/api.php → GET /health
/// sehingga full path-nya adalah /api/health (prefix /api dari route file).
Future<Map<String, dynamic>> ping() async {
  // gunakan path absolut agar tidak bergantung format baseUrl
  final Response res = await _dio.get('/api/health');

  final data = res.data;
  if (data is Map<String, dynamic>) {
    return data;
  }
  return {
    'status': res.statusCode,
    'raw': data,
  };
}
