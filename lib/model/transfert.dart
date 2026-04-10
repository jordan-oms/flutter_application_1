// lib/model/transfert.dart

import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:flutter/foundation.dart';
import '/model/commentaire.dart';

class Transfert {
  final String id;
  final String tranche;
  final List<String>? tranchesVisibles;
  final String contenu;
  final DateTime dateEmission;
  final bool estPrioritaire;
  final String auteurIdCreation;
  final String auteurNomPrenomCreation;
  final String roleAuteurCreation;
  final bool estValidee;
  final DateTime? dateValidation;
  final String? commentaireValidation;
  final String? idAuteurValidation;
  final String? nomPrenomValidation;
  final List<Commentaire>? commentairesNonRealisation;
  final bool estNonRealiseeEffectivement;
  final String? dosimetrieInfo;
  // Nouveaux champs pour les transferts
  final String? lieuDepart;
  final String? lieuArrivee;
  final DateTime? heureDepart;
  final DateTime? heureDepartReel;
  final DateTime? heureArriveeReel;

  Transfert({
    required this.id,
    required this.tranche,
    this.tranchesVisibles,
    required this.contenu,
    required this.dateEmission,
    this.estPrioritaire = false,
    required this.auteurIdCreation,
    required this.auteurNomPrenomCreation,
    required this.roleAuteurCreation,
    this.estValidee = false,
    this.dateValidation,
    this.commentaireValidation,
    this.idAuteurValidation,
    this.nomPrenomValidation,
    this.commentairesNonRealisation,
    this.estNonRealiseeEffectivement = false,
    this.dosimetrieInfo,
    this.lieuDepart,
    this.lieuArrivee,
    this.heureDepart,
    this.heureDepartReel,
    this.heureArriveeReel,
  });

  factory Transfert.fromJson(Map<String, dynamic> json) {
    DateTime? toDateTime(dynamic value) {
      if (value == null) return null;
      if (value is fs.Timestamp) return value.toDate();
      if (value is DateTime) return value;
      return null;
    }

    var rawCommentairesNonRealisation = json['commentairesNonRealisation'];
    List<Commentaire>? parsedCommentairesNonRealisation;
    if (rawCommentairesNonRealisation is List) {
      parsedCommentairesNonRealisation = rawCommentairesNonRealisation
          .map((data) => Commentaire.fromJson(data as Map<String, dynamic>))
          .toList();
    }

    return Transfert(
      id: json['id']?.toString() ?? '',
      tranche: json['tranche']?.toString() ?? '',
      tranchesVisibles: (json['tranchesVisibles'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      contenu: json['contenu']?.toString() ?? '',
      dateEmission: toDateTime(json['dateEmission']) ?? DateTime.now(),
      estPrioritaire: json['estPrioritaire'] == true,
      auteurIdCreation: json['auteurIdCreation']?.toString() ?? '',
      auteurNomPrenomCreation:
          json['auteurNomPrenomCreation']?.toString() ?? '',
      roleAuteurCreation: json['roleAuteurCreation']?.toString() ?? '',
      estValidee: json['estValidee'] == true,
      dateValidation: toDateTime(json['dateValidation']),
      commentaireValidation: json['commentaireValidation']?.toString(),
      idAuteurValidation: json['idAuteurValidation']?.toString(),
      nomPrenomValidation: json['nomPrenomValidation']?.toString(),
      commentairesNonRealisation: parsedCommentairesNonRealisation,
      estNonRealiseeEffectivement: json['estNonRealiseeEffectivement'] == true,
      dosimetrieInfo: json['dosimetrieInfo']?.toString(),
      lieuDepart: json['lieuDepart']?.toString(),
      lieuArrivee: json['lieuArrivee']?.toString(),
      heureDepart: toDateTime(json['heureDepart']),
      heureDepartReel: toDateTime(json['heureDepartReel']),
      heureArriveeReel: toDateTime(json['heureArriveeReel']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tranche': tranche,
      'tranchesVisibles': tranchesVisibles,
      'contenu': contenu,
      'dateEmission': fs.Timestamp.fromDate(dateEmission),
      'estPrioritaire': estPrioritaire,
      'auteurIdCreation': auteurIdCreation,
      'auteurNomPrenomCreation': auteurNomPrenomCreation,
      'roleAuteurCreation': roleAuteurCreation,
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
      'lieuDepart': lieuDepart,
      'lieuArrivee': lieuArrivee,
      'heureDepart':
          heureDepart != null ? fs.Timestamp.fromDate(heureDepart!) : null,
      'heureDepartReel': heureDepartReel != null
          ? fs.Timestamp.fromDate(heureDepartReel!)
          : null,
      'heureArriveeReel': heureArriveeReel != null
          ? fs.Timestamp.fromDate(heureArriveeReel!)
          : null,
    };
  }

  Transfert copyWith({
    String? id,
    String? tranche,
    List<String>? tranchesVisibles,
    String? contenu,
    DateTime? dateEmission,
    bool? estPrioritaire,
    String? auteurIdCreation,
    String? auteurNomPrenomCreation,
    String? roleAuteurCreation,
    bool? estValidee,
    DateTime? dateValidation,
    String? commentaireValidation,
    String? idAuteurValidation,
    String? nomPrenomValidation,
    List<Commentaire>? commentairesNonRealisation,
    bool? estNonRealiseeEffectivement,
    String? dosimetrieInfo,
    String? lieuDepart,
    String? lieuArrivee,
    DateTime? heureDepart,
    DateTime? heureDepartReel,
    DateTime? heureArriveeReel,
    bool clearDosimetrieInfo = false,
    bool clearCommentaireValidation = false,
    bool clearDateValidation = false,
    bool clearIdAuteurValidation = false,
    bool clearNomPrenomValidation = false,
    bool clearCommentairesNonRealisation = false,
    bool clearTranchesVisibles = false,
  }) {
    return Transfert(
      id: id ?? this.id,
      tranche: tranche ?? this.tranche,
      tranchesVisibles: clearTranchesVisibles
          ? null
          : (tranchesVisibles ?? this.tranchesVisibles),
      contenu: contenu ?? this.contenu,
      dateEmission: dateEmission ?? this.dateEmission,
      estPrioritaire: estPrioritaire ?? this.estPrioritaire,
      auteurIdCreation: auteurIdCreation ?? this.auteurIdCreation,
      auteurNomPrenomCreation:
          auteurNomPrenomCreation ?? this.auteurNomPrenomCreation,
      roleAuteurCreation: roleAuteurCreation ?? this.roleAuteurCreation,
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
      lieuDepart: lieuDepart ?? this.lieuDepart,
      lieuArrivee: lieuArrivee ?? this.lieuArrivee,
      heureDepart: heureDepart ?? this.heureDepart,
      heureDepartReel: heureDepartReel ?? this.heureDepartReel,
      heureArriveeReel: heureArriveeReel ?? this.heureArriveeReel,
    );
  }
}
