import 'dart:io' show File;
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';

/// Saves picked images (web => data URL, mobile/desktop => local file path).
class ImageStorage {
  static Future<String?> savePicked(XFile file) async {
    if (kIsWeb) {
      final bytes = await file.readAsBytes();
      final mime = _guessMime(file.name);
      final b64 = base64Encode(bytes);
      return 'data:$mime;base64,$b64';
    } else {
      final dir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${dir.path}/images');
      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }
      final safeName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final dstPath =
          '${imagesDir.path}/${DateTime.now().millisecondsSinceEpoch}_$safeName';
      final dst = File(dstPath);
      final data = await file.readAsBytes();
      await dst.writeAsBytes(data, flush: true);
      return dst.path;
    }
  }

  static String _guessMime(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'application/octet-stream';
  }
}
