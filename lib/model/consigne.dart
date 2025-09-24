// model/consigne.dart
import 'package:cloud_firestore/cloud_firestore.dart' as fs; // Utilisation de l'alias fs
import 'package:flutter/foundation.dart';
import '/model/commentaire.dart'; // Assurez-vous que le chemin est correct

class Consigne {
  final String id;
  final String tranche;
  final String contenu;
  final DateTime dateEmission;
  final bool estPrioritaire;
  final String auteurIdCreation;
  final String auteurNomPrenomCreation;
  final String roleAuteurCreation;
  final String? categorie;
  final String? enjeu;
  final bool estValidee;
  final DateTime? dateValidation;
  final String? commentaireValidation;
  final String? idAuteurValidation;
  final List<Commentaire>? commentairesNonRealisation;
  final bool estNonRealiseeEffectivement;

  Consigne({
    required this.id,
    required this.tranche,
    required this.contenu,
    required this.dateEmission,
    this.estPrioritaire = false,
    required this.auteurIdCreation,
    required this.auteurNomPrenomCreation,
    required this.roleAuteurCreation,
    this.categorie,
    this.enjeu,
    this.estValidee = false,
    this.dateValidation,
    this.commentaireValidation,
    this.idAuteurValidation,
    this.commentairesNonRealisation,
    this.estNonRealiseeEffectivement = false,
  });

  factory Consigne.fromJson(Map<String, dynamic> json) {
    var rawCommentairesNonRealisation = json['commentairesNonRealisation'];
    List<Commentaire>? parsedCommentairesNonRealisation;
    if (rawCommentairesNonRealisation is List) {
      parsedCommentairesNonRealisation = rawCommentairesNonRealisation
          .map((data) => Commentaire.fromJson(data as Map<String, dynamic>))
          .toList();
    } else if (rawCommentairesNonRealisation is Map) {
      // Gérer l'ancien format si nécessaire
      try {
        parsedCommentairesNonRealisation = [
          Commentaire.fromJson(
              rawCommentairesNonRealisation as Map<String, dynamic>)
        ];
      } catch (e, s) { // Capture de l'exception et de la StackTrace
        debugPrint(
            "Erreur de désérialisation de l'ancien format de commentaireNonRealisation: $e\nStackTrace: $s");
      }
    }

    return Consigne(
      id: json['id'] as String,
      tranche: json['tranche'] as String,
      contenu: json['contenu'] as String,
      dateEmission: (json['dateEmission'] as fs.Timestamp).toDate(),
      // Utilisation de fs.Timestamp
      estPrioritaire: json['estPrioritaire'] as bool? ?? false,
      auteurIdCreation: json['auteurIdCreation'] as String,
      auteurNomPrenomCreation: json['auteurNomPrenomCreation'] as String,
      roleAuteurCreation: json['roleAuteurCreation'] as String,
      categorie: json['categorie'] as String?,
      enjeu: json['enjeu'] as String?,
      estValidee: json['estValidee'] as bool? ?? false,
      dateValidation: (json['dateValidation'] as fs.Timestamp?)?.toDate(),
      // Utilisation de fs.Timestamp?
      commentaireValidation: json['commentaireValidation'] as String?,
      idAuteurValidation: json['idAuteurValidation'] as String?,
      commentairesNonRealisation: parsedCommentairesNonRealisation,
      estNonRealiseeEffectivement:
      json['estNonRealiseeEffectivement'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tranche': tranche,
      'contenu': contenu,
      'dateEmission': fs.Timestamp.fromDate(dateEmission),
      // Utilisation de fs.Timestamp
      'estPrioritaire': estPrioritaire,
      'auteurIdCreation': auteurIdCreation,
      'auteurNomPrenomCreation': auteurNomPrenomCreation,
      'roleAuteurCreation': roleAuteurCreation,
      'categorie': categorie,
      'enjeu': enjeu,
      'estValidee': estValidee,
      'dateValidation': dateValidation != null
          ? fs.Timestamp.fromDate(
          dateValidation!) // Utilisation de fs.Timestamp
          : null,
      'commentaireValidation': commentaireValidation,
      'idAuteurValidation': idAuteurValidation,
      'commentairesNonRealisation': commentairesNonRealisation
          ?.map((commentaire) => commentaire.toJson())
          .toList(),
      'estNonRealiseeEffectivement': estNonRealiseeEffectivement,
    };
  }

  Consigne copyWith({
    String? id,
    String? tranche,
    String? contenu,
    DateTime? dateEmission,
    bool? estPrioritaire,
    String? auteurIdCreation,
    String? auteurNomPrenomCreation,
    String? roleAuteurCreation,
    String? categorie,
    dynamic enjeu,
    bool? estValidee,
    DateTime? dateValidation,
    String? commentaireValidation,
    String? idAuteurValidation,
    List<Commentaire>? commentairesNonRealisation,
    bool? estNonRealiseeEffectivement,
    bool clearCommentaireValidation = false,
    bool clearDateValidation = false,
    bool clearIdAuteurValidation = false,
    bool clearCommentairesNonRealisation = false,
  }) {
    return Consigne(
      id: id ?? this.id,
      tranche: tranche ?? this.tranche,
      contenu: contenu ?? this.contenu,
      dateEmission: dateEmission ?? this.dateEmission,
      estPrioritaire: estPrioritaire ?? this.estPrioritaire,
      auteurIdCreation: auteurIdCreation ?? this.auteurIdCreation,
      auteurNomPrenomCreation:
      auteurNomPrenomCreation ?? this.auteurNomPrenomCreation,
      roleAuteurCreation: roleAuteurCreation ?? this.roleAuteurCreation,
      categorie: categorie ?? this.categorie,
      enjeu: (enjeu is Function) ? enjeu() : (enjeu ?? this.enjeu) as String?,
      estValidee: estValidee ?? this.estValidee,
      dateValidation: clearDateValidation
          ? null
          : (dateValidation ??
          ((estValidee != null && !estValidee)
              ? null
              : this.dateValidation)),
      commentaireValidation: clearCommentaireValidation
          ? null
          : commentaireValidation ?? this.commentaireValidation,
      idAuteurValidation: clearIdAuteurValidation
          ? null
          : (idAuteurValidation ?? this.idAuteurValidation),
      commentairesNonRealisation: clearCommentairesNonRealisation
          ? null
          : commentairesNonRealisation ?? this.commentairesNonRealisation,
      estNonRealiseeEffectivement:
      estNonRealiseeEffectivement ?? this.estNonRealiseeEffectivement,
    );
  }
}