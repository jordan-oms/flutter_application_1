// model/info_chantier.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class LectureInfo {
  final String userId;
  final String userNomPrenom;
  final DateTime dateLecture;

  LectureInfo({
    required this.userId,
    required this.userNomPrenom,
    required this.dateLecture,
  });

  factory LectureInfo.fromJson(Map<String, dynamic> json) {
    return LectureInfo(
      userId: json['userId'] as String,
      userNomPrenom: json['userNomPrenom'] as String,
      dateLecture: (json['dateLecture'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'userNomPrenom': userNomPrenom,
      'dateLecture': Timestamp.fromDate(dateLecture),
    };
  }
}

class InfoChantier {
  final String id;
  final String tranche; // Pour lier l'info à une tranche
  final String contenu;
  final DateTime dateEmission;
  final String auteurIdCreation;
  final String auteurNomPrenomCreation;
  final String roleAuteurCreation;
  final List<LectureInfo> lectures; // Suivi des lectures

  InfoChantier({
    required this.id,
    required this.tranche,
    required this.contenu,
    required this.dateEmission,
    required this.auteurIdCreation,
    required this.auteurNomPrenomCreation,
    required this.roleAuteurCreation,
    this.lectures = const [],
  });

  factory InfoChantier.fromJson(Map<String, dynamic> json) {
    final lecturesData = json['lectures'] as List<dynamic>? ?? [];
    return InfoChantier(
      id: json['id'] as String,
      tranche: json['tranche'] as String,
      contenu: json['contenu'] as String,
      dateEmission: (json['dateEmission'] as Timestamp).toDate(),
      auteurIdCreation: json['auteurIdCreation'] as String,
      auteurNomPrenomCreation: json['auteurNomPrenomCreation'] as String,
      roleAuteurCreation: json['roleAuteurCreation'] as String,
      lectures: lecturesData
          .map((e) => LectureInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tranche': tranche,
      'contenu': contenu,
      'dateEmission': Timestamp.fromDate(dateEmission),
      // Conserve Timestamp pour Firestore
      'auteurIdCreation': auteurIdCreation,
      'auteurNomPrenomCreation': auteurNomPrenomCreation,
      'roleAuteurCreation': roleAuteurCreation,
      'lectures': lectures.map((l) => l.toJson()).toList(),
    };
  }

  // Ajout de la méthode copyWith
  InfoChantier copyWith({
    String? id,
    String? tranche,
    String? contenu,
    DateTime? dateEmission,
    String? auteurIdCreation,
    String? auteurNomPrenomCreation,
    String? roleAuteurCreation,
    List<LectureInfo>? lectures,
  }) {
    return InfoChantier(
      id: id ?? this.id,
      tranche: tranche ?? this.tranche,
      contenu: contenu ?? this.contenu,
      dateEmission: dateEmission ?? this.dateEmission,
      auteurIdCreation: auteurIdCreation ?? this.auteurIdCreation,
      auteurNomPrenomCreation:
          auteurNomPrenomCreation ?? this.auteurNomPrenomCreation,
      roleAuteurCreation: roleAuteurCreation ?? this.roleAuteurCreation,
      lectures: lectures ?? this.lectures,
    );
  }
}
