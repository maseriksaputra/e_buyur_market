// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

bool isSecureAndHasMedia() {
  // isSecureContext bertipe bool?, jadi pakai == true agar jadi bool non-null
  final bool secure = html.window.isSecureContext == true;
  // mediaDevices bertipe MediaDevices?, cek != null menghasilkan bool non-null
  final bool hasMedia = html.window.navigator.mediaDevices != null;
  return secure && hasMedia;
}
