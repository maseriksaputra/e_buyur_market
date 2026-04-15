// lib/app/data/api_client.dart
import 'package:dio/dio.dart';
import '../core/env.dart';

final Dio dio = Dio(
  BaseOptions(
    baseUrl: Env.apiBase, // contoh: http://192.168.1.7:8000
    headers: {'Accept': 'application/json'},
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 12),
  ),
)..interceptors.add(LogInterceptor(requestBody: true, responseBody: true));
