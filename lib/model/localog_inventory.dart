// lib/model/localog_inventory.dart

class LocalogInventory {
  final String qrCode;
  final String materiel;
  final String local;
  final String? validityDate;
  final String observations;
  final Map<String, dynamic> lastUpdatedBy;
  final String lastUpdatedAt;
  final DateTime lastUpdatedTime;
  final List<Map<String, dynamic>>? history;

  LocalogInventory({
    required this.qrCode,
    required this.materiel,
    required this.local,
    this.validityDate,
    required this.observations,
    required this.lastUpdatedBy,
    required this.lastUpdatedAt,
    required this.lastUpdatedTime,
    this.history,
  });

  Map<String, dynamic> toMap() {
    return {
      'qrCode': qrCode,
      'materiel': materiel,
      'local': local,
      'validityDate': validityDate,
      'observations': observations,
      'lastUpdatedBy': lastUpdatedBy,
      'lastUpdatedAt': lastUpdatedAt,
      'lastUpdatedTime': lastUpdatedTime,
      'history': history,
    };
  }

  factory LocalogInventory.fromMap(Map<String, dynamic> map) {
    return LocalogInventory(
      qrCode: map['qrCode'] ?? '',
      materiel: map['materiel'] ?? '',
      local: map['local'] ?? '',
      validityDate: map['validityDate'],
      observations: map['observations'] ?? '',
      lastUpdatedBy: map['lastUpdatedBy'] ?? {},
      lastUpdatedAt: map['lastUpdatedAt'] ?? '',
      lastUpdatedTime: map['lastUpdatedTime'] ?? DateTime.now(),
      history: map['history'] != null
          ? List<Map<String, dynamic>>.from(map['history'])
          : null,
    );
  }
}
