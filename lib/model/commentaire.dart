// lib/model/commentaire.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class Commentaire {
  final String id; // Identifiant unique pour chaque commentaire
  final String texte;
  final DateTime date;
  final String auteurId; // UID de l'utilisateur Firebase qui a écrit le commentaire
  final String auteurNomPrenom; // Nom et prénom de l'auteur pour affichage
  final String roleAuteur; // Rôle de l'auteur au moment de l'écriture

  Commentaire({ required this.id,
    required this.texte,
    required this.date,
    required this.auteurId,
    required this.auteurNomPrenom,
    required this.roleAuteur,
  });

  // Méthode pour convertir un document Firestore (Map) en objet Commentaire
  factory Commentaire.fromJson(Map<String, dynamic> json) {
    return Commentaire(
      id: json['id'] as String? ?? '',
      // Fournir une valeur par défaut si null
      texte: json['texte'] as String? ?? '',
      date: (json['date'] as Timestamp? ?? Timestamp.now()).toDate(),
      // Fournir une date actuelle si null
      auteurId: json['auteurId'] as String? ?? '',
      auteurNomPrenom: json['auteurNomPrenom'] as String? ?? 'Inconnu',
      roleAuteur: json['roleAuteur'] as String? ?? 'Indéfini',
    );
  }

  // Méthode pour convertir un objet Commentaire en Map pour Firestore
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'texte': texte,
      'date': Timestamp.fromDate(date),
      // Convertir DateTime en Timestamp Firestore
      'auteurId': auteurId,
      'auteurNomPrenom': auteurNomPrenom,
      'roleAuteur': roleAuteur,
    };
  }

  // Optionnel: une méthode copyWith si vous avez besoin de créer des copies modifiées
  Commentaire copyWith({
    String? id,
    String? texte,
    DateTime? date,
    String? auteurId,
    String? auteurNomPrenom,
    String? roleAuteur,
  }) {
    return Commentaire(
      id: id ?? this.id,
      texte: texte ?? this.texte,
      date: date ?? this.date,
      auteurId: auteurId ?? this.auteurId,
      auteurNomPrenom: auteurNomPrenom ?? this.auteurNomPrenom,
      roleAuteur: roleAuteur ?? this.roleAuteur,
    );
  }
}