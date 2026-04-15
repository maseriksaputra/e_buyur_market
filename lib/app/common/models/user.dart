import 'dart:convert';

class User {
  final int? id;
  final String? name;
  final String? email;
  final String? role;

  User({this.id, this.name, this.email, this.role});

  /// Parser utama dari Map
  factory User.fromJson(Map<String, dynamic> json) {
    int? _parseId(dynamic v) {
      if (v is int) return v;
      if (v is String) return int.tryParse(v);
      return null;
    }

    return User(
      id: _parseId(json['id']),
      name: json['name'] as String?,
      email: json['email'] as String?,
      role: json['role'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'role': role,
      };

  /// (Opsional) Helper aman untuk berbagai bentuk payload
  /// - {'user': {...}} atau {'data': {'user': {...}}} atau langsung {...}
  static User? fromAny(dynamic any) {
    if (any == null) return null;

    if (any is String) {
      try {
        final decoded = jsonDecode(any);
        return fromAny(decoded);
      } catch (_) {
        return null;
      }
    }

    if (any is Map<String, dynamic>) {
      final u = any['user'];
      if (u is Map) return User.fromJson(Map<String, dynamic>.from(u));
      final d = any['data'];
      if (d is Map && d['user'] is Map) {
        return User.fromJson(Map<String, dynamic>.from(d['user'] as Map));
      }
      // kalau payload langsung berisi user fields
      return User.fromJson(any);
    }

    if (any is Map) {
      return User.fromJson(Map<String, dynamic>.from(any));
    }

    return null;
  }
}
