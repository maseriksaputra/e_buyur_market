// lib/app/core/web_secure_check.dart
// Memilih implementasi tergantung target platform.
import 'web_secure_check_default.dart'
    if (dart.library.html) 'web_secure_check_web.dart' as impl;

/// Di non-web: selalu true.
/// Di Web: true hanya jika context HTTPS (secure) & browser punya mediaDevices.
bool isSecureAndHasMedia() => impl.isSecureAndHasMedia();
