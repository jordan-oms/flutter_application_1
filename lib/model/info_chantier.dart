// model/info_chantier.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class InfoChantier {
  final String id;
  final String tranche; // Pour lier l'info à une tranche
  final String contenu;
  final DateTime dateEmission;
  final String auteurIdCreation;
  final String auteurNomPrenomCreation;
  final String roleAuteurCreation;

  InfoChantier({
    required this.id,
    required this.tranche,
    required this.contenu,
    required this.dateEmission,
    required this.auteurIdCreation,
    required this.auteurNomPrenomCreation,
    required this.roleAuteurCreation,
  });

  factory InfoChantier.fromJson(Map<String, dynamic> json) {
    return InfoChantier(
      id: json['id'] as String,
      tranche: json['tranche'] as String,
      contenu: json['contenu'] as String,
      dateEmission: (json['dateEmission'] as Timestamp).toDate(),
      auteurIdCreation: json['auteurIdCreation'] as String,
      auteurNomPrenomCreation: json['auteurNomPrenomCreation'] as String,
      roleAuteurCreation: json['roleAuteurCreation'] as String,
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
  }) {
    return InfoChantier(
      id: id ?? this.id,
      tranche: tranche ?? this.tranche,
      contenu: contenu ?? this.contenu,
      dateEmission: dateEmission ?? this.dateEmission,
      auteurIdCreation: auteurIdCreation ?? this.auteurIdCreation,
      auteurNomPrenomCreation: auteurNomPrenomCreation ??
          this.auteurNomPrenomCreation,
      roleAuteurCreation: roleAuteurCreation ?? this.roleAuteurCreation,
    );
  }
}