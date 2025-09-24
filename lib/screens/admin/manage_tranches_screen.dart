// lib/screens/admin/manage_tranches_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'
as fs; // Utilisé pour la cohérence, et si Timestamp est nécessaire plus tard
import 'package:firebase_auth/firebase_auth.dart';

const String roleAdminStringForCheck = "administrateur";

class ManageTranchesScreen extends StatefulWidget {
  static const String routeName = '/manage-tranches';

  const ManageTranchesScreen({super.key}); // Modifié pour super.key

  @override
  // Modifié pour retourner le type d'état public
  ManageTranchesScreenState createState() => ManageTranchesScreenState();
}

// Classe d'état renommée en ManageTranchesScreenState (publique)
class ManageTranchesScreenState extends State<ManageTranchesScreen> {
  final fs.FirebaseFirestore _firestore = fs.FirebaseFirestore.instance;
  final fs.DocumentReference _tranchesConfigRef =
  fs.FirebaseFirestore.instance.collection('app_config').doc('tranches_config');

  List<String> _tranches = [];
  bool _isLoading = true;
  String? _error;

  final TextEditingController _nouvelleTrancheController =
  TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadTranches();
  }

  @override
  void dispose() {
    _nouvelleTrancheController.dispose();
    super.dispose();
  }

  Future<void> _loadTranches() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      fs.DocumentSnapshot snapshot = await _tranchesConfigRef.get();
      if (!mounted) return;

      if (snapshot.exists && snapshot.data() != null) {
        var data = snapshot.data() as Map<String, dynamic>;
        if (data['liste_tranches'] is List) {
          _tranches = List<String>.from(
              data['liste_tranches'].map((item) => item.toString()));
        } else {
          _tranches = [];
          debugPrint( // Remplacé print par debugPrint
              "[ManageTranchesScreen - _loadTranches] 'liste_tranches' n'est pas une List dans le document.");
        }
      } else {
        _tranches = [];
        debugPrint( // Remplacé print par debugPrint
            "[ManageTranchesScreen - _loadTranches] Document 'tranches_config' non trouvé ou vide.");
      }
    } catch (e, s) {
      debugPrint( // Remplacé print par debugPrint
          "[ManageTranchesScreen - _loadTranches] Erreur chargement tranches: $e\nStackTrace: $s");
      if (mounted) {
        _error = "Erreur de chargement des tranches: $e";
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _addTranche() async {
    final nouvelleTranche = _nouvelleTrancheController.text.trim();
    if (nouvelleTranche.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Veuillez saisir un nom de tranche.")),
        );
      }
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    debugPrint( // Remplacé print par debugPrint
        "[ManageTranchesScreen - _addTranche] DÉBUT AJOUT TRANCHE");
    debugPrint( // Remplacé print par debugPrint
        "[ManageTranchesScreen - _addTranche] Utilisateur actuel UID: ${currentUser
            ?.uid}");
    debugPrint( // Remplacé print par debugPrint
        "[ManageTranchesScreen - _addTranche] Tranche à ajouter: $nouvelleTranche");

    if (currentUser == null) {
      debugPrint( // Remplacé print par debugPrint
          "[ManageTranchesScreen - _addTranche] ERREUR: Utilisateur non connecté !");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Erreur: Utilisateur non connecté.")),
        );
      }
      return;
    }

    try {
      fs.DocumentSnapshot userDoc =
      await _firestore.collection('utilisateurs').doc(currentUser.uid).get();
      if (!mounted) return;

      if (userDoc.exists && userDoc.data() != null) {
        var userData = userDoc.data() as Map<String, dynamic>;
        List<String> userRoles = (userData['roles'] is List)
            ? List<String>.from(userData['roles']
            .map((role) => role.toString().toLowerCase().trim()))
            : [];
        debugPrint( // Remplacé print par debugPrint
            "[ManageTranchesScreen - _addTranche] Rôles récupérés ET STANDARDISÉS pour ${currentUser
                .uid}: $userRoles");

        if (!userRoles.contains(roleAdminStringForCheck)) {
          debugPrint( // Remplacé print par debugPrint
              "[ManageTranchesScreen - _addTranche] ERREUR: L'utilisateur ${currentUser
                  .uid} n'a pas le rôle '$roleAdminStringForCheck'. Action refusée côté client.");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text("Action non autorisée (rôle admin manquant).")),
            );
          }
          return;
        }
        debugPrint( // Remplacé print par debugPrint
            "[ManageTranchesScreen - _addTranche] Vérification du rôle admin ('$roleAdminStringForCheck') RÉUSSIE pour ${currentUser
                .uid}.");
      } else {
        debugPrint( // Remplacé print par debugPrint
            "[ManageTranchesScreen - _addTranche] ERREUR: Document utilisateur non trouvé pour ${currentUser
                .uid}. Impossible de vérifier le rôle admin.");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text("Erreur: Document utilisateur introuvable.")),
          );
        }
        return;
      }
    } catch (e, s) {
      debugPrint( // Remplacé print par debugPrint
          "[ManageTranchesScreen - _addTranche] ERREUR lors de la vérification du rôle admin pour ${currentUser
              .uid}: $e\nStackTrace: $s");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Erreur lors de la vérification des droits: $e")),
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      debugPrint( // Remplacé print par debugPrint
          "[ManageTranchesScreen - _addTranche] Tentative d'écriture Firestore pour /app_config/tranches_config avec la tranche: $nouvelleTranche");
      fs.DocumentSnapshot configDoc = await _tranchesConfigRef.get();
      if (!mounted) return;

      if (!configDoc.exists) {
        debugPrint( // Remplacé print par debugPrint
            "[ManageTranchesScreen - _addTranche] Document tranches_config N'EXISTE PAS. Création avec .set().");
        await _tranchesConfigRef.set({
          'liste_tranches': [nouvelleTranche]
        });
      } else {
        debugPrint( // Remplacé print par debugPrint
            "[ManageTranchesScreen - _addTranche] Document tranches_config EXISTE. Mise à jour avec FieldValue.arrayUnion.");
        await _tranchesConfigRef.update({
          'liste_tranches': fs.FieldValue.arrayUnion([nouvelleTranche])
          // Utiliser fs.FieldValue
        });
      }
      debugPrint( // Remplacé print par debugPrint
          "[ManageTranchesScreen - _addTranche] Tranche '$nouvelleTranche' ajoutée/mise à jour avec succès dans Firestore.");
      _nouvelleTrancheController.clear();
      await _loadTranches();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Tranche '$nouvelleTranche' ajoutée.")),
        );
      }
    } catch (e, s) {
      debugPrint( // Remplacé print par debugPrint
          "[ManageTranchesScreen - _addTranche] ERREUR Firestore lors de l'ajout/MAJ de la tranche '$nouvelleTranche': $e\nStackTrace: $s");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
              "Erreur Firestore lors de l'ajout de la tranche: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteTranche(String trancheASupprimer) async {
    final confirmer = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) =>
          AlertDialog(
            title: const Text('Confirmer la suppression'),
            content: Text(
                "Voulez-vous vraiment supprimer la tranche '$trancheASupprimer' ?"),
            actions: <Widget>[
              TextButton(
                child: const Text('Annuler'),
                onPressed: () {
                  Navigator.of(ctx).pop(false);
                },
              ),
              TextButton(
                child:
                const Text('Supprimer', style: TextStyle(color: Colors.red)),
                onPressed: () {
                  Navigator.of(ctx).pop(true);
                },
              ),
            ],
          ),
    ) ??
        false;

    if (!confirmer) return;
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      debugPrint( // Remplacé print par debugPrint
          "[ManageTranchesScreen - _deleteTranche] Tentative de suppression de la tranche: $trancheASupprimer");
      await _tranchesConfigRef.update({
        'liste_tranches': fs.FieldValue.arrayRemove([trancheASupprimer])
        // Utiliser fs.FieldValue
      });
      debugPrint( // Remplacé print par debugPrint
          "[ManageTranchesScreen - _deleteTranche] Tranche '$trancheASupprimer' supprimée de Firestore.");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Tranche '$trancheASupprimer' supprimée !")),
        );
        await _loadTranches();
      }
    } catch (e, s) {
      debugPrint( // Remplacé print par debugPrint
          "[ManageTranchesScreen - _deleteTranche] ERREUR Firestore lors de la suppression de la tranche '$trancheASupprimer': $e\nStackTrace: $s");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  "Erreur Firestore lors de la suppression de la tranche: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Gérer les Tranches"),
        backgroundColor: Colors.redAccent.shade700,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          if (_isLoading && _tranches.isNotEmpty)
            const LinearProgressIndicator(),
          Expanded(
            child: _isLoading && _tranches.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.red, fontSize: 16)),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text("Réessayer"),
                      onPressed: _loadTranches,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent.shade400,
                          foregroundColor: Colors.white),
                    )
                  ],
                ),
              ),
            )
                : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _nouvelleTrancheController,
                          decoration: const InputDecoration(
                            labelText: "Nom de la nouvelle tranche",
                            border: OutlineInputBorder(),
                            hintText: "Ex: 320-25 ALOG, 320-25 BNET...",
                          ),
                          onSubmitted: (_) => _addTranche(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        icon:
                        const Icon(Icons.add_circle_outline),
                        label: const Text("Ajouter"),
                        onPressed: _addTranche,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent.shade400,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _tranches.isEmpty
                      ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        mainAxisAlignment:
                        MainAxisAlignment.center,
                        children: [
                          Icon(Icons.layers_clear,
                              size: 60,
                              color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          const Text(
                            "Aucune tranche configurée.",
                            style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            "Utilisez le champ ci-dessus pour ajouter votre première tranche.",
                            style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                      : ListView.builder(
                    padding: const EdgeInsets.only(
                        bottom: 16, left: 16, right: 16),
                    itemCount: _tranches.length,
                    itemBuilder: (context, index) {
                      final tranche = _tranches[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            vertical: 6),
                        elevation: 2,
                        child: ListTile(
                          title: Text(tranche,
                              style: const TextStyle(
                                  fontWeight:
                                  FontWeight.w500)),
                          trailing: IconButton(
                            icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.red),
                            tooltip:
                            "Supprimer cette tranche",
                            onPressed: () =>
                                _deleteTranche(tranche),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}