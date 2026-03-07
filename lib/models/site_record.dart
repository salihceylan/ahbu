class SiteRecord {
  const SiteRecord({
    required this.id,
    required this.name,
    required this.address,
    required this.city,
    required this.district,
    required this.createdAt,
  });

  final int id;
  final String name;
  final String? address;
  final String? city;
  final String? district;
  final DateTime? createdAt;

  factory SiteRecord.fromJson(Map<String, dynamic> json) {
    return SiteRecord(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      address: json['address'] as String?,
      city: json['city'] as String?,
      district: json['district'] as String?,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'] as String),
    );
  }

  String get summary {
    final parts = <String>[
      if ((district ?? '').isNotEmpty) district!,
      if ((city ?? '').isNotEmpty) city!,
    ];
    return parts.isEmpty ? 'Site' : parts.join(' / ');
  }
}
