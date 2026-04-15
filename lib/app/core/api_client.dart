// lib/core/api_client.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final int? status;
  final String message;
  ApiException(this.message, {this.status});
  factory ApiException.fromResponse(http.Response r) {
    try {
      final m = json.decode(r.body);
      final msg = m['error']?['message'] ?? m['message'] ?? 'HTTP ${r.statusCode}';
      return ApiException(msg, status: r.statusCode);
    } catch (_) {
      return ApiException('HTTP ${r.statusCode}', status: r.statusCode);
    }
  }
}

class ApiClient {
  ApiClient(this.baseUrl, {this.readToken});
  final String baseUrl;
  final Future<String?> Function()? readToken; // contoh: () async => storage.read('token')

  Future<Map<String, String>> _headers() async {
    final t = await (readToken?.call() ?? Future.value(null));
    return {
      'Content-Type': 'application/json',
      if (t != null && t.isNotEmpty) 'Authorization': 'Bearer $t',
    };
  }

  Future<dynamic> get(String path) async {
    final r = await http.get(Uri.parse('$baseUrl$path'), headers: await _headers());
    if (r.statusCode >= 200 && r.statusCode < 300) return json.decode(r.body);
    throw ApiException.fromResponse(r);
  }

  Future<dynamic> post(String path, Map<String, dynamic> body) async {
    final r = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: await _headers(),
      body: json.encode(body),
    );
    if (r.statusCode >= 200 && r.statusCode < 300) return json.decode(r.body);
    throw ApiException.fromResponse(r);
  }

  Future<dynamic> delete(String path) async {
    final r = await http.delete(Uri.parse('$baseUrl$path'), headers: await _headers());
    if (r.statusCode >= 200 && r.statusCode < 300) return json.decode(r.body);
    throw ApiException.fromResponse(r);
  }
}
