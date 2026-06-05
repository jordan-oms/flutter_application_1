// lib/model/consigne.dart

import 'package:cloud_firestore/cloud_firestore.dart' as fs;
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

  final String? reference;
  final List<String> idsConsignesRattachees;
  final List<String> referencesConsignesRattachees;
  final String? site;

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
    this.reference,
    this.idsConsignesRattachees = const [],
    this.referencesConsignesRattachees = const [],
    this.site,
  });

  factory Consigne.fromJson(Map<String, dynamic> json) {
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

    // Gestion de la migration des anciens champs simples vers les listes
    List<String> ids = [];
    if (json['idsConsignesRattachees'] is List) {
      ids = List<String>.from(json['idsConsignesRattachees']);
    } else if (json['idConsigneRattachee'] != null) {
      ids = [json['idConsigneRattachee'].toString()];
    }

    List<String> refs = [];
    if (json['referencesConsignesRattachees'] is List) {
      refs = List<String>.from(json['referencesConsignesRattachees']);
    } else if (json['referenceConsigneRattachee'] != null) {
      refs = [json['referenceConsigneRattachee'].toString()];
    }

    return Consigne(
      id: json['id']?.toString() ?? '',
      tranche: json['tranche']?.toString() ?? '',
      contenu: json['contenu']?.toString() ?? '',
      dateEmission: toDateTime(json['dateEmission']) ?? DateTime.now(),
      estPrioritaire: json['estPrioritaire'] == true,
      auteurIdCreation: json['auteurIdCreation']?.toString() ?? '',
      auteurNomPrenomCreation:
          json['auteurNomPrenomCreation']?.toString() ?? '',
      roleAuteurCreation: json['roleAuteurCreation']?.toString() ?? '',
      categorie: json['categorie']?.toString(),
      enjeu: json['enjeu']?.toString(),
      estValidee: json['estValidee'] == true,
      dateValidation: toDateTime(json['dateValidation']),
      commentaireValidation: json['commentaireValidation']?.toString(),
      idAuteurValidation: json['idAuteurValidation']?.toString(),
      nomPrenomValidation: json['nomPrenomValidation']?.toString(),
      commentairesNonRealisation: parsedCommentairesNonRealisation,
      estNonRealiseeEffectivement: json['estNonRealiseeEffectivement'] == true,
      dosimetrieInfo: json['dosimetrieInfo']?.toString(),
      reference: json['reference']?.toString(),
      idsConsignesRattachees: ids,
      referencesConsignesRattachees: refs,
      site: json['site']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    final data = {
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
      'reference': reference,
      'site': site,
    };

    // Gestion propre des rattachements pour Firestore
    if (idsConsignesRattachees.isNotEmpty) {
      data['idsConsignesRattachees'] = idsConsignesRattachees;
      data['referencesConsignesRattachees'] = referencesConsignesRattachees;

      // Pour la compatibilité avec les anciennes règles "hasOnly" (si non-éditeur)
      // On met le premier élément de la liste en texte simple
      data['idConsigneRattachee'] = idsConsignesRattachees.first;
      data['referenceConsigneRattachee'] = referencesConsignesRattachees.first;
    } else {
      data['idsConsignesRattachees'] = [];
      data['referencesConsignesRattachees'] = [];
      data['idConsigneRattachee'] = null;
      data['referenceConsigneRattachee'] = null;
    }

    return data;
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
    String? reference,
    List<String>? idsConsignesRattachees,
    List<String>? referencesConsignesRattachees,
    String? site,
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
      reference: reference ?? this.reference,
      idsConsignesRattachees:
          idsConsignesRattachees ?? this.idsConsignesRattachees,
      referencesConsignesRattachees:
          referencesConsignesRattachees ?? this.referencesConsignesRattachees,
      site: site ?? this.site,
    );
  }
}
