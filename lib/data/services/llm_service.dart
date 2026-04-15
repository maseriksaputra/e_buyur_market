import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class GeminiLLM {
  GeminiLLM(this.apiKey);
  final String apiKey;

  // ✅ Utama: 2.5 Flash
  static const _primary = 'gemini-2.5-flash';

  // ✅ Fallback berjenjang agar tetap jalan jika model utama tak tersedia di region/kuota
  static const _fallbacks = <String>[
    'gemini-2.0-flash',
    'gemini-1.5-flash',
    'gemini-1.5-flash-8b',
    'gemini-1.5-flash-001',
    'gemini-1.0-pro-vision-latest',
  ];

  Future<String?> generateForImage({
    required Uint8List imageBytes,
    required String prompt,
    String mimeType = 'image/jpeg',
  }) async {
    final models = <String>[_primary, ..._fallbacks];
    Object? lastErr;

    for (final m in models) {
      try {
        final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1/models/$m:generateContent?key=$apiKey',
        );

        final body = {
          "contents": [
            {
              "parts": [
                {"text": prompt},
                {
                  "inline_data": {
                    "mime_type": mimeType,
                    "data": base64Encode(imageBytes),
                  }
                }
              ]
            }
          ]
        };

        final res = await http.post(
          uri,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(body),
        );

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final text = (data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?)?.trim();
          return text;
        }

        // 404/405 → coba fallback berikutnya; error lain hentikan loop
        lastErr = 'HTTP ${res.statusCode}: ${res.body}';
        if (res.statusCode == 404 || res.statusCode == 405) continue;
        break;
      } catch (e, st) {
        if (kDebugMode) print('[GeminiLLM] model=$m error: $e\n$st');
        lastErr = e;
      }
    }

    throw Exception(lastErr ?? 'LLM tidak tersedia');
  }
}
