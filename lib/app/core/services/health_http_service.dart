import 'dart:convert';
import 'package:http/http.dart' as http;

Future<Map<String, dynamic>> pingHttp() async {
  final uri = Uri.https('api.ebuyurmarket.com', '/api/health');
  final res = await http.get(uri, headers: {'Accept': 'application/json'});
  if (res.statusCode != 200) {
    throw Exception('HTTP ${res.statusCode}: ${res.body}');
  }
  return json.decode(res.body) as Map<String, dynamic>;
}
