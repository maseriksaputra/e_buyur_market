// lib/app/core/env.dart
class Env {
  /// Ubah via: --dart-define="API_BASE=http://192.168.1.7:8000"
  static const apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://192.168.1.7:8000',
  );
}
