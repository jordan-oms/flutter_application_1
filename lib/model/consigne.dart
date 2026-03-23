// lib/model/consigne.dart

import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:flutter/foundation.dart';
import '/model/commentaire.dart';

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
  final String? nomPrenomValidation; // Stocke le Nom Prénom de celui qui valide
  final List<Commentaire>? commentairesNonRealisation;
  final bool estNonRealiseeEffectivement;
  final String? dosimetrieInfo;

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
    this.nomPrenomValidation,
    this.commentairesNonRealisation,
    this.estNonRealiseeEffectivement = false,
    this.dosimetrieInfo,
  });

  factory Consigne.fromJson(Map<String, dynamic> json) {
    var rawCommentairesNonRealisation = json['commentairesNonRealisation'];
    List<Commentaire>? parsedCommentairesNonRealisation;
    if (rawCommentairesNonRealisation is List) {
      parsedCommentairesNonRealisation = rawCommentairesNonRealisation
          .map((data) => Commentaire.fromJson(data as Map<String, dynamic>))
          .toList();
    }

    return Consigne(
      id: json['id'] as String,
      tranche: json['tranche'] as String,
      contenu: json['contenu'] as String,
      dateEmission: (json['dateEmission'] as fs.Timestamp).toDate(),
      estPrioritaire: json['estPrioritaire'] as bool? ?? false,
      auteurIdCreation: json['auteurIdCreation'] as String,
      auteurNomPrenomCreation: json['auteurNomPrenomCreation'] as String,
      roleAuteurCreation: json['roleAuteurCreation'] as String,
      categorie: json['categorie'] as String?,
      enjeu: json['enjeu'] as String?,
      estValidee: json['estValidee'] as bool? ?? false,
      dateValidation: (json['dateValidation'] as fs.Timestamp?)?.toDate(),
      commentaireValidation: json['commentaireValidation'] as String?,
      idAuteurValidation: json['idAuteurValidation'] as String?,
      nomPrenomValidation: json['nomPrenomValidation'] as String?,
      commentairesNonRealisation: parsedCommentairesNonRealisation,
      estNonRealiseeEffectivement:
          json['estNonRealiseeEffectivement'] as bool? ?? false,
      dosimetrieInfo: json['dosimetrieInfo'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tranche': tranche,
      'contenu': contenu,
      'dateEmission': fs.Timestamp.fromDate(dateEmission),
      'estPrioritaire': estPrioritaire,
      'auteurIdCreation': auteurIdCreation,
      'auteurNomPrenomCreation': auteurNomPrenomCreation,
      'roleAuteurCreation': roleAuteurCreation,
      'categorie': categorie,
      'enjeu': enjeu,
      'estValidee': estValidee,
      'dateValidation': dateValidation != null
          ? fs.Timestamp.fromDate(dateValidation!)
          : null,
      'commentaireValidation': commentaireValidation,
      'idAuteurValidation': idAuteurValidation,
      'nomPrenomValidation': nomPrenomValidation,
      'commentairesNonRealisation':
          commentairesNonRealisation?.map((c) => c.toJson()).toList(),
      'estNonRealiseeEffectivement': estNonRealiseeEffectivement,
      'dosimetrieInfo': dosimetrieInfo,
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
    String? nomPrenomValidation,
    List<Commentaire>? commentairesNonRealisation,
    bool? estNonRealiseeEffectivement,
    String? dosimetrieInfo,
    bool clearDosimetrieInfo = false,
    bool clearCommentaireValidation = false,
    bool clearDateValidation = false,
    bool clearIdAuteurValidation = false,
    bool clearNomPrenomValidation = false,
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
      dateValidation:
          clearDateValidation ? null : (dateValidation ?? this.dateValidation),
      commentaireValidation: clearCommentaireValidation
          ? null
          : (commentaireValidation ?? this.commentaireValidation),
      idAuteurValidation: clearIdAuteurValidation
          ? null
          : (idAuteurValidation ?? this.idAuteurValidation),
      nomPrenomValidation: clearNomPrenomValidation
          ? null
          : (nomPrenomValidation ?? this.nomPrenomValidation),
      commentairesNonRealisation: clearCommentairesNonRealisation
          ? []
          : (commentairesNonRealisation ?? this.commentairesNonRealisation),
      estNonRealiseeEffectivement:
          estNonRealiseeEffectivement ?? this.estNonRealiseeEffectivement,
      dosimetrieInfo:
          clearDosimetrieInfo ? null : (dosimetrieInfo ?? this.dosimetrieInfo),
    );
  }
}
