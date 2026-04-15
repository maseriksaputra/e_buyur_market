// lib/app/core/services/buyer_stats_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class BuyerStatsService {
  static const String _base = String.fromEnvironment('API_BASE',
      defaultValue: 'http://192.168.110.99:8000');

  static Future<Map<String, dynamic>> fetchStats(
      {required String? token}) async {
    final uri = Uri.parse('$_base/api/buyer/stats');

    final headers = <String, String>{
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };

    final res = await http.get(uri, headers: headers);
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return (body['data'] as Map<String, dynamic>);
    } else if (res.statusCode == 401) {
      throw UnauthorizedException();
    } else {
      throw Exception('Gagal memuat stats (${res.statusCode})');
    }
  }
}

class UnauthorizedException implements Exception {}
