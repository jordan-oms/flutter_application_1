import 'package:cloud_firestore/cloud_firestore.dart';
import 'consigne.dart';

class ConsigneService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Génère une référence unique de type SITE-TRANCHE-C00
  Future<String> generateReference(String site, String tranche) async {
    final String siteUpper = site.toUpperCase();
    final String trancheUpper = tranche.toUpperCase();
    final String counterId = "$siteUpper-$trancheUpper";
    final DocumentReference counterRef =
        _firestore.collection('consigne_counters').doc(counterId);

    try {
      print("DEBUG: Démarrage transaction pour $counterId");
      return await _firestore.runTransaction((transaction) async {
        DocumentSnapshot snapshot = await transaction.get(counterRef);

        int nextNumber = 1;
        if (snapshot.exists && snapshot.data() != null) {
          final data = snapshot.data() as Map<String, dynamic>;
          nextNumber = (data['lastNumber'] ?? 0) + 1;
        }

        transaction.set(counterRef, {'lastNumber': nextNumber});

        String formattedNumber = nextNumber.toString().padLeft(2, '0');
        return "$counterId-C$formattedNumber";
      }, timeout: const Duration(seconds: 10));
    } catch (e) {
      print(
          "DEBUG: Échec transaction generateReference ($e). Tentative de fallback par requête...");

      try {
        // Fallback : On cherche la dernière consigne créée pour ce site/tranche
        // pour essayer de deviner le prochain numéro.
        final querySnapshot = await _firestore
            .collection('consignes')
            .where('site', isEqualTo: siteUpper)
            .where('tranche', isEqualTo: trancheUpper)
            .orderBy('reference', descending: true)
            .limit(1)
            .get();

        int nextNumberFallback = 1;
        if (querySnapshot.docs.isNotEmpty) {
          final lastRef = querySnapshot.docs.first.get('reference') as String;
          // On tente d'extraire le numéro après le "-C"
          final parts = lastRef.split('-C');
          if (parts.length > 1) {
            final lastNum = int.tryParse(parts.last);
            if (lastNum != null) {
              nextNumberFallback = lastNum + 1;
            }
          }
        }

        String formattedNumber = nextNumberFallback.toString().padLeft(2, '0');
        return "$counterId-C$formattedNumber";
      } catch (e2) {
        print(
            "DEBUG: Fallback par requête échoué ($e2). Utilisation d'un suffixe temporel formaté.");
        // Dernier recours : SITE-TRANCHE-C + 2 derniers chiffres du timestamp pour rester dans le format
        String ts = DateTime.now().millisecondsSinceEpoch.toString();
        String suffix = ts.substring(ts.length - 2);
        return "$counterId-C$suffix";
      }
    }
  }

  /// Recherche une consigne par référence ou contenu (recherche par "contient")
  /// [tranche] optionnelle pour filtrer les résultats sur une tranche précise
  Future<List<Consigne>> searchConsignes(String query,
      {String? tranche,
      bool includeArchived = true,
      String collectionPrefix = ""}) async {
    if (query.isEmpty) return [];

    final String queryUpper = query.toUpperCase();
    final String? trancheUpper = tranche?.toUpperCase();
    final List<Consigne> allResults = [];
    final Set<String> seenIds = {};

    print(
        "DEBUG SEARCH: Début recherche pour '$queryUpper' (Tranche: $trancheUpper)");

    try {
      // Avec la collection unique, on ne cherche que dans '${collectionPrefix}consignes'
      Query queryRef = _firestore.collection('${collectionPrefix}consignes');
      if (trancheUpper != null) {
        queryRef = queryRef.where('tranche', isEqualTo: trancheUpper);
      }

      final snapshot = await queryRef.get();
      print("DEBUG SEARCH: ${snapshot.docs.length} consignes à filtrer");

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final c = Consigne.fromJson(data);
        final ref = (c.reference ?? "").toUpperCase();
        final cont = c.contenu.toUpperCase();

        // Si on ne veut pas les archives, on filtre par estValidee
        if (!includeArchived && c.estValidee) continue;

        if (ref.contains(queryUpper) || cont.contains(queryUpper)) {
          if (!seenIds.contains(c.id)) {
            allResults.add(c);
            seenIds.add(c.id);
          }
        }
      }
    } catch (e, stack) {
      print("DEBUG SEARCH ERROR GLOBAL: $e");
      print(stack);
    }

    print("DEBUG SEARCH: ${allResults.length} résultats au total");
    return allResults;
  }
}
