class User {
  // umum
  final int? id;
  final String? name;
  final String? email;
  final String? role;
  final String? phone;
  final String? address; // alamat buyer umum

  // seller fields
  final String? storeName;
  final String? storeDescription;
  final String? storeAddress; // bisa juga datang sebagai pickup_address

  // status & meta
  final bool? isVerified;
  final String? profilePictureUrl;
  final DateTime? dateOfBirth;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const User({
    this.id,
    this.name,
    this.email,
    this.role,
    this.phone,
    this.address,
    this.storeName,
    this.storeDescription,
    this.storeAddress,
    this.isVerified,
    this.profilePictureUrl,
    this.dateOfBirth,
    this.createdAt,
    this.updatedAt,
  });

  /// Parser toleran: menerima {user:{...}}, {data:{...}}, atau objek langsung.
  /// Untuk field toko, juga mencoba membaca dari nested `seller`.
  factory User.fromJson(Map<String, dynamic> j) {
    int? _int(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('$v');
    }

    String? _str(dynamic v) => v == null ? null : v.toString();

    bool? _bool(dynamic v) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) {
        final s = v.toLowerCase().trim();
        return s == '1' || s == 'true' || s == 'yes' || s == 'verified';
      }
      return null;
    }

    DateTime? _dt(dynamic v) {
      if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
      return null;
    }

    // Normalisasi root
    final Map<String, dynamic> m = (j['user'] is Map)
        ? Map<String, dynamic>.from(j['user'])
        : (j['data'] is Map)
            ? Map<String, dynamic>.from(j['data'])
            : j;

    // Jika server mengirim info seller di nested `seller`
    final Map<String, dynamic> seller = (m['seller'] is Map)
        ? Map<String, dynamic>.from(m['seller'])
        : const <String, dynamic>{};

    // Ambil variasi key untuk store*
    final String? _storeName = _str(
      m['store_name'] ??
          m['storeName'] ??
          seller['store_name'] ??
          seller['name'] ??
          m['shop_name'],
    );

    final String? _storeDesc = _str(
      m['store_description'] ??
          m['storeDesc'] ??
          seller['store_description'] ??
          seller['description'],
    );

    final String? _storeAddr = _str(
      m['store_address'] ??
          m['pickup_address'] ??
          seller['store_address'] ??
          seller['pickup_address'] ??
          seller['address'],
    );

    return User(
      id: _int(m['id']),
      name: _str(m['name']),
      email: _str(m['email']),
      role: _str(m['role'] ?? m['type'] ?? m['user_type']),
      phone: _str(m['phone'] ?? m['phone_number']),
      address: _str(m['address'] ?? m['shipping_address']),
      storeName: _storeName,
      storeDescription: _storeDesc,
      storeAddress: _storeAddr,
      isVerified:
          _bool(m['is_verified']) ?? (m['email_verified_at'] != null ? true : null),
      profilePictureUrl: _str(
        m['profile_picture_url'] ??
            m['profile_picture'] ??
            m['avatar_url'] ??
            m['avatar'],
      ),
      dateOfBirth: _dt(m['date_of_birth'] ?? m['dob']),
      createdAt: _dt(m['created_at']),
      updatedAt: _dt(m['updated_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'role': role,
        'phone': phone,
        'address': address,
        'store_name': storeName,
        'store_description': storeDescription,
        'store_address': storeAddress,
        'is_verified': isVerified,
        'profile_picture_url': profilePictureUrl,
        'date_of_birth': dateOfBirth?.toIso8601String(),
        'created_at': createdAt?.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
      };

  User copyWith({
    int? id,
    String? name,
    String? email,
    String? role,
    String? phone,
    String? address,
    String? storeName,
    String? storeDescription,
    String? storeAddress,
    bool? isVerified,
    String? profilePictureUrl,
    DateTime? dateOfBirth,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      storeName: storeName ?? this.storeName,
      storeDescription: storeDescription ?? this.storeDescription,
      storeAddress: storeAddress ?? this.storeAddress,
      isVerified: isVerified ?? this.isVerified,
      profilePictureUrl: profilePictureUrl ?? this.profilePictureUrl,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() =>
      'User(id:$id, name:$name, email:$email, role:$role, store:$storeName)';
}
