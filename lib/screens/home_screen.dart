// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Importez vos modèles
import '../model/consigne.dart';
import '../model/info_chantier.dart';
import '../model/commentaire.dart';

// Importez vos autres écrans
import './role_selection_screen.dart';
import './admin/manage_tranches_screen.dart';

// Constantes pour les rôles
const String roleAdminString = "administrateur";
const String roleChefDeChantierString = "chef_de_chantier";
const String roleChefEquipeString = "chef_equipe";


// Options pour le dialogue de sélection des enjeux
const List<String> optionsEnjeux = [
  'Sûreté',
  'RP',
  'Sécurité',
];

enum HomeScreenLoadingState {
  initializing,
  loadingTranches,
  ready,
  error,
  unauthenticated,
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

// =========================================================================
// =================== CLASSE _HomeScreenState COMPLÈTE ===================
// =========================================================================
class _HomeScreenState extends State<HomeScreen> {
  HomeScreenLoadingState _loadingState = HomeScreenLoadingState.initializing;
  User? _currentUser;
  List<String> _userRoles = [];
  String _currentUserNomPrenom = "Chargement...";
  String _roleDisplay = "Chargement...";
  int _currentIndex = 0;

  String? _selectedTranche;
  List<String> _tranches = [];

  // Pour les Consignes (champ d'ajout)
  final TextEditingController _consigneController = TextEditingController();
  bool _estPrioritaireNouvelleConsigne = false;
  String? _selectedEnjeuPourNouvelleConsigne;

  final TextEditingController _observationValidationDialogController = TextEditingController();

  // Références et contrôleurs existants
  final CollectionReference _consignesRefGlobal = FirebaseFirestore.instance
      .collection('consignes');
  final Map<String, TextEditingController> _obsNonRealiseeControllers = {};
  final Map<String, TextEditingController> _obsValidationControllers = {};
  final List<String> _categoriesConsignes = [
    "Confinement",
    "Protection Biologique",
    "Décontamination",
    "Pompage",
    "Nettoyage",
    "DMP",
    "Décontamination piscine",
    "Autre",
  ];
  final TextEditingController _infoController = TextEditingController();
  final CollectionReference _infosChantierRefGlobal = FirebaseFirestore.instance
      .collection('infos_chantier');
  final DocumentReference _tranchesConfigRef = FirebaseFirestore.instance
      .collection('app_config').doc('tranches_config');
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _loadUserDataAndRoles();
  }

  @override
  void dispose() {
    _consigneController.dispose();
    _infoController.dispose();
    _obsNonRealiseeControllers.forEach((_, controller) => controller.dispose());
    _obsNonRealiseeControllers.clear();
    _obsValidationControllers.forEach((_, controller) => controller.dispose());
    _obsValidationControllers.clear();
    _observationValidationDialogController.dispose();
    super.dispose();
  }

  void _safelySetState(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  Future<void> _loadUserDataAndRoles() async {
    final stopwatch = Stopwatch()
      ..start();
    if (!mounted) {
      stopwatch.stop();
      return;
    }
    _safelySetState(() => _loadingState = HomeScreenLoadingState.initializing);
    _currentUser = FirebaseAuth.instance.currentUser;

    if (!mounted) {
      stopwatch.stop();
      return;
    }

    if (_currentUser == null) {
      _safelySetState(() =>
      _loadingState = HomeScreenLoadingState.unauthenticated);
      _triggerReSelectionAndNavigate();
      stopwatch.stop();
      return;
    }

    try {
      DocumentSnapshot userDoc = await _firestore
          .collection('utilisateurs')
          .doc(_currentUser!.uid)
          .get();
      if (!mounted) {
        stopwatch.stop();
        return;
      }

      if (userDoc.exists && userDoc.data() != null) {
        var data = userDoc.data() as Map<String, dynamic>;
        _userRoles = (data['roles'] is List)
            ? List<String>.from(
            data['roles'].map((role) => role.toString().toLowerCase().trim()))
            : [];

        // Pour _currentUserNomPrenom, la priorité est au champ 'nom' de Firestore.
        // Si 'nom' n'existe pas ou est vide, on construit à partir de equipe/poste (pour chef d'équipe)
        // ou on utilise les fallbacks pour les autres.
        String? firestoreNom = data['nom'] as String?;

        if (_userRoles.contains(roleChefEquipeString)) {
          // Pour Chef d'équipe, on veut que _currentUserNomPrenom soit "Équipe X - Poste Y"
          if (firestoreNom != null && firestoreNom.isNotEmpty) {
            _currentUserNomPrenom =
                firestoreNom; // Doit être "Équipe X - Poste Y"
          } else {
            // Si data['nom'] n'est pas ce qu'on attend, on le reconstruit
            String equipe = data.containsKey('numeroEquipe')
                ? "Équipe ${data['numeroEquipe']}"
                : "Équipe ?";
            String poste = data.containsKey('poste_actuel')
                ? "${data['poste_actuel']}"
                : "Poste ?";
            _currentUserNomPrenom = "$equipe - $poste";
          }
        } else {
          // Pour les autres rôles, utiliser 'nom' s'il existe, sinon fallback
          _currentUserNomPrenom = firestoreNom ??
              (_currentUser!.isAnonymous
                  ? "Utilisateur Anonyme"
                  : (_currentUser!.email ?? "UID: ${_currentUser!.uid}"));
        }
      } else { // Si userDoc n'existe pas
        _userRoles = [];
        _currentUserNomPrenom =
        _currentUser!.isAnonymous
            ? "Utilisateur Anonyme (Doc Manquant)"
            : (_currentUser!.email ??
            "UID: ${_currentUser!.uid} (Doc Manquant)");
      }

      // Détermination de _roleDisplay
      if (_userRoles.contains(roleAdminString)) {
        _roleDisplay = "Administrateur";
        // _currentUserNomPrenom sera le nom de l'admin ou "Administrateur" si data['nom'] est vide
      } else if (_userRoles.contains(roleChefDeChantierString)) {
        _roleDisplay = "Chef de chantier";
        // _currentUserNomPrenom sera le nom du CDC ou "Chef de chantier" si data['nom'] est vide
      } else if (_userRoles.contains(roleChefEquipeString)) {
        // Pour Chef d'équipe, _roleDisplay est le rôle générique
        _roleDisplay = "Chef d'équipe";
        // _currentUserNomPrenom a déjà été défini ci-dessus pour être "Équipe X - Poste Y"
      } else {
        _roleDisplay = "Rôle Indéfini";
        // _currentUserNomPrenom sera "Utilisateur Anonyme" ou UID
      }
      await _loadTranches();
    } catch (e) {
      if (mounted) {
        _safelySetState(() => _loadingState = HomeScreenLoadingState.error);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
              "Erreur de chargement des informations utilisateur: $e")),
        );
      }
    }
    stopwatch.stop();
  }

  Future<void> _loadTranches() async {
    if (!mounted) {
      return;
    }
    if (_loadingState != HomeScreenLoadingState.initializing) {
      _safelySetState(() =>
      _loadingState = HomeScreenLoadingState.loadingTranches);
    }

    try {
      DocumentSnapshot tranchesDoc = await _tranchesConfigRef.get();
      if (!mounted) return;

      if (tranchesDoc.exists && tranchesDoc.data() != null) {
        var data = tranchesDoc.data() as Map<String, dynamic>;
        if (data['liste_tranches'] is List) {
          _tranches = List<String>.from(
              data['liste_tranches'].map((item) => item.toString()));
          if (_tranches.isNotEmpty) {
            if (_selectedTranche == null ||
                !_tranches.contains(_selectedTranche)) {
              _selectedTranche = _tranches.first;
            }
          } else {
            _tranches = [];
            _selectedTranche = null;
          }
        } else {
          _tranches = [];
          _selectedTranche = null;
        }
      } else {
        _tranches = [];
        _selectedTranche = null;
      }
      _safelySetState(() => _loadingState = HomeScreenLoadingState.ready);
    } catch (e) {
      if (mounted) {
        _safelySetState(() => _loadingState = HomeScreenLoadingState.error);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
              "Erreur de chargement de la configuration des tranches: $e")),
        );
      }
    }
  }

  void _triggerReSelectionAndNavigate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        RoleSelectionScreen.triggerRoleReSelection(context);
      }
    });
  }

  Stream<List<Consigne>> getConsignesStream() {
    if (_selectedTranche == null) {
      return Stream.value([]);
    }
    return _consignesRefGlobal
        .where('tranche', isEqualTo: _selectedTranche)
        .orderBy('dateEmission', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        try {
          return Consigne.fromJson(doc.data() as Map<String, dynamic>);
        } catch (e) {
          return null;
        }
      }).whereType<Consigne>().toList();
    });
  }

  Future<void> _addConsigneDB(Consigne consigne) async {
    try {
      await _consignesRefGlobal.doc(consigne.id).set(consigne.toJson());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erreur d'ajout de la consigne: $e")));
      }
    }
  }

  Future<void> _deleteConsigneDB(String id) async {
    try {
      await _consignesRefGlobal.doc(id).delete();
      // SnackBar de succès est géré par l'appelant direct (e.g., dans _buildConsignesList ou _confirmerEtSupprimerConsigneArchivee)
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Erreur de suppression de la consigne: $e")));
      }
    }
  }

  // DANS LA CLASSE _HomeScreenState
  Future<void> _updateConsigneDB(Consigne consigne) async {
    Map<String, dynamic> dataToUpdate = {};

    if (_currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(
              "Erreur : Utilisateur non identifié pour la mise à jour.")),
        );
      }
      return;
    }

    // GESTION POUR ADMIN / CHEF DE CHANTIER
    if (_userRoles.contains(roleAdminString) ||
        _userRoles.contains(roleChefDeChantierString)) {
      if (consigne.estValidee) { // L'action est de marquer comme VALIDÉE
        dataToUpdate['estValidee'] = true;
        dataToUpdate['dateValidation'] =
        consigne.dateValidation != null ? Timestamp.fromDate(
            consigne.dateValidation!) : Timestamp.now();
        dataToUpdate['commentaireValidation'] =
            consigne.commentaireValidation; // Peut être null si pas d'obs
        dataToUpdate['idAuteurValidation'] =
            consigne.idAuteurValidation ?? _currentUser!.uid;
        dataToUpdate['estNonRealiseeEffectivement'] = false;
      } else if (consigne
          .estNonRealiseeEffectivement) { // L'action est d'ajouter une NON-RÉALISATION
        dataToUpdate['commentairesNonRealisation'] =
            consigne.commentairesNonRealisation
                ?.map((c) => c.toJson())
                .toList();
        dataToUpdate['estNonRealiseeEffectivement'] = true;
        dataToUpdate['estValidee'] = false; // Une non-réalisation invalide
        dataToUpdate['dateValidation'] = null;
        dataToUpdate['commentaireValidation'] = null;
        dataToUpdate['idAuteurValidation'] = null;
      } else { // L'action est d'INVALIDER (décocher, estValidee=false, estNonRealiseeEffectivement=false)
        dataToUpdate['estValidee'] = false;
        dataToUpdate['dateValidation'] = null;
        dataToUpdate['commentaireValidation'] = null;
        dataToUpdate['idAuteurValidation'] = null;
      }
      // GESTION POUR CHEF D'ÉQUIPE
    } else if (_userRoles.contains(roleChefEquipeString)) {
      if (consigne
          .estValidee) {
        if (consigne.idAuteurValidation != null &&
            consigne.idAuteurValidation != _currentUser!.uid) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text(
                  "Vous ne pouvez modifier que votre propre validation (Chef d'Équipe).")),
            );
          }
          return;
        }
        dataToUpdate['estValidee'] = true;
        dataToUpdate['dateValidation'] = consigne.dateValidation != null
            ? Timestamp.fromDate(consigne.dateValidation!)
            : Timestamp.now();
        dataToUpdate['commentaireValidation'] = consigne.commentaireValidation;
        dataToUpdate['idAuteurValidation'] = _currentUser!.uid;
        dataToUpdate['estNonRealiseeEffectivement'] = false;
      } else if (consigne
          .estNonRealiseeEffectivement) { // L'action est NON-RÉALISATION
        dataToUpdate['commentairesNonRealisation'] =
            consigne.commentairesNonRealisation
                ?.map((c) => c.toJson())
                .toList();
        dataToUpdate['estNonRealiseeEffectivement'] = true;
        dataToUpdate['estValidee'] = false;
        dataToUpdate['dateValidation'] = null;
        dataToUpdate['commentaireValidation'] = null;
        dataToUpdate['idAuteurValidation'] = null;
      } else { // L'action est d'INVALIDER (décocher)
        dataToUpdate['estValidee'] = false;
        dataToUpdate['dateValidation'] = null;
        dataToUpdate['commentaireValidation'] = null;
        dataToUpdate['idAuteurValidation'] = null;
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(
              "Vous n'avez pas la permission de modifier cette consigne.")),
        );
      }
      return; // Aucun rôle correspondant trouvé pour la modification
    }

    if (dataToUpdate.isEmpty) {
      return;
    }

    try {
      await _consignesRefGlobal.doc(consigne.id).update(dataToUpdate);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text("Erreur de mise à jour de la consigne: $e")));
      }
    }
  }

  void _presenterValidationConsigne(Consigne consigne,
      bool estValideeMaintenant) {

    if (estValideeMaintenant) {
      _presenterDialogObservationValidation(consigne);

    } else {
      Consigne consigneMiseAJour = consigne.copyWith(
        estValidee: false,
        dateValidation: null,
        // Effacer la date de validation
        clearCommentaireValidation: true,
        // Effacer le commentaire de validation
        idAuteurValidation: null, // Effacer l'auteur de la validation
        // estNonRealiseeEffectivement n'est pas changé ici, sauf logique spécifique
      );
      _updateConsigneDB(consigneMiseAJour);
    }
  }

  // ignore: unused_element
  Future<void> _presenterDialogObservationValidation(
      Consigne consigneAValider) async {
    String initialComment = "";
    if (consigneAValider.idAuteurValidation == _currentUser?.uid &&
        consigneAValider.commentaireValidation != null) {
      initialComment =
          consigneAValider.commentaireValidation!.split('\n-').first.trim();
    } else if (consigneAValider.commentaireValidation == null) {
      initialComment = "";

    }

    _observationValidationDialogController.text = initialComment;


    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Observation de Validation'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(
                    'Veuillez saisir une observation pour la consigne : "${consigneAValider
                        .contenu}"'),
                const SizedBox(height: 16),
                TextField(
                  controller: _observationValidationDialogController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Saisir votre observation ici (optionnel)...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('ANNULER VALIDATION'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _observationValidationDialogController
                    .clear(); // Vider au cas où
              },
            ),
            ElevatedButton(
              child: const Text('ENREGISTRER ET VALIDER'),
              onPressed: () {
                final String observationTexte = _observationValidationDialogController
                    .text.trim();
                String commentaireFinalAvecAuteur = "";
                if (observationTexte.isNotEmpty) {
                  commentaireFinalAvecAuteur =
                  "$observationTexte\n- $_currentUserNomPrenom ($_roleDisplay) le ${_formatDateSimple(
                      DateTime.now(), showTime: true)}";
                }

                Consigne consigneMiseAJour = consigneAValider.copyWith(
                  estValidee: true,
                  dateValidation: DateTime.now(),
                  commentaireValidation: commentaireFinalAvecAuteur.isNotEmpty
                      ? commentaireFinalAvecAuteur
                      : null,
                  clearCommentaireValidation: commentaireFinalAvecAuteur
                      .isEmpty,
                  idAuteurValidation: _currentUser!.uid,
                  // Enregistrer qui valide
                  estNonRealiseeEffectivement: false, // Si on valide, elle n'est plus "non réalisée effectivement"
                );
                _updateConsigneDB(consigneMiseAJour);
                Navigator.of(dialogContext).pop();
                _observationValidationDialogController.clear();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _presenterAjoutConsigne() async {
    // --- Vérifications initiales ---
    if (_selectedTranche == null || _selectedTranche!.isEmpty) {
      if (!mounted) return; // Protège le context pour ScaffoldMessenger
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Veuillez d'abord sélectionner une tranche.")),
      );
      return;
    }

    final bool peutAjouter = (_userRoles.contains(roleAdminString) ||
        _userRoles.contains(roleChefDeChantierString)) && _currentUser != null;

    if (!peutAjouter) {
      String message = "Action non autorisée pour ajouter une consigne.";
      if (_currentUser == null) {
        message =
        "Utilisateur non connecté. Impossible d'ajouter une consigne.";
      } else if (!_userRoles.contains(roleAdminString) &&
          !_userRoles.contains(roleChefDeChantierString)) {
        message =
        "Seul Admin/Chef de chantier peut ajouter une consigne. Rôles actuels: $_userRoles";
      }
      if (!mounted) return; // Bonne pratique avant ScaffoldMessenger
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)));
      return;
    }

    final texte = _consigneController.text.trim();
    if (texte.isEmpty) {
      if (!mounted) return; // Bonne pratique avant ScaffoldMessenger
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Veuillez saisir le texte de la consigne.")));
      return;
    }

    // --- PREMIER DIALOGUE (Catégorie) ---
    String? categorieChoisie = await showDialog<String>(
      context: context, // VOTRE context original
      barrierDismissible: false,
      builder: (BuildContext dialogContext) { // VOTRE builder original
        return SimpleDialog(
          title: const Text('Choisir une catégorie pour la consigne'),
          children: _categoriesConsignes.map((categorie) {
            return SimpleDialogOption(
              onPressed: () {
                Navigator.pop(dialogContext, categorie);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: 10.0, horizontal: 8.0),
                child: Text(categorie, style: const TextStyle(fontSize: 16)),
              ),
            );
          })
              .toList(), // .toList() est généralement correct ici pour SimpleDialog
        );
      },
    );

    // >> Protection APRÈS le premier showDialog
    if (!mounted) return;

    if (categorieChoisie == null) {
      // L'utilisateur a annulé, on sort de la fonction.
      // Pas besoin de SnackBar ici sauf si vous le souhaitez (avec protection if(!mounted) avant)
      return;
    }

    // --- DEUXIÈME DIALOGUE (Définir Enjeu ?) ---
    bool veutDefinirEnjeu = await showDialog<bool>(
      context: context, // VOTRE context original
      barrierDismissible: false,
      builder: (BuildContext dialogContext) { // VOTRE builder original
        return AlertDialog(
          title: const Text("Définir un Enjeu ?"),
          content: const Text(
              "Voulez-vous associer un enjeu spécifique (Sûreté, RP, Sécurité) à cette consigne ?"),
          actions: <Widget>[
            TextButton(
              child: const Text("NON"),
              onPressed: () => Navigator.pop(dialogContext, false),
            ),
            ElevatedButton(
              child: const Text("OUI"),
              onPressed: () => Navigator.pop(dialogContext, true),
            ),
          ],
        );
      },
    ) ?? false;

    // >> Protection APRÈS le deuxième showDialog
    if (!mounted) return;

    String? enjeuFinalPourConsigne;

    if (veutDefinirEnjeu) {
      _safelySetState(() { // _safelySetState contient déjà la protection 'mounted'
        _selectedEnjeuPourNouvelleConsigne = null;
      });

      // --- TROISIÈME DIALOGUE (Sélectionner Enjeu) ---
      final String? enjeuChoisiPopup = await showDialog<String>(
        context: context, // VOTRE context original
        builder: (BuildContext dialogContextEnjeu) { // VOTRE builder original
          return StatefulBuilder(
              builder: (BuildContext context, StateSetter setStateDialog) {
                return SimpleDialog(
                  title: const Text('Sélectionner un enjeu'),
                  // ...
                  children: <Widget>[
                    // Enlever .toList() ici
                    ...optionsEnjeux.map((String enjeu) {
                      return SimpleDialogOption(
                        onPressed: () {
                          Navigator.pop(dialogContextEnjeu, enjeu);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(enjeu, style: TextStyle(
                            fontWeight: _selectedEnjeuPourNouvelleConsigne ==
                                enjeu ? FontWeight.bold : FontWeight.normal,
                            color: _selectedEnjeuPourNouvelleConsigne == enjeu
                                ? Colors.blue
                                : null,
                          )),
                        ),
                      );
                    }), // <--- .toList() supprimé
                    SimpleDialogOption( // L'autre SimpleDialogOption reste
                      onPressed: () {
                        Navigator.pop(dialogContextEnjeu, null);
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text('Aucun enjeu / Annuler', style: TextStyle(
                            fontStyle: FontStyle.italic, color: Colors.grey)),
                      ),
                    ),
                  ],
// ...
                );
              });
        },
      );

      // >> Protection APRÈS le troisième showDialog
      if (!mounted) return;

      if (enjeuChoisiPopup != null) {
        enjeuFinalPourConsigne = enjeuChoisiPopup;
      }
      // else { /* L'utilisateur a annulé, enjeuFinalPourConsigne reste null */ }
    }
    // else { /* L'utilisateur n'a pas voulu définir d'enjeu, enjeuFinalPourConsigne reste null */ }

    // --- Création et ajout de la consigne ---
    final nouvelleConsigne = Consigne(
      id: DateTime
          .now()
          .millisecondsSinceEpoch
          .toString(),
      tranche: _selectedTranche!,
      contenu: texte,
      dateEmission: DateTime.now(),
      estPrioritaire: _estPrioritaireNouvelleConsigne,
      auteurIdCreation: _currentUser!.uid,
      auteurNomPrenomCreation: _currentUserNomPrenom,
      roleAuteurCreation: _roleDisplay,
      categorie: categorieChoisie,
      enjeu: enjeuFinalPourConsigne,
      commentairesNonRealisation: [],
    );

    await _addConsigneDB(
        nouvelleConsigne); // _addConsigneDB gère son propre 'mounted' pour son SnackBar

    // >> Protection APRÈS _addConsigneDB (déjà présente dans votre code original et correcte)
    if (!mounted) return;

    _consigneController.clear();
    _safelySetState(() { // _safelySetState gère son propre 'mounted'
      _estPrioritaireNouvelleConsigne = false;
      _selectedEnjeuPourNouvelleConsigne = null;
    });
  }

  Future<void> _enregistrerObservationNonRealisation(Consigne consigne,
      String texteNouvelleObservation) async {
    if (texteNouvelleObservation.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("L'observation ne peut pas être vide.")),
        );
      }
      return;
    }
    final nouveauCommentaire = Commentaire(
      id: DateTime
          .now()
          .millisecondsSinceEpoch
          .toString(),
      texte: texteNouvelleObservation,
      date: DateTime.now(),
      auteurId: _currentUser!.uid,
      auteurNomPrenom: _currentUserNomPrenom,
      roleAuteur: _roleDisplay,
    );
    List<Commentaire> commentairesActuels = List<Commentaire>.from(
        consigne.commentairesNonRealisation ?? []);
    commentairesActuels.add(nouveauCommentaire);

    final consigneMiseAJour = consigne.copyWith(
      commentairesNonRealisation: commentairesActuels,
      estValidee: false,
      // Une observation de non-réalisation implique qu'elle n'est pas validée
      dateValidation: null,
      clearCommentaireValidation: true,
      idAuteurValidation: null,
      estNonRealiseeEffectivement: true, // Marquer comme explicitement non réalisée
    );

    // Pas besoin de vider _obsValidationControllers ici, car on ne touche pas à la validation
    await _updateConsigneDB(consigneMiseAJour);
    _obsNonRealiseeControllers[consigne.id]
        ?.clear(); // Vider le champ après enregistrement
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Observation de non-réalisation ajoutée.")),
      );
    }
  }

  Future<void> _enregistrerObservationValidation(Consigne consigne,
      String texteObservation) async {

    if (!consigne.estValidee ||
        consigne.idAuteurValidation != _currentUser?.uid) {
      if (mounted && consigne.idAuteurValidation != _currentUser?.uid &&
          consigne.estValidee) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(
              "Vous ne pouvez modifier que vos propres observations de validation.")),
        );
      }
      return;
    }

    final String texteCommentaireActuelSeul = consigne.commentaireValidation
        ?.split('\n-')
        .first
        .trim() ?? "";

    if (texteObservation.isEmpty && texteCommentaireActuelSeul.isEmpty) {
      return;
    }
    if (texteObservation ==
        texteCommentaireActuelSeul) { // Comparer seulement le texte de l'obs, pas la signature
      return;
    }

    String commentaireFinalAvecAuteur = "";
    if (texteObservation.isNotEmpty) {
      commentaireFinalAvecAuteur =
      "$texteObservation\n- $_currentUserNomPrenom ($_roleDisplay) le ${_formatDateSimple(
          DateTime.now(), showTime: true)}";
    }


    final consigneMiseAJour = consigne.copyWith(
      commentaireValidation: commentaireFinalAvecAuteur.isNotEmpty
          ? commentaireFinalAvecAuteur
          : null,
      clearCommentaireValidation: commentaireFinalAvecAuteur.isEmpty,
    );
    await _updateConsigneDB(consigneMiseAJour);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _obsValidationControllers.containsKey(consigne.id)) {
        _obsValidationControllers[consigne.id]!.text = texteObservation;
      }
    });


    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(texteObservation.isNotEmpty
            ? "Observation de validation mise à jour."
            : "Observation de validation supprimée.")),
      );
    }
  }


  Future<void> _confirmerEtSupprimerConsigneArchivee(Consigne consigne) async {
    if (!_userRoles.contains(roleAdminString)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Action non autorisée.")),
      );
      return;
    }
    final bool confirmation = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirmer la suppression'),
          content: Text(
              "Êtes-vous sûr de vouloir supprimer définitivement l'archive : ${consigne
                  .contenu} ? Cette action est irréversible."),
          actions: <Widget>[
            TextButton(
              child: const Text('ANNULER'),
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('SUPPRIMER DÉFINITIVEMENT'),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
            ),
          ],
        );
      },
    ) ?? false;

    if (confirmation) {
      try {
        _obsNonRealiseeControllers.remove(consigne.id)?.dispose();
        _obsValidationControllers.remove(consigne.id)?.dispose();
        await _deleteConsigneDB(consigne.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(
                'Archive "${consigne.contenu}" supprimée définitivement.')),
          );
        }
      } catch (e) {

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(
                "Erreur lors de la suppression de l'archive : ${e
                    .toString()}")),
          );
        }
      }
    }
  }

  Stream<List<InfoChantier>> getInfosChantierStream() {
    if (_selectedTranche == null) {
      return Stream.value([]);
    }
    return _infosChantierRefGlobal
        .where('tranche', isEqualTo: _selectedTranche)
        .orderBy('dateEmission', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        try {
          return InfoChantier.fromJson(doc.data() as Map<String, dynamic>);
        } catch (e) {
          return null;
        }
      }).whereType<InfoChantier>().toList();
    });
  }

  Future<void> _addInfoChantierDB(InfoChantier info) async {
    try {
      await _infosChantierRefGlobal.doc(info.id).set(info.toJson());
      if (mounted) {
        // Optionnel: SnackBar de succès si besoin
        // ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Information ajoutée.")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erreur d'ajout de l'information: $e")));
      }
    }
  }

  Future<void> _deleteInfoChantierDB(String infoId) async {
    try {
      await _infosChantierRefGlobal.doc(infoId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Information supprimée avec succès.")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Erreur de suppression de l'information: $e")));
      }
    }
  }

  Future<void> _updateInfoChantierDB(InfoChantier info) async {
    try {
      await _infosChantierRefGlobal.doc(info.id).update(info.toJson());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Information mise à jour avec succès.")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Erreur de mise à jour de l'information: $e")));
      }
    }
  }

  void _presenterAjoutInfoChantier() {
    if (_selectedTranche == null || _selectedTranche!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Veuillez d'abord sélectionner une tranche.")),
      );
      return;
    }
    final bool peutAjouterInfo = (_userRoles.contains(roleAdminString) ||
        _userRoles.contains(roleChefDeChantierString)) && _currentUser != null;
    if (!peutAjouterInfo) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Action non autorisée.")));
      return;
    }
    final texte = _infoController.text.trim();
    if (texte.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Veuillez saisir le texte de l'information.")));
      return;
    }
    final nouvelleInfo = InfoChantier(
      id: DateTime
          .now()
          .millisecondsSinceEpoch
          .toString(),
      tranche: _selectedTranche!,
      contenu: texte,
      dateEmission: DateTime.now(),
      auteurIdCreation: _currentUser!.uid,
      auteurNomPrenomCreation: _currentUserNomPrenom,
      roleAuteurCreation: _roleDisplay,
    );
    _addInfoChantierDB(nouvelleInfo);
    _infoController.clear();
  }

  Future<void> _confirmerEtSupprimerInfo(BuildContext itemContext,
      String infoId, String infoContenu) async {
    if (!mounted) return;
    final bool? confirmer = await showDialog<bool>(
      context: context, // Utilise le context du State (_HomeScreenState)
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirmer la suppression'),
          content: Text(
              'Êtes-vous sûr de vouloir supprimer l\'information : "$infoContenu" ?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Annuler'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            TextButton(
              child: const Text(
                  'Supprimer', style: TextStyle(color: Colors.red)),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );

    if (confirmer == true) {
      await _deleteInfoChantierDB(infoId);
    }
  }

  void _presenterModificationInfo(BuildContext itemContext,
      InfoChantier infoAmodifier) {
    if (!mounted) return;
    final TextEditingController modificationController =
    TextEditingController(text: infoAmodifier.contenu);

    showDialog<void>(
      context: context, // Utilise le context du State (_HomeScreenState)
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text("Modifier l'information"),
          content: TextField(
            controller: modificationController,
            decoration: const InputDecoration(
                hintText: "Nouveau texte de l'information"),
            maxLines: null,
          ),
          // ...
          actions: [
            TextButton(
              onPressed: () {
                // AJOUT DES ACCOLADES ICI
                if (Navigator.canPop(dialogContext)) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: const Text("Annuler"),
            ),
            TextButton(
              onPressed: () async {
                final nouveauContenu = modificationController.text.trim();
                if (nouveauContenu.isNotEmpty &&
                    nouveauContenu != infoAmodifier.contenu) {
                  final infoMiseAJour = infoAmodifier.copyWith(
                      contenu: nouveauContenu);

                  // Fermer le dialogue AVANT l'await
                  if (Navigator.canPop(dialogContext)) {
                    Navigator.of(dialogContext).pop();
                  }

                  await _updateInfoChantierDB(infoMiseAJour); // ASYNC GAP

                } else if (nouveauContenu.isEmpty) {
                  // Pour le SnackBar dans le dialogue, dialogContext est sûr ici car pas d'await avant.
                  ScaffoldMessenger
                      .of(dialogContext)
                      .showSnackBar(
                    const SnackBar(
                        content: Text('Le contenu ne peut pas être vide.')),
                  );
                } else { // Cas où nouveauContenu == infoAmodifier.contenu (rien n'a changé)
                  // Fermer simplement le dialogue.
                  if (Navigator.canPop(dialogContext)) {
                    Navigator.of(dialogContext).pop();
                  }
                }
              },
              child: const Text("Enregistrer"),
            )
          ],
        );
      },
    ).then((_) {
      WidgetsBinding.instance.addPostFrameCallback((
          _) { // Dispose après le cycle de frame
        modificationController.dispose();
      });
    });
  }

  String _formatDateSimple(DateTime? date, {bool showTime = true}) {
    if (date == null) return 'Date inconnue';
    String day = date.day.toString().padLeft(2, '0');
    String month = date.month.toString().padLeft(2, '0');
    String year = date.year.toString();
    if (showTime) {
      String hour = date.hour.toString().padLeft(2, '0');
      String minute = date.minute.toString().padLeft(2, '0');
      return "$day/$month/$year $hour:$minute";
    }
    return "$day/$month/$year";
  }

  Widget _buildLoadingScreen(String message) {
    return Scaffold(
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.green)),
          const SizedBox(height: 20),
          Text(message, style: const TextStyle(fontSize: 16)),
        ]),
      ),
    );
  }

  Widget _buildBlocHeader(String title,
      {MaterialColor headerColor = Colors.green}) {
    return Container(
      color: headerColor.shade100,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(children: [
        Expanded(
            child: Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: headerColor.shade900))),
        Text(_formatDateSimple(DateTime.now(), showTime: false),
            style: TextStyle(fontSize: 14, color: headerColor.shade700)),
      ]),
    );
  }

  Widget _buildChampAjoutConsigne() {
    final bool peutAfficherChampAjout = (_userRoles.contains(roleAdminString) ||
        _userRoles.contains(roleChefDeChantierString)) &&
        _currentUser != null;

    if (!peutAfficherChampAjout || _selectedTranche == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12.0, 8.0, 12.0, 12.0),
      child: Material(
        elevation: 2.0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
            side: BorderSide(color: Colors.grey.shade300)),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Ajouter une nouvelle consigne pour la tranche: $_selectedTranche",
                style: Theme
                    .of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(
                    color: Colors.blueGrey.shade700,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _consigneController,
                      maxLines: null,
                      minLines: 2,
                      decoration: InputDecoration(
                        hintText: "Texte de la consigne...",
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.0)),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add_task_outlined, size: 20),
                    onPressed: _presenterAjoutConsigne,
                    label: const Text("Valider"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0)),
                      textStyle: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () {
                      _safelySetState(() {
                        _estPrioritaireNouvelleConsigne =
                        !_estPrioritaireNouvelleConsigne;
                      });
                    },
                    borderRadius: BorderRadius.circular(4.0),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: _estPrioritaireNouvelleConsigne,
                            activeColor: Colors.orange.shade800,
                            visualDensity: VisualDensity.compact,
                            onChanged: (val) =>
                                _safelySetState(() =>
                                _estPrioritaireNouvelleConsigne = val ?? false),
                          ),
                          Text("Marquer comme prioritaire", style: TextStyle(
                              color: Colors.grey.shade800)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChampAjoutInfo() {
    final bool peutAfficherChampAjoutInfo =
        (_userRoles.contains(roleAdminString) ||
            _userRoles.contains(roleChefDeChantierString)) &&
            _currentUser != null;

    if (!peutAfficherChampAjoutInfo) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Material(
        elevation: 2.0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
            side: BorderSide(color: Colors.blue.shade200)),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Ajouter une nouvelle information",
                style: Theme
                    .of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Colors.blue.shade800)),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  child: TextField(
                      controller: _infoController,
                      maxLines: null,
                      minLines: 2,
                      decoration: InputDecoration(
                          hintText: "Texte de l'information...",
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8.0)),
                          filled: true,
                          fillColor: Colors.blue.shade50))),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                  icon: const Icon(Icons.add_comment_outlined),
                  onPressed: _presenterAjoutInfoChantier,
                  label: const Text("Ajouter Info"),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0)))),
            ]),
          ]),
        ),
      ),
    );
  }

  // =========================================================================
  // ============= MÉTHODE _buildConsignesList (avec Observations) =========
  // =========================================================================
  // =========================================================================
// ============= MÉTHODE _buildConsignesList (CORRIGÉE) ===================
// =========================================================================
  Widget _buildConsignesList(List<Consigne> consignes) {
    if (_selectedTranche == null) {
      // CORRECTION : Supprimé 'Expanded'
      return const Center(child: Text("Veuillez sélectionner une tranche."));
    }
    if (consignes.isEmpty) {
      // CORRECTION : Supprimé 'Expanded'
      return const Center(
          child: Text("Aucune consigne active pour cette tranche."));
    }

    final bool peutAgirSurConsigne = (_userRoles.contains(roleAdminString) ||
        _userRoles.contains(roleChefDeChantierString) ||
        _userRoles.contains(roleChefEquipeString)) &&
        _currentUser != null;

    final bool peutSupprimerConsigneNonValidee =
        (_userRoles.contains(roleAdminString) ||
            _userRoles.contains(roleChefDeChantierString)) &&
            _currentUser != null;

    // CORRECTION : Supprimé 'Expanded' qui enveloppait le ListView.builder
    return ListView.builder(
      itemCount: consignes.length,
      itemBuilder: (context, index) {
        final c = consignes[index];

        // Votre logique pour les contrôleurs _obsNonRealiseeControllers et _obsValidationControllers
        // reste ici, elle est correcte.
        if (!_obsNonRealiseeControllers.containsKey(c.id)) {
          _obsNonRealiseeControllers[c.id] = TextEditingController();
        }

        if (!_obsValidationControllers.containsKey(c.id)) {
          _obsValidationControllers[c.id] = TextEditingController(
              text: c.commentaireValidation
                  ?.split('\n-')
                  .first
                  .trim() ?? "");
        } else {
          final currentControllerText = _obsValidationControllers[c.id]!
              .text;
          final currentDataComment = c.commentaireValidation
              ?.split('\n-')
              .first
              .trim() ?? "";
          if (currentControllerText != currentDataComment) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted &&
                  _obsValidationControllers.containsKey(c.id) &&
                  _obsValidationControllers[c.id] != null) {
                _obsValidationControllers[c.id]!.text =
                    currentDataComment;
              }
            });
          }
        }

        // Le reste de votre Card et de la logique de l'itemBuilder
        // est ici et reste inchangé.
        return Card(
          key: ValueKey(c.id),
          color: c.estPrioritaire && !c.estValidee
              ? Colors.red.shade50
              : (c.estValidee ? Colors.green.shade50 : Colors.grey
              .shade100),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          elevation: c.estPrioritaire && !c.estValidee ? 4.0 : 2.0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
            side: c.estPrioritaire && !c.estValidee
                ? BorderSide(color: Colors.red.shade200, width: 1.5)
                : BorderSide(color: Colors.grey.shade300),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (peutAgirSurConsigne)
                      Padding(
                        padding: const EdgeInsets.only(
                            right: 8.0, top: 6.0),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: c.estValidee,
                            onChanged: (val) {
                              if (val != null) {
                                _presenterValidationConsigne(c, val);
                              }
                            },
                            activeColor: Colors.green.shade600,
                            checkColor: Colors.white,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                    if (!peutAgirSurConsigne && c.estValidee)
                      Padding(
                        padding: const EdgeInsets.only(
                            right: 8.0, top: 10.0),
                        child: Icon(Icons.check_circle,
                            color: Colors.green.shade600, size: 24),
                      ),
                    if (!peutAgirSurConsigne && !c.estValidee)
                      const SizedBox(width: 32, height: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.contenu,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: c.estPrioritaire &&
                                  !c.estValidee
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: c.estPrioritaire && !c.estValidee
                                  ? Colors.red.shade800
                                  : (c.estValidee
                                  ? Colors.grey.shade700
                                  : Colors.black87),
                              decoration: c.estValidee
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationColor: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Créée par: ${c.auteurNomPrenomCreation} (${c
                                .roleAuteurCreation}) le ${_formatDateSimple(
                                c.dateEmission, showTime: false)}",
                            style: TextStyle(
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                                color: Colors.grey.shade600),
                          ),
                          if (c.categorie != null &&
                              c.categorie!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text("Catégorie: ${c.categorie}",
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.blueGrey.shade700)),
                            ),
                          if (c.enjeu != null && c.enjeu!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.shield_outlined,
                                      color: Colors.blue.shade700,
                                      size: 14),
                                  const SizedBox(width: 4),
                                  Text("Enjeu: ${c.enjeu}",
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.blue.shade800,
                                          fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (peutSupprimerConsigneNonValidee && !c.estValidee)
                      IconButton(
                        icon: Icon(Icons.delete_outline,
                            color: Colors.grey.shade700, size: 22),
                        tooltip: "Supprimer la consigne",
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () async {
                          final confirmer = await showDialog<bool>(
                            context: context,
                            builder: (ctx) =>
                                AlertDialog(
                                  title: const Text("Confirmation"),
                                  content: Text(
                                      "Supprimer la consigne '${c
                                          .contenu}' ?"),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.of(ctx).pop(false),
                                        child: const Text("Annuler")),
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.of(ctx).pop(true),
                                        child: const Text("Supprimer",
                                            style: TextStyle(
                                                color: Colors.red))),
                                  ],
                                ),
                          );
                          if (confirmer == true) {
                            _obsNonRealiseeControllers
                                .remove(c.id)
                                ?.dispose();
                            _obsValidationControllers
                                .remove(c.id)
                                ?.dispose();
                            await _deleteConsigneDB(c.id);
                          }
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (!c.estValidee && peutAgirSurConsigne)
                  _buildChampObservation(
                    context: context,
                    consigne: c,
                    controller: _obsNonRealiseeControllers[c.id]!,
                    label:
                    "Observation (si non réalisée / en attente) :",
                    hint: "Raison de la non-réalisation, action corrective...",
                    onSave: (texteNouvelleObservation) {
                      _enregistrerObservationNonRealisation(
                          c, texteNouvelleObservation);
                    },
                    backgroundColor: Colors.orange.shade50,
                    iconColor: Colors.orange.shade800,
                  ),
                if (c.commentairesNonRealisation != null &&
                    c.commentairesNonRealisation!.isNotEmpty)
                  Padding(
                    padding:
                    const EdgeInsets.only(
                        top: 10.0, left: 4.0, right: 4.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            "Historique des observations (non réalisée/en attente):",
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade900)),
                        const SizedBox(height: 6),
                        ...c.commentairesNonRealisation!.map((commentaire) {
                          return Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              margin: const EdgeInsets.only(
                                  bottom: 6),
                              decoration: BoxDecoration(
                                  color: Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(
                                      6),
                                  border:
                                  Border.all(
                                      color: Colors.orange.shade200)),
                              child: RichText(
                                  text: TextSpan(
                                      style: TextStyle(fontSize: 13,
                                          color: Colors.orange
                                              .shade900),
                                      children: [
                                        TextSpan(text: "${commentaire
                                            .texte}\n"),
                                        TextSpan(
                                            text: "- ${commentaire
                                                .auteurNomPrenom} (${commentaire
                                                .roleAuteur}) le ${_formatDateSimple(
                                                commentaire.date,
                                                showTime: true)}",
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontStyle: FontStyle
                                                    .italic,
                                                color: Colors.orange
                                                    .shade700)
                                        )
                                      ]
                                  )
                              )
                          );
                        })
                      ],
                    ),
                  ),
                if (c.estValidee && peutAgirSurConsigne)
                  Padding(
                    padding: const EdgeInsets.only(top: 10.0),
                    child: _buildChampObservation(
                      context: context,
                      consigne: c,
                      controller: _obsValidationControllers[c.id]!,
                      label: "Observation (après validation) :",
                      hint: "Détails supplémentaires, remarques...",
                      onSave: (texteObservation) {
                        _enregistrerObservationValidation(
                            c, texteObservation);
                      },
                      backgroundColor: Colors.green.shade50,
                      iconColor: Colors.green.shade800,
                    ),
                  ),
                if (c.commentaireValidation != null &&
                    c.commentaireValidation!.isNotEmpty &&
                    (!peutAgirSurConsigne || (peutAgirSurConsigne &&
                        _obsValidationControllers[c.id]?.text ==
                            c.commentaireValidation
                                ?.split('\n-')
                                .first
                                .trim())))
                  Padding(
                    padding:
                    const EdgeInsets.only(
                        top: 10.0, left: 4.0, right: 4.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Observation de validation :",
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade900)),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(6),
                              border:
                              Border.all(
                                  color: Colors.green.shade200)),
                          child: Text(c.commentaireValidation!,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.green.shade900)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      }, // Fin de itemBuilder
    ); // Fin de ListView.builder
  } // FIN DE LA MÉTHODE _buildConsignesList (CORRIGÉE)


  Widget _buildChampObservation({
    required BuildContext context,
    required Consigne consigne,
    required TextEditingController controller,
    required String label,
    required String hint,
    required Function(String) onSave,
    Color backgroundColor = Colors.white,
    Color iconColor = Colors.grey,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          maxLines: null,
          minLines: 1,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: backgroundColor,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6.0),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6.0),
              borderSide: BorderSide(color: Colors.grey.shade400),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6.0),
              borderSide: BorderSide(color: Theme
                  .of(context)
                  .primaryColor, width: 1.5),
            ),
            suffixIcon: IconButton(
              icon: Icon(Icons.save_alt_outlined, color: iconColor, size: 20),
              tooltip: "Enregistrer l'observation",
              onPressed: () {
                onSave(controller.text.trim());
                FocusScope.of(context).unfocus(); // Cacher le clavier
              },
            ),
          ),
          onSubmitted: (
              text) { // Enregistrer aussi si l'utilisateur appuie sur "Terminé" sur le clavier
            onSave(text.trim());
          },
        ),
      ],
    );
  }

  Widget _buildConsignesBlocWidget() {
    if (_selectedTranche == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: _tranches.isEmpty
              ? const Text(
              "Aucune tranche n'est configurée. Contactez un administrateur.")
              : const Text(
              "Veuillez sélectionner une tranche dans l'AppBar pour voir les consignes."),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBlocHeader(
            "Consignes - $_selectedTranche", headerColor: Colors.green),
        Expanded(
          child: StreamBuilder<List<Consigne>>(
            stream: getConsignesStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Erreur: ${snapshot.error}'));
              }
              final toutesLesConsignes = snapshot.data ?? [];
              // On affiche seulement les consignes NON validées dans ce bloc
              final consignesActives = toutesLesConsignes.where((
                  consigne) => !consigne.estValidee).toList();
              return _buildConsignesList(consignesActives);
            },
          ),
        ),
        _buildChampAjoutConsigne(),
      ],
    );
  }

  Widget _buildInfosBlocWidget() {
    if (_selectedTranche == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: _tranches.isEmpty
              ? const Text("Aucune tranche n'est configurée pour les infos.")
              : const Text(
              "Veuillez sélectionner une tranche pour voir les informations."),
        ),
      );
    }
    final bool peutModifierInfo = (_userRoles.contains(roleAdminString) ||
        _userRoles.contains(roleChefDeChantierString)) && _currentUser != null;
    final bool peutSupprimerInfo = _userRoles.contains(roleAdminString) &&
        _currentUser != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBlocHeader("Informations - $_selectedTranche",
            headerColor: Colors.blue),
        Expanded(
          child: StreamBuilder<List<InfoChantier>>(
            stream: getInfosChantierStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue)));
              }
              if (snapshot.hasError) {
                return Center(
                    child: Text('Erreur chargement infos: ${snapshot.error}'));
              }
              final infos = snapshot.data ?? [];
              if (infos.isEmpty) {
                return const Center(
                    child: Text("Aucune information pour cette tranche."));
              }
              return ListView.builder(
                itemCount: infos.length,
                itemBuilder: (itemBuilderContext, index) {
                  final info = infos[index];
                  return Card(
                    key: ValueKey(info.id),
                    margin: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12.0, 12.0, 4.0, 12.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Padding(
                            padding: EdgeInsets.only(right: 12.0, top: 2.0),
                            child: Icon(Icons.info_outline, color: Colors.blue,
                                size: 24),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  info.contenu,
                                  style: const TextStyle(fontSize: 16,
                                      fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Publié par: ${info
                                      .auteurNomPrenomCreation} (${info
                                      .roleAuteurCreation})',
                                  style: TextStyle(fontSize: 11,
                                      color: Colors.grey.shade700),
                                ),
                                Text(
                                  'Le: ${_formatDateSimple(info.dateEmission)}',
                                  style: TextStyle(fontSize: 11,
                                      color: Colors.grey.shade700),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              if (peutModifierInfo)
                                IconButton(
                                  icon: Icon(
                                      Icons.edit_note_outlined,
                                      color: Colors.orange.shade700,
                                      size: 22),
                                  tooltip: 'Modifier',
                                  padding: const EdgeInsets.all(4),
                                  constraints: const BoxConstraints(),
                                  onPressed: () {
                                    _presenterModificationInfo(
                                        itemBuilderContext, info);
                                  },
                                ),
                              if (peutSupprimerInfo)
                                IconButton(
                                  icon: Icon(
                                      Icons.delete_forever_outlined,
                                      color: Colors.red.shade600,
                                      size: 22),
                                  tooltip: 'Supprimer',
                                  padding: const EdgeInsets.all(4),
                                  constraints: const BoxConstraints(),
                                  onPressed: () {
                                    _confirmerEtSupprimerInfo(
                                        itemBuilderContext, info.id,
                                        info.contenu);
                                  },
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        _buildChampAjoutInfo(),
      ],
    );
  }

  Widget _buildValideBlocWidget() {
    if (_selectedTranche == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: _tranches.isEmpty
              ? const Text("Aucune tranche n'est configurée pour les archives.")
              : const Text(
              "Veuillez sélectionner une tranche pour voir les archives."),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBlocHeader("Archives (Consignes) - $_selectedTranche",
            headerColor: Colors.teal),
        Expanded(
          child: StreamBuilder<List<Consigne>>(
            stream: getConsignesStream().map((list) {
              // Dans le bloc archives, on affiche seulement les consignes VALIDÉES
              return list.where((c) => c.estValidee).toList();
            }),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.teal)));
              }
              if (snapshot.hasError) {
                return Center(child: Text(
                    'Erreur chargement archives: ${snapshot.error}'));
              }
              final consignesArchivees = snapshot.data ?? [];
              if (consignesArchivees.isEmpty) {
                return const Center(child: Text(
                    "Aucune consigne archivée pour cette tranche."));
              }
              return ListView.builder(
                itemCount: consignesArchivees.length,
                itemBuilder: (context, index) {
                  final c = consignesArchivees[index];
                  return Card(
                    key: ValueKey("archive_${c.id}"),
                    margin: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    color: c.estNonRealiseeEffectivement && c.estPrioritaire &&
                        c
                            .estValidee // Si elle a été marquée non réalisée mais ensuite validée
                        ? Colors.yellow
                        .shade100 // Couleur distincte pour ce cas
                        : (c.estValidee ? Colors.green.shade50 : Colors.grey
                        .shade200),
                    child: ListTile(
                      leading: c.estValidee
                          ? const Icon(
                          Icons.check_circle_outline, color: Colors.green)
                          : (c
                          .estNonRealiseeEffectivement // Devrait être rare ici car on filtre sur estValidee=true
                          ? const Icon(Icons.report_problem_outlined,
                          color: Colors.orange)
                          : const Icon(Icons.archive_outlined, color: Colors
                          .grey)),
                      title: Text(c.contenu, style: TextStyle(decoration: c
                          .estValidee ? TextDecoration.lineThrough : null)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Créée par: ${c.auteurNomPrenomCreation} (${c
                              .roleAuteurCreation})"),
                          if (c.categorie != null && c.categorie!.isNotEmpty)
                            Text("Catégorie: ${c.categorie}", style: TextStyle(
                                fontSize: 11, color: Colors.blueGrey.shade600)),
                          if (c.enjeu != null && c.enjeu!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.shield_outlined,
                                      color: Colors.blue.shade600, size: 12),
                                  const SizedBox(width: 3),
                                  Text("Enjeu: ${c.enjeu}", style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.blue.shade700)),
                                ],
                              ),
                            ),
                          if (c.estValidee && c.dateValidation != null)
                            Text("Validée le: ${_formatDateSimple(
                                c.dateValidation, showTime: true)} par ${c
                                .idAuteurValidation != null ? '(ID: ${c
                                .idAuteurValidation})' : ''}",
                                // Afficher qui a validé si possible
                                style: const TextStyle(fontSize: 11)),
                          if (c.commentairesNonRealisation != null &&
                              c.commentairesNonRealisation!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      "Historique non-réalisation (avant validation):",
                                      style: TextStyle(fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.orange.shade700)),
                                  ...c.commentairesNonRealisation!.map((obs) =>
                                      Text(
                                        "- ${obs.texte} (${obs
                                            .auteurNomPrenom} le ${_formatDateSimple(
                                            obs.date, showTime: false)})",
                                        style: TextStyle(fontSize: 10,
                                            fontStyle: FontStyle.italic,
                                            color: Colors.orange.shade800),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 2,
                                      ))
                                ],
                              ),
                            ),
                          if (c.commentaireValidation != null &&
                              c.commentaireValidation!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                  "Obs. Validation: ${c.commentaireValidation}",
                                  // Affiche le commentaire complet avec auteur/date
                                  style: TextStyle(fontSize: 11,
                                      fontStyle: FontStyle.italic,
                                      color: Colors.green.shade700)),
                            ),
                        ],
                      ),
                      trailing: _userRoles.contains(roleAdminString)
                          ? IconButton(
                        icon: Icon(Icons.delete_forever_outlined,
                            color: Colors.red.shade700),
                        tooltip: 'Supprimer définitivement l\'archive',
                        onPressed: () {
                          _confirmerEtSupprimerConsigneArchivee(c);
                        },
                      )
                          : null,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showTrancheSelector() async {
    if (!mounted) {
      return;
    }

    if (_tranches.isEmpty) {
      if (_userRoles.contains(roleAdminString)) {
        final goToConfig = await showDialog<bool>(
            context: context,
            builder: (ctx) =>
                AlertDialog(
                  title: const Text("Aucune tranche configurée"),
                  content: const Text(
                      "Il n'y a actuellement aucune tranche. Voulez-vous aller à l'écran de configuration des tranches ?"),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text("Annuler")),
                    TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text("Configurer",
                            style: TextStyle(color: Colors.orange))),
                  ],
                ));

        if (!mounted) return;

        if (goToConfig == true) {
          await Navigator.push( // Appel corrigé
            context,
            MaterialPageRoute(
                builder: (routeContext) => const ManageTranchesScreen()),
          );

          if (!mounted) return;
          _loadTranches();
        }
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  "Aucune tranche n'est configurée. Contactez un administrateur.")),
        );
      }
      return;
    }

    final nouvelleTranche = await showDialog<String>(
      context: context,
      builder: (dialogContext) => // Renommé pour clarté
      SimpleDialog(
        title: const Text("Sélectionner une tranche"),
        children: _tranches
            .map((t) =>
            SimpleDialogOption(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text(t,
                    style: TextStyle(
                        fontWeight: t == _selectedTranche
                            ? FontWeight.bold
                            : FontWeight.normal)),
              ),
              onPressed: () =>
                  Navigator.pop(dialogContext, t), // Utilise dialogContext
            ))
            .toList(),
      ),
    );

    if (!mounted) return;

    if (nouvelleTranche != null && nouvelleTranche != _selectedTranche) {
      _safelySetState(() =>
      _selectedTranche =
          nouvelleTranche);
    }
  }

  @override
  Widget build(BuildContext context) {

    if (_loadingState == HomeScreenLoadingState.initializing ||
        _loadingState == HomeScreenLoadingState.loadingTranches) {
      return _buildLoadingScreen("Chargement des données...");
    }

    if (_loadingState == HomeScreenLoadingState.unauthenticated) {
      return _buildLoadingScreen("Redirection vers la sélection du rôle...");
    }

    if (_loadingState == HomeScreenLoadingState.error) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 50),
                const SizedBox(height: 16),
                const Text(
                    "Une erreur est survenue lors du chargement des données.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16)),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text("Réessayer"),
                  onPressed: _loadUserDataAndRoles,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme
                        .of(context)
                        .colorScheme
                        .primary,
                    foregroundColor: Theme
                        .of(context)
                        .colorScheme
                        .onPrimary,
                  ),
                )
              ],
            ),
          ),
        ),
      );
    }

    if (_selectedTranche == null &&
        _tranches.isEmpty &&
        _loadingState == HomeScreenLoadingState.ready) {
      // Cas où tout est chargé mais aucune tranche n'est configurée du tout.
      return Scaffold(
        appBar: AppBar(
          title: const Text("Gestion Chantier"),
          backgroundColor: Colors.grey.shade700,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.logout_outlined),
              tooltip: "Déconnexion / Changer de rôle",
              onPressed: _triggerReSelectionAndNavigate,
            ),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.layers_clear_outlined, size: 60,
                    color: Colors.orange.shade300),
                const SizedBox(height: 20),
                const Text(
                  "Aucune tranche n'est actuellement configurée pour cette application.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 10),
                Text(
                  _userRoles.contains(roleAdminString)
                      ? "En tant qu'administrateur, vous pouvez configurer les tranches initiales."
                      : "Veuillez contacter un administrateur pour configurer les tranches.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                ),
                if (_userRoles.contains(roleAdminString))
                  Padding(
                    padding: const EdgeInsets.only(top: 20.0),
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.settings_applications_outlined),
                      label: const Text("Configurer les Tranches"),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (
                              context) => const ManageTranchesScreen()),
                        ).then((_) => _loadTranches());
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    Color appBarColor = Colors.green.shade700;
    if (_userRoles.contains(roleAdminString)) {
      appBarColor = Colors.redAccent.shade700;
    }

    List<Widget> stackChildren = [
      _buildConsignesBlocWidget(),
      _buildInfosBlocWidget(),
      _buildValideBlocWidget(),
    ];

    List<BottomNavigationBarItem> navBarItems = [
      const BottomNavigationBarItem(
          icon: Icon(Icons.list_alt_outlined), label: 'Consignes'),
      const BottomNavigationBarItem(
          icon: Icon(Icons.info_outline), label: 'Infos'),
      const BottomNavigationBarItem(
          icon: Icon(Icons.archive_outlined), label: 'Archives'),
    ];

    if (_userRoles.contains(roleAdminString)) {
      stackChildren.add(Center( // Placeholder pour l'onglet Admin
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("Administration", style: Theme
                  .of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: appBarColor)),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                icon: const Icon(Icons.construction_outlined),
                label: const Text("Gérer les Tranches"),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const ManageTranchesScreen()),
                  ).then((_) => _loadTranches());
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: appBarColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(200, 50),
                ),
              ),
              const SizedBox(height: 15),
              ElevatedButton.icon(
                icon: const Icon(Icons.people_alt_outlined),
                label: const Text("Gérer les Utilisateurs (N/A)"),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text(
                          "Fonctionnalité de gestion des utilisateurs non implémentée.")));
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: appBarColor.withValues(alpha: 0.7),
                  // Moins proéminent
                  foregroundColor: Colors.white,
                  minimumSize: const Size(200, 50),
                ),
              ),
            ],
          ),
        ),
      ));
      navBarItems.add(const BottomNavigationBarItem(
          icon: Icon(Icons.settings_applications_outlined), label: 'Admin'));
    }

    if (_currentIndex >= stackChildren.length) {
      _currentIndex = 0;
    }

    return Scaffold(
      appBar: AppBar(
          title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Tranche: ${_selectedTranche ?? 'Sélectionner...'}"),
                Text("Mode: $_roleDisplay ($_currentUserNomPrenom)",
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.normal)),
              ]),
          backgroundColor: appBarColor,
          foregroundColor: Colors.white,
          leading: (_tranches.isNotEmpty ||
              _userRoles.contains(roleAdminString))
              ? IconButton(
              icon: const Icon(Icons.layers_outlined),
              tooltip: "Sélectionner une tranche",
              onPressed: _showTrancheSelector)
              : null,
          actions: [
            IconButton(
              icon: const Icon(Icons.logout_outlined),
              tooltip: "Déconnexion / Changer de rôle",
              onPressed: _triggerReSelectionAndNavigate,
            ),
          ]),
      body: SafeArea(
        child: IndexedStack( // Utiliser IndexedStack pour préserver l'état des onglets
          index: _currentIndex,
          children: stackChildren,
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          _safelySetState(() {
            _currentIndex = index;
          });
        },
        items: navBarItems,
        selectedItemColor: appBarColor,
        unselectedItemColor: Colors.grey.shade600,
        type: BottomNavigationBarType.fixed,
        // Pour afficher tous les libellés
        showUnselectedLabels: true, // Afficher les libellés même non sélectionnés
      ),
    );
  }
} // Fin de la classe _HomeScreenState