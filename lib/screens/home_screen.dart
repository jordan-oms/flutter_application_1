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
import 'archive_screen.dart';
import 'dosimetrie_dialog.dart';
import 'gerer_les_utilisateur.dart';
import './chantier_plus_screen.dart';

// ... (vos imports existants)
import '../widgets/tranche_selector.dart';
import '../main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'detail_repere_screen.dart';

// Constantes pour les rôles
const String roleAdminString = "administrateur";
const String roleChefDeChantierString = "chef_de_chantier";
const String roleChefEquipeString = "chef_equipe";
const String roleIntervenantString = "intervenant";

// Options pour le dialogue de sélection des enjeux
const List<String> optionsEnjeux = [
  'Sûreté',
  'RP',
  'Sécurité',
];

// Classe pour comparer les listes de consignes et éviter les reconstructions inutiles
class _ConsignesCache {
  List<Consigne>? _lastList;

  bool hasChanged(List<Consigne> newList) {
    if (_lastList == null) {
      _lastList = newList;
      return true;
    }

    // Comparaison rapide par longueur
    if (_lastList!.length != newList.length) {
      _lastList = newList;
      return true;
    }

    // Comparaison par ID et propriétés clés
    for (int i = 0; i < _lastList!.length; i++) {
      final oldC = _lastList![i];
      final newC = newList[i];

      if (oldC.id != newC.id ||
          oldC.estValidee != newC.estValidee ||
          oldC.contenu != newC.contenu ||
          oldC.commentairesNonRealisation?.length !=
              newC.commentairesNonRealisation?.length ||
          oldC.dosimetrieInfo != newC.dosimetrieInfo) {
        _lastList = newList;
        return true;
      }
    }

    return false;
  }

  void clear() {
    _lastList = null;
  }
}

enum HomeScreenLoadingState {
  initializing,
  loadingTranches,
  ready,
  error,
  unauthenticated,
}

class HomeScreen extends StatefulWidget {
  final String? userId; // Devient optionnel
  final String? initialTranche;
  final bool isReadOnly; // Nouveau paramètre

  const HomeScreen({
    super.key,
    this.userId,
    this.initialTranche,
    this.isReadOnly = false, // Valeur par défaut
  }) : assert(isReadOnly || userId != null,
            'userId ne peut être nul que si isReadOnly est vrai.');

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HomeScreenLoadingState _loadingState = HomeScreenLoadingState.initializing;
  User? _currentUser;
  List<String> _userRoles = [];
  String _currentUserNomPrenom = "Chargement...";
  String _roleDisplay = "Chargement...";
  int _currentIndex = 0;
  int _unreadInfosCount = 0;
  late ValueNotifier<int> _unreadCountNotifier;

  // Cache pour éviter les reconstructions inutiles
  final _ConsignesCache _consignesCache = _ConsignesCache();

  String? _selectedTranche;
  String? _favoriteTranche;
  List<String> _tranches = [];

  final FocusNode _ajoutConsigneFocusNode = FocusNode();

  final TextEditingController _consigneController = TextEditingController();
  bool _estPrioritaireNouvelleConsigne = false;
  String? _selectedEnjeuPourNouvelleConsigne;

  Consigne? _consigneEnEdition;
  bool _isAddingConsigne = false;

  final TextEditingController _observationValidationDialogController =
      TextEditingController();
  final TextEditingController _obsvalitatiobDialogDosimetrie =
      TextEditingController();

  final CollectionReference _consignesRefGlobal =
      FirebaseFirestore.instance.collection('consignes');
  final Map<String, TextEditingController> _obsNonRealiseeControllers = {};
  final Map<String, TextEditingController> _obsValidationControllers = {};
  List<Consigne> _lastConsignesSnapshot = [];
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
  final CollectionReference _infosChantierRefGlobal =
      FirebaseFirestore.instance.collection('infos_chantier');
  final DocumentReference _tranchesConfigRef = FirebaseFirestore.instance
      .collection('app_config')
      .doc('tranches_config');
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // On ajoute un raccourci pour savoir si on est en mode lecture seule
  bool get _isReadOnly => widget.isReadOnly;

  @override
  void initState() {
    super.initState();
    _unreadCountNotifier = ValueNotifier<int>(0);
    // Si on est en lecture seule, on ne charge que les tranches.
    if (_isReadOnly) {
      _safelySetState(
          () => _loadingState = HomeScreenLoadingState.loadingTranches);
      _loadTranches().then((_) {
        _safelySetState(() => _loadingState = HomeScreenLoadingState.ready);
      });
    } else {
      // Sinon, on lance le processus de vérification complet comme avant.
      _checkVersionAndInitialize();
    }
  }

  @override
  void dispose() {
    _ajoutConsigneFocusNode.dispose();
    _consigneController.dispose();
    _infoController.dispose();
    _obsNonRealiseeControllers.forEach((_, controller) => controller.dispose());
    _obsNonRealiseeControllers.clear();
    _obsValidationControllers.forEach((_, controller) => controller.dispose());
    _obsValidationControllers.clear();
    _observationValidationDialogController.dispose();
    _obsvalitatiobDialogDosimetrie.dispose();
    _unreadCountNotifier.dispose();
    super.dispose();
  }

  void _updateUnreadCount(List<InfoChantier> infos) async {
    // Nouveau système : compter les infos non lues par l'utilisateur actuel
    int count = 0;

    for (final info in infos) {
      // Vérifier si l'utilisateur actuel a déjà lu cette info
      final bool estLueParUtilisateur =
          info.lectures.any((lecture) => lecture.userId == _currentUser?.uid);
      // Ne compter que si l'utilisateur ne l'a pas lue ET n'est pas l'auteur
      final bool estAuteur = info.auteurIdCreation == _currentUser?.uid;

      if (!estLueParUtilisateur && !estAuteur) {
        count++;
      }
    }

    if (mounted && _unreadInfosCount != count) {
      setState(() {
        _unreadInfosCount = count;
      });
    }
  }

// Analyse le texte pour trouver un repère et redirige vers le bon écran
  void _analyserEtNaviguerVersRepere(String texteConsigne) async {
    // Format : 1 chiffre, 3 lettres, 3 chiffres, 2 lettres
    final regExpRepere = RegExp(r'\d[A-Z]{3}\d{3}[A-Z]{2}');
    final match = regExpRepere.firstMatch(texteConsigne.toUpperCase());

    if (match != null) {
      String repereId = match.group(0)!;

      // Vérifier si le repère existe dans Firestore avant d'ouvrir
      try {
        final doc = await FirebaseFirestore.instance
            .collection('reperes')
            .doc(repereId)
            .get();

        if (doc.exists) {
          // Si le repère existe, on ouvre directement ses détails
          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DetailRepereScreen(repereId: repereId),
            ),
          );
        } else {
          // Si le repère est trouvé dans le texte mais pas en base, on va sur Chantier+
          _allerVersChantierPlus();
        }
      } catch (e) {
        _allerVersChantierPlus();
      }
    } else {
      // Aucun repère trouvé dans le texte -> Chantier+
      _allerVersChantierPlus();
    }
  }

// Fonction de secours pour naviguer vers Chantier+
  void _allerVersChantierPlus() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ChantierPlusScreen()),
    );
  }

  void _presenterAjoutConsigne() {
    if (_consigneEnEdition != null) {
      FocusScope.of(context).requestFocus(_ajoutConsigneFocusNode);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                "Veuillez d'abord terminer la modification en cours ou l'annuler.")),
      );
      return;
    }
    setState(() {
      _isAddingConsigne = true;
    });
    FocusScope.of(context).requestFocus(_ajoutConsigneFocusNode);
  }

  void _presenterModificationConsigne(Consigne consigne) {
    setState(() {
      _consigneEnEdition = consigne;
      _consigneController.text = consigne.contenu;
      _estPrioritaireNouvelleConsigne = consigne.estPrioritaire;
      _selectedEnjeuPourNouvelleConsigne = consigne.enjeu;
      _isAddingConsigne = true;
    });
    FocusScope.of(context).requestFocus(_ajoutConsigneFocusNode);
  }

  Future<void> _enregistrerOuModifierConsigne() async {
    final contenu = _consigneController.text.trim();
    if (contenu.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Le contenu de la consigne ne peut pas être vide.")),
      );
      return;
    }
    if (_currentUser == null) return;
    FocusScope.of(context).unfocus();
    try {
      if (_consigneEnEdition != null) {
        Map<String, dynamic> dataToUpdate = {
          'contenu': contenu,
          'estPrioritaire': _estPrioritaireNouvelleConsigne,
          'enjeu': _selectedEnjeuPourNouvelleConsigne,
          'modifieLe': FieldValue.serverTimestamp(),
          'modifiePar': _currentUserNomPrenom,
        };
        await _consignesRefGlobal
            .doc(_consigneEnEdition!.id)
            .update(dataToUpdate);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Consigne modifiée avec succès !'),
              backgroundColor: Colors.green),
        );
      } else {
        await _presenterAjoutConsigneHandler();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erreur lors de l\'enregistrement : $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _consigneController.clear();
          _estPrioritaireNouvelleConsigne = false;
          _selectedEnjeuPourNouvelleConsigne = null;
          _consigneEnEdition = null;
        });
      }
    }
  }

  void _confirmerSuppressionConsigne(Consigne consigne) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirmer la suppression'),
          content: Text(
              'Êtes-vous sûr de vouloir supprimer la consigne : "${consigne.contenu}" ?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Annuler'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Supprimer'),
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                try {
                  await _consignesRefGlobal.doc(consigne.id).delete();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Consigne supprimée avec succès.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Erreur lors de la suppression : $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _presenterSuppressionConsigne() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Action impossible"),
          content: const Text(
              "Pour supprimer une consigne, veuillez utiliser le bouton 'poubelle' situé directement sur la carte de la consigne que vous souhaitez enlever."),
          actions: <Widget>[
            TextButton(
              child: const Text('Compris'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _safelySetState(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  Future<void> _loadUserDataAndRoles() async {
    // ... (Cette fonction reste inchangée, elle est déjà correcte)
    final stopwatch = Stopwatch()..start();
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
      _safelySetState(
          () => _loadingState = HomeScreenLoadingState.unauthenticated);
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
        _favoriteTranche = data['favoriteTranche'] as String?;
        _userRoles = (data['roles'] is List)
            ? List<String>.from(data['roles']
                .map((role) => role.toString().toLowerCase().trim()))
            : [];

        // On récupère le nom et le prénom séparément
        String? nom = data['nom'] as String?;
        String? prenom = data['prenom'] as String?;

        if (nom != null && prenom != null) {
          // Si les deux existent, on les combine
          _currentUserNomPrenom = "$prenom $nom";
        } else if (nom != null || prenom != null) {
          // Si l'un des deux seulement existe
          _currentUserNomPrenom = nom ?? prenom!;
        } else {
          // Si aucun des deux n'est renseigné, on garde l'email ou l'anonyme en dernier recours
          _currentUserNomPrenom = _currentUser!.isAnonymous
              ? "Utilisateur Anonyme"
              : (_currentUser!.email ?? "UID: ${_currentUser!.uid}");
        }
      } else {
        _userRoles = [];
        _favoriteTranche = null;
        _currentUserNomPrenom = _currentUser!.isAnonymous
            ? "Utilisateur Anonyme (Doc Manquant)"
            : (_currentUser!.email ??
                "UID: ${_currentUser!.uid} (Doc Manquant)");
      }
      if (_userRoles.contains(roleAdminString)) {
        _roleDisplay = "Administrateur";
      } else if (_userRoles.contains(roleChefDeChantierString)) {
        _roleDisplay = "Chef de chantier";
      } else if (_userRoles.contains(roleChefEquipeString)) {
        _roleDisplay = "Chef d'équipe";
      } else if (_userRoles.contains(roleIntervenantString)) {
        // <-- AJOUTEZ CE BLOC
        _roleDisplay = "Intervenant";
      } else {
        _roleDisplay = "Rôle Indéfini";
      }
      await _loadTranches();
    } catch (e) {
      if (mounted) {
        _safelySetState(() => _loadingState = HomeScreenLoadingState.error);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  "Erreur de chargement des informations utilisateur: $e")),
        );
      }
    }
    stopwatch.stop();
  }

  Future<void> _loadTranches() async {
    // ... (Cette fonction reste inchangée, elle est déjà correcte)
    if (!mounted) {
      return;
    }
    if (_loadingState != HomeScreenLoadingState.initializing) {
      _safelySetState(
          () => _loadingState = HomeScreenLoadingState.loadingTranches);
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
            if (_favoriteTranche != null &&
                _tranches.contains(_favoriteTranche)) {
              _selectedTranche = _favoriteTranche;
              debugPrint(
                  "Tranche favorite '$_favoriteTranche' chargée au démarrage.");
            } else {
              _selectedTranche = _tranches.first;
              debugPrint(
                  "Aucune tranche favorite valide. Chargement de la première : '$_selectedTranche'.");
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
          SnackBar(
              content: Text(
                  "Erreur de chargement de la configuration des tranches: $e")),
        );
      }
    }
  }

  void _triggerReSelectionAndNavigate() {
    // ... (Cette fonction reste inchangée)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        final bool? connexionReussie =
            await RoleSelectionScreen.triggerRoleReSelection(context);
        if (mounted && connexionReussie == true) {
          await _loadUserDataAndRoles();
        }
      }
    });
  }

  Stream<List<Consigne>> getConsignesStream() {
    // ... (Cette fonction reste inchangée)
    if (_selectedTranche == null) {
      return Stream.value([]);
    }
    return _consignesRefGlobal
        .where('tranche', isEqualTo: _selectedTranche)
        .orderBy('dateEmission', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) {
            try {
              return Consigne.fromJson(doc.data() as Map<String, dynamic>);
            } catch (e) {
              debugPrint("Erreur de parsing d'une consigne: $e");
              return null;
            }
          })
          .whereType<Consigne>()
          .toList();
    });
  }

  Future<void> _addConsigneDB(Consigne consigne) async {
    // ... (Cette fonction reste inchangée)
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
    // ... (Cette fonction reste inchangée)
    try {
      await _consignesRefGlobal.doc(id).delete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Erreur de suppression de la consigne: $e")));
      }
    }
  }

  // --- CORRECTION 1 : SIMPLIFICATION DE _updateConsigneDB ---
  Future<void> _updateConsigneDB(Consigne consigne) async {
    // La méthode toJson() dans votre modèle Consigne fait déjà tout le travail.
    // Cette fonction devient donc beaucoup plus simple.
    try {
      await _consignesRefGlobal.doc(consigne.id).update(consigne.toJson());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Erreur de mise à jour de la consigne: $e")));
      }
    }
  }

  // --- FIN DE LA CORRECTION ---

  void _presenterValidationConsigne(
      Consigne consigne, bool estValideeMaintenant) {
    if (estValideeMaintenant) {
      _presenterDialogObservationValidation(consigne);
    } else {
      // --- MODIFICATION ICI : On ajoute clearNomPrenomValidation ---
      Consigne consigneMiseAJour = consigne.copyWith(
        estValidee: false,
        clearDateValidation: true,
        clearCommentaireValidation: true,
        clearIdAuteurValidation: true,
        clearNomPrenomValidation: true,
        // <--- AJOUTEZ CETTE LIGNE
        clearDosimetrieInfo: true,
      );
      _updateConsigneDB(consigneMiseAJour);
    }
  }

  Future<void> _presenterDialogObservationValidation(
      Consigne consigneAValider) async {
    // Le pré-remplissage est maintenant correct car commentaireValidation
    // ne contient plus la dosimétrie.
    String initialComment = "";
    if (consigneAValider.idAuteurValidation == _currentUser?.uid &&
        consigneAValider.commentaireValidation != null) {
      initialComment = consigneAValider.commentaireValidation!;
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
                    'Veuillez saisir une observation pour la consigne : "${consigneAValider.contenu}"'),
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
              child: const Text('ANNULER'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _observationValidationDialogController.clear();
              },
            ),
            ElevatedButton(
              child: const Text('SUIVANT : DOSIMÉTRIE'),
              // ... à l'intérieur de ElevatedButton (SUIVANT : DOSIMÉTRIE)
              onPressed: () {
                final String observationTexte =
                    _observationValidationDialogController.text.trim();
                String commentaireAvecAuteur = "";
                if (observationTexte.isNotEmpty) {
                  commentaireAvecAuteur = "$observationTexte";
                }
                Navigator.of(dialogContext).pop();
                _observationValidationDialogController.clear();

                // --- MODIFICATION ICI : On passe les nouvelles infos au copyWith ---
                final consignePrete = consigneAValider.copyWith(
                  estValidee: true,
                  dateValidation: DateTime.now(),
                  idAuteurValidation: _currentUser!.uid,
                  nomPrenomValidation: _currentUserNomPrenom,
                  // <--- ON ENREGISTRE LE NOM ICI
                  commentaireValidation: commentaireAvecAuteur.isNotEmpty
                      ? commentaireAvecAuteur
                      : null,
                );

                _lancerDialogueDosimetrie(consignePrete, commentaireAvecAuteur);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _lancerDialogueDosimetrie(
      Consigne consigne, String commentaireInitial) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return DosimetrieDialog(
          consigneAValider: consigne,
          // 'consigne' contient déjà le nomPrenomValidation ici
          commentaireInitial: commentaireInitial,
          currentUserUid: _currentUser!.uid,
          onUpdateConsigne: (consigneMiseAJour) {
            _updateConsigneDB(
                consigneMiseAJour); // Enregistre tout dans Firebase
          },
        );
      },
    );
  }

  // ... Le reste du fichier (à partir de _presenterAjoutConsigneHandler) est déjà correct et n'a pas besoin d'être modifié.
  // Vous pouvez simplement copier les fonctions ci-dessus et remplacer les vôtres.
  // Pour être sûr, je vous remets la suite complète ci-dessous.

  Future<void> _presenterAjoutConsigneHandler() async {
    if (_selectedTranche == null || _selectedTranche!.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Veuillez d'abord sélectionner une tranche.")),
      );
      return;
    }
    final bool peutAjouter = (_userRoles.contains(roleAdminString) ||
            _userRoles.contains(roleChefDeChantierString)) &&
        _currentUser != null;
    if (!peutAjouter) {
      String message = "Action non autorisée pour ajouter une consigne.";
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    final texte = _consigneController.text.trim();
    if (texte.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Veuillez saisir le texte de la consigne.")));
      return;
    }
    String? categorieChoisie = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return SimpleDialog(
          title: const Text('Choisir une catégorie pour la consigne'),
          children: _categoriesConsignes.map((categorie) {
            return SimpleDialogOption(
              onPressed: () {
                Navigator.pop(dialogContext, categorie);
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 10.0, horizontal: 8.0),
                child: Text(categorie, style: const TextStyle(fontSize: 16)),
              ),
            );
          }).toList(),
        );
      },
    );
    if (!mounted || categorieChoisie == null) return;
    bool veutDefinirEnjeu = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext dialogContext) {
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
        ) ??
        false;
    if (!mounted) return;
    String? enjeuFinalPourConsigne;
    if (veutDefinirEnjeu) {
      final String? enjeuChoisiPopup = await showDialog<String>(
        context: context,
        builder: (BuildContext dialogContextEnjeu) {
          return SimpleDialog(
            title: const Text('Sélectionner un enjeu'),
            children: <Widget>[
              ...optionsEnjeux.map((String enjeu) {
                return SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialogContextEnjeu, enjeu),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(enjeu),
                  ),
                );
              }),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContextEnjeu, null),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text('Aucun enjeu / Annuler',
                      style: TextStyle(
                          fontStyle: FontStyle.italic, color: Colors.grey)),
                ),
              ),
            ],
          );
        },
      );
      if (!mounted) return;
      if (enjeuChoisiPopup != null) {
        enjeuFinalPourConsigne = enjeuChoisiPopup;
      }
    }
    final nouvelleConsigne = Consigne(
      id: _consignesRefGlobal.doc().id,
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
    await _addConsigneDB(nouvelleConsigne);
    if (!mounted) return;
  }

  Future<void> _enregistrerObservationNonRealisation(
      Consigne consigne, String texteNouvelleObservation) async {
    if (texteNouvelleObservation.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("L'observation ne peut pas être vide.")),
        );
      }
      return;
    }
    final nouveauCommentaire = Commentaire(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      texte: texteNouvelleObservation,
      date: DateTime.now(),
      auteurId: _currentUser!.uid,
      auteurNomPrenom: _currentUserNomPrenom,
      roleAuteur: _roleDisplay,
    );
    List<Commentaire> commentairesActuels =
        List<Commentaire>.from(consigne.commentairesNonRealisation ?? []);
    commentairesActuels.add(nouveauCommentaire);
    final consigneMiseAJour = consigne.copyWith(
        commentairesNonRealisation: commentairesActuels,
        estValidee: false,
        dateValidation: null,
        clearCommentaireValidation: true,
        idAuteurValidation: null,
        estNonRealiseeEffectivement: true,
        clearDosimetrieInfo: true // On efface aussi la dosimétrie
        );
    await _updateConsigneDB(consigneMiseAJour);
    _obsNonRealiseeControllers[consigne.id]?.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Observation de non-réalisation ajoutée.")),
      );
    }
  }

  Future<void> _enregistrerObservationValidation(
      Consigne consigne, String texteObservation) async {
    if (!consigne.estValidee ||
        consigne.idAuteurValidation != _currentUser?.uid) {
      if (mounted &&
          consigne.idAuteurValidation != _currentUser?.uid &&
          consigne.estValidee) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  "Vous ne pouvez modifier que vos propres observations de validation.")),
        );
      }
      return;
    }
    final String texteCommentaireActuelSeul =
        consigne.commentaireValidation?.split('\n-').first.trim() ?? "";
    if (texteObservation == texteCommentaireActuelSeul) return;
    String commentaireFinalAvecAuteur = "";
    if (texteObservation.isNotEmpty) {
      commentaireFinalAvecAuteur =
          "$texteObservation\n- $_currentUserNomPrenom ($_roleDisplay) le ${_formatDateSimple(DateTime.now(), showTime: true)}";
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
        SnackBar(
            content: Text(texteObservation.isNotEmpty
                ? "Observation de validation mise à jour."
                : "Observation de validation supprimée.")),
      );
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
      return snapshot.docs
          .map((doc) {
            try {
              return InfoChantier.fromJson(doc.data() as Map<String, dynamic>);
            } catch (e) {
              return null;
            }
          })
          .whereType<InfoChantier>()
          .toList();
    });
  }

  Future<void> _addInfoChantierDB(InfoChantier info) async {
    try {
      await _infosChantierRefGlobal.doc(info.id).set(info.toJson());
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Veuillez d'abord sélectionner une tranche.")),
        );
      }
      return;
    }
    final bool peutAjouterInfo = (_userRoles.contains(roleAdminString) ||
            _userRoles.contains(roleChefDeChantierString)) &&
        _currentUser != null;
    if (!peutAjouterInfo) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Action non autorisée.")));
      }
      return;
    }
    final texte = _infoController.text.trim();
    if (texte.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Veuillez saisir le texte de l'information.")));
      }
      return;
    }
    final nouvelleInfo = InfoChantier(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
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

  Future<void> _confirmerEtSupprimerInfo(
      BuildContext itemContext, String infoId, String infoContenu) async {
    if (!mounted) return;
    final bool? confirmer = await showDialog<bool>(
      context: context,
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
              child:
                  const Text('Supprimer', style: TextStyle(color: Colors.red)),
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

  void _presenterModificationInfo(
      BuildContext itemContext, InfoChantier infoAmodifier) {
    if (!mounted) return;
    final TextEditingController modificationController =
        TextEditingController(text: infoAmodifier.contenu);
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text("Modifier l'information"),
          content: TextField(
            controller: modificationController,
            decoration: const InputDecoration(
                hintText: "Nouveau texte de l'information"),
            maxLines: null,
          ),
          actions: [
            TextButton(
              onPressed: () {
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
                  final infoMiseAJour =
                      infoAmodifier.copyWith(contenu: nouveauContenu);
                  if (Navigator.canPop(dialogContext)) {
                    Navigator.of(dialogContext).pop();
                  }
                  await _updateInfoChantierDB(infoMiseAJour);
                } else if (nouveauContenu.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                        content: Text('Le contenu ne peut pas être vide.')),
                  );
                } else {
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        modificationController.dispose();
      });
    });
  }

  Future<void> _marquerInfoCommeLue(InfoChantier info) async {
    try {
      // Vérifier si l'utilisateur a déjà lu cette info
      final dejaLue = info.lectures.any((l) => l.userId == _currentUser?.uid);
      if (dejaLue) {
        return; // Déjà lue, rien à faire
      }

      // Ajouter une nouvelle lecture
      final nouvelleLecture = LectureInfo(
        userId: _currentUser!.uid,
        userNomPrenom: _currentUserNomPrenom,
        dateLecture: DateTime.now(),
      );

      final lecturesUpd = [...info.lectures, nouvelleLecture];
      final infoMiseAJour = info.copyWith(lectures: lecturesUpd);

      await _updateInfoChantierDB(infoMiseAJour);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Information marquée comme lue.")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur : $e")),
        );
      }
    }
  }

  void _presenterDialogueLectures(BuildContext context, InfoChantier info) {
    if (info.lectures.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Aucun lecteur pour cette info.")),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(
            "Lecteurs de l'information (${info.lectures.length})",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: ListBody(
              children: info.lectures.map((lecture) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lecture.userNomPrenom,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Lu le: ${_formatDateSimple(lecture.dateLecture)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text("Fermer"),
            )
          ],
        );
      },
    );
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

  Future<void> _checkVersionAndInitialize() async {
    // ... (Cette fonction reste inchangée)
    if (!mounted) return;
    setState(() {
      _loadingState = HomeScreenLoadingState.initializing;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedDeploymentId = prefs.getString('deployment_id');
      if (storedDeploymentId != DEPLOYMENT_ID) {
        debugPrint(
            "Nouvelle version détectée (actuelle: $DEPLOYMENT_ID, stockée: $storedDeploymentId). Déconnexion forcée.");
        await FirebaseAuth.instance.signOut();
        await prefs.clear();
        await prefs.setString('deployment_id', DEPLOYMENT_ID);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Déconnexion suite à une mise à jour de l\'application.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 4),
            ),
          );
        }
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
            (route) => false,
          );
        }
        return;
      }
      debugPrint(
          "Version de l'application à jour ($DEPLOYMENT_ID). Chargement normal.");
      await _loadUserDataAndRoles();
    } catch (e) {
      if (mounted) {
        setState(() => _loadingState = HomeScreenLoadingState.error);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur critique au démarrage : $e")),
        );
      }
    }
  }

  Widget _buildChampAjoutConsigne() {
    // ... (Cette fonction reste inchangée)
    final bool peutAfficherChampAjout = (_userRoles.contains(roleAdminString) ||
            _userRoles.contains(roleChefDeChantierString)) &&
        _currentUser != null;
    if (!peutAfficherChampAjout || _selectedTranche == null) {
      return const SizedBox.shrink();
    }
    final bool estEnModeModification = _consigneEnEdition != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 12.0),
      child: Material(
        elevation: 4.0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
            side: BorderSide(
                color: estEnModeModification
                    ? Colors.blue.shade300
                    : Colors.grey.shade300,
                width: 1.5)),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                estEnModeModification
                    ? "Modifier la consigne"
                    : "Ajouter une nouvelle consigne pour: $_selectedTranche",
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: estEnModeModification
                        ? Colors.blue.shade800
                        : Colors.blueGrey.shade700,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _consigneController,
                      focusNode: _ajoutConsigneFocusNode,
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
                    icon: Icon(
                        estEnModeModification
                            ? Icons.save_as_outlined
                            : Icons.add_task_outlined,
                        size: 20),
                    onPressed: _enregistrerOuModifierConsigne,
                    label:
                        Text(estEnModeModification ? "Enregistrer" : "Valider"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: estEnModeModification
                          ? Colors.blue.shade700
                          : Colors.orange.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  InkWell(
                    onTap: () {
                      setState(() {
                        _estPrioritaireNouvelleConsigne =
                            !_estPrioritaireNouvelleConsigne;
                      });
                    },
                    borderRadius: BorderRadius.circular(4.0),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        children: [
                          Checkbox(
                            value: _estPrioritaireNouvelleConsigne,
                            visualDensity: VisualDensity.compact,
                            onChanged: (val) => setState(() =>
                                _estPrioritaireNouvelleConsigne = val ?? false),
                          ),
                          const Text("Marquer comme prioritaire"),
                        ],
                      ),
                    ),
                  ),
                  if (estEnModeModification)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _consigneController.clear();
                          _estPrioritaireNouvelleConsigne = false;
                          _selectedEnjeuPourNouvelleConsigne = null;
                          _consigneEnEdition = null;
                          FocusScope.of(context).unfocus();
                        });
                      },
                      child: const Text("Annuler"),
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
    // ... (Cette fonction reste inchangée)
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
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Ajouter une nouvelle information",
                style: Theme.of(context)
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

  Widget _buildConsignesList(List<Consigne> consignes) {
    if (_selectedTranche == null) {
      return const Center(child: Text("Veuillez sélectionner une tranche."));
    }
    if (consignes.isEmpty) {
      return const Center(
        child: Text("Aucune consigne active pour cette tranche."),
      );
    }

    // Initialiser les contrôleurs pour TOUTES les consignes d'abord
    for (final c in consignes) {
      _obsNonRealiseeControllers.putIfAbsent(
        c.id,
        () => TextEditingController(),
      );
      _obsValidationControllers.putIfAbsent(
        c.id,
        () => TextEditingController(
          text: c.commentaireValidation?.split('\n-').first.trim() ?? "",
        ),
      );
    }

    final bool peutAgirSurConsigne = (_userRoles.contains(roleAdminString) ||
            _userRoles.contains(roleChefDeChantierString) ||
            _userRoles.contains(roleChefEquipeString) ||
            _userRoles.contains(roleIntervenantString)) &&
        _currentUser != null;

    final bool peutModifierConsigne = (_userRoles.contains(roleAdminString) ||
            _userRoles.contains(roleChefDeChantierString)) &&
        _currentUser != null;

    final bool peutSupprimerConsigneNonValidee =
        (_userRoles.contains(roleAdminString) ||
                _userRoles.contains(roleChefDeChantierString)) &&
            _currentUser != null;

    return RepaintBoundary(
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 120),
        itemCount: consignes.length,
        itemBuilder: (context, index) {
          final c = consignes[index];

          return ConsigneItemWidget(
            key: ValueKey(c.id),
            consigne: c,
            peutAgirSurConsigne: peutAgirSurConsigne,
            peutModifierConsigne: peutModifierConsigne,
            peutSupprimerConsigneNonValidee: peutSupprimerConsigneNonValidee,
            obsNonRealiseeController: _obsNonRealiseeControllers[c.id]!,
            obsValidationController: _obsValidationControllers[c.id]!,
            onValidation: _presenterValidationConsigne,
            onModification: _presenterModificationConsigne,
            onLocaliser: _analyserEtNaviguerVersRepere,
            onSuppression: _confirmerSuppressionConsigne,
            onEnregistrerObsNonRealisation:
                _enregistrerObservationNonRealisation,
            onEnregistrerObsValidation: _enregistrerObservationValidation,
            formatDate: _formatDateSimple,
          );
        },
      ),
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
        _buildBlocHeader("Consignes - $_selectedTranche",
            headerColor: Colors.green),
        Expanded(
          child: _ConsignesStreamBuilder(
            selectedTranche: _selectedTranche!,
            getConsignesStream: getConsignesStream,
            buildConsignesList: _buildConsignesList,
            cache: _consignesCache,
          ),
        ),
        _buildChampAjoutConsigne(),
      ],
    );
  }

  Widget _buildInfosBlocWidget() {
    // ... (Cette fonction reste la même)
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
            _userRoles.contains(roleChefDeChantierString)) &&
        _currentUser != null;
    final bool peutSupprimerInfo =
        _userRoles.contains(roleAdminString) && _currentUser != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBlocHeader("Informations - $_selectedTranche",
            headerColor: Colors.blue),
        Expanded(
          child: StreamBuilder<List<InfoChantier>>(
            stream: getInfosChantierStream(),
            builder: (context, snapshot) {
              // --- AJOUT ICI ---
              if (snapshot.hasData && snapshot.data != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _updateUnreadCount(snapshot.data!); // On passe snapshot.data
                });
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.blue)));
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
                  final bool estLue =
                      info.lectures.any((l) => l.userId == _currentUser?.uid);
                  final bool estAuteur =
                      info.auteurIdCreation == _currentUser?.uid;

                  return Card(
                    key: ValueKey(info.id),
                    margin:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    color: estLue ? Colors.blue.shade50 : Colors.cyan.shade50,
                    elevation: estLue ? 1 : 2,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12.0, 12.0, 4.0, 12.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Stack(
                            alignment: Alignment.topRight,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.only(right: 8.0, top: 2.0),
                                child: Icon(Icons.info_outline,
                                    color: estLue
                                        ? Colors.blue
                                        : Colors.cyan.shade700,
                                    size: 24),
                              ),
                              // Badge visible seulement si pas auteur, pas lue et si d'autres l'ont lue
                              if (!estAuteur &&
                                  !estLue &&
                                  info.lectures.isNotEmpty)
                                Positioned(
                                  top: -4,
                                  right: -4,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      info.lectures.length.toString(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  info.contenu,
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: estLue
                                          ? FontWeight.w500
                                          : FontWeight.w600,
                                      color: estLue
                                          ? Colors.black87
                                          : Colors.cyan.shade900),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Publié par: ${info.auteurNomPrenomCreation} (${info.roleAuteurCreation})',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade700),
                                ),
                                Text(
                                  'Le: ${_formatDateSimple(info.dateEmission)}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade700),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              // Bouton pour voir les lecteurs (pour l'auteur, chefs de chantier et admins)
                              if ((estAuteur || peutModifierInfo) &&
                                  info.lectures.isNotEmpty)
                                IconButton(
                                  icon: Icon(Icons.visibility_outlined,
                                      color: Colors.green.shade700, size: 22),
                                  tooltip:
                                      'Voir les lectures (${info.lectures.length})',
                                  padding: const EdgeInsets.all(4),
                                  constraints: const BoxConstraints(),
                                  onPressed: () {
                                    _presenterDialogueLectures(
                                        itemBuilderContext, info);
                                  },
                                ),
                              // Bouton pour marquer comme lue (seulement si pas auteur)
                              if (!estAuteur && !estLue)
                                IconButton(
                                  icon: Icon(Icons.done_all_outlined,
                                      color: Colors.blue.shade700, size: 22),
                                  tooltip: 'Marquer comme lue',
                                  padding: const EdgeInsets.all(4),
                                  constraints: const BoxConstraints(),
                                  onPressed: () {
                                    _marquerInfoCommeLue(info);
                                  },
                                ),
                              if (peutModifierInfo)
                                IconButton(
                                  icon: Icon(Icons.edit_note_outlined,
                                      color: Colors.orange.shade700, size: 22),
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
                                  icon: Icon(Icons.delete_forever_outlined,
                                      color: Colors.red.shade600, size: 22),
                                  tooltip: 'Supprimer',
                                  padding: const EdgeInsets.all(4),
                                  constraints: const BoxConstraints(),
                                  onPressed: () {
                                    _confirmerEtSupprimerInfo(
                                        itemBuilderContext,
                                        info.id,
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

  void _showTrancheSelector() async {
    if (!mounted) {
      return;
    }

    if (_tranches.isEmpty) {
      if (_userRoles.contains(roleAdminString)) {
        final goToConfig = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
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
          await Navigator.push(
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
      builder: (dialogContext) => SimpleDialog(
        title: const Text("Sélectionner une tranche"),
        children: _tranches
            .map((t) => SimpleDialogOption(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(t,
                        style: TextStyle(
                            fontWeight: t == _selectedTranche
                                ? FontWeight.bold
                                : FontWeight.normal)),
                  ),
                  onPressed: () => Navigator.pop(dialogContext, t),
                ))
            .toList(),
      ),
    );

    if (!mounted) return;

    if (nouvelleTranche != null && nouvelleTranche != _selectedTranche) {
      _safelySetState(() => _selectedTranche = nouvelleTranche);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ... (Toute la logique de build reste la même jusqu'à la fin)
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
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
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
      return Scaffold(
        appBar: AppBar(
          title: const Text("Gestion Chantier"),
          backgroundColor: Colors.grey.shade700,
          foregroundColor: Colors.white,
          leading: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('utilisateurs')
                .doc(widget.userId)
                .snapshots(),
            builder: (context, snapshot) {
              return const IconButton(
                icon: Icon(Icons.layers_outlined),
                tooltip: "Aucune tranche configurée",
                onPressed: null,
              );
            },
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.layers_clear_outlined,
                    size: 60, color: Colors.orange.shade300),
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
                          MaterialPageRoute(
                              builder: (context) =>
                                  const ManageTranchesScreen()),
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
      ArchiveScreen(
        selectedTranche: _selectedTranche,
        tranches: _tranches,
        userRoles: _userRoles,
        getConsignesStream: getConsignesStream,
        deleteConsigneDB: _deleteConsigneDB,
        obsNonRealiseeControllers: _obsNonRealiseeControllers,
        obsValidationControllers: _obsValidationControllers,
      ),
    ];

    List<BottomNavigationBarItem> navBarItems = [
      const BottomNavigationBarItem(
          icon: Icon(Icons.list_alt_outlined), label: 'Consignes'),
      BottomNavigationBarItem(
          icon: Badge(
            label: Text(_unreadInfosCount.toString()),
            isLabelVisible: _unreadInfosCount > 0, // On cache si 0
            child: const Icon(Icons.info_outline),
          ),
          label: 'Infos'),
      const BottomNavigationBarItem(
          icon: Icon(Icons.archive_outlined), label: 'Archives'),
    ];

    if (_userRoles.contains(roleAdminString)) {
      stackChildren.add(Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("Administration",
                  style: Theme.of(context)
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
                label: const Text("Gérer les Utilisateurs"),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const GererLesUtilisateursScreen(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: appBarColor,
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
              // Affiche un message différent en mode lecture seule
              if (_isReadOnly)
                const Text(
                  "Mode: Lecture Seule",
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
                )
              else
                Text(
                  "Mode: $_roleDisplay ($_currentUserNomPrenom)",
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.normal),
                ),
            ],
          ),
          backgroundColor: appBarColor,
          foregroundColor: Colors.white,
          leading: _isReadOnly
              ? IconButton(
                  icon: const Icon(Icons.layers_outlined),
                  tooltip: "Changer de tranche",
                  onPressed: _showTrancheSelector,
                )
              : TrancheSelector(
                  tranches: _tranches,
                  // On passe l'userId (qui n'est pas nul si on n'est pas en readOnly)
                  userId: widget.userId!,
                  favoriteTranche: _favoriteTranche,
                  onTrancheSelected: (nouvelleTranche) async {
                    if (nouvelleTranche != _selectedTranche) {
                      _safelySetState(() => _selectedTranche = nouvelleTranche);

                      // Optionnel : On peut aussi mettre à jour localement le favori
                      // si le widget TrancheSelector le modifie en base.
                      DocumentSnapshot userDoc = await _firestore
                          .collection('utilisateurs')
                          .doc(_currentUser!.uid)
                          .get();
                      if (userDoc.exists) {
                        _safelySetState(() {
                          _favoriteTranche = userDoc.get('favoriteTranche');
                        });
                      }
                    }
                  },
                  userRoles: _userRoles,
                ),
          actions: _isReadOnly
              ? [
                  // On remplace la liste vide par une liste contenant un bouton
                  IconButton(
                    icon: const Icon(Icons.login_outlined),
                    tooltip: "Se connecter / Quitter le mode lecture",
                    onPressed: () {
                      // Cette action ferme l'écran actuel et retourne au précédent (l'écran de connexion)
                      Navigator.of(context).pop();
                    },
                  ),
                ]
              : [
                  IconButton(
                    icon: const Icon(Icons.logout_outlined),
                    tooltip: "Déconnexion / Changer de rôle",
                    onPressed: _triggerReSelectionAndNavigate,
                  ),
                ]),
      body: SafeArea(
        child: IndexedStack(
          index: _currentIndex,
          children: stackChildren,
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) async {
          _safelySetState(() {
            _currentIndex = index;
          });

          // Plus de marquage automatique des infos comme lues
          // Le badge reste affiché jusqu'à ce que chaque info soit marquée comme lue individuellement
        },
        items: navBarItems,
        // ...
        selectedItemColor: appBarColor,
        unselectedItemColor: Colors.grey.shade600,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
      ),
    );
  }
}

class ConsigneItemWidget extends StatefulWidget {
  final Consigne consigne;
  final bool peutAgirSurConsigne;
  final bool peutModifierConsigne;
  final bool peutSupprimerConsigneNonValidee;
  final TextEditingController obsNonRealiseeController;
  final TextEditingController obsValidationController;
  final Function(Consigne, bool) onValidation;
  final Function(Consigne) onModification;
  final Function(String) onLocaliser;
  final Function(Consigne) onSuppression;
  final Function(Consigne, String) onEnregistrerObsNonRealisation;
  final Function(Consigne, String) onEnregistrerObsValidation;
  final String Function(DateTime) formatDate;

  const ConsigneItemWidget({
    Key? key,
    required this.consigne,
    required this.peutAgirSurConsigne,
    required this.peutModifierConsigne,
    required this.peutSupprimerConsigneNonValidee,
    required this.obsNonRealiseeController,
    required this.obsValidationController,
    required this.onValidation,
    required this.onModification,
    required this.onLocaliser,
    required this.onSuppression,
    required this.onEnregistrerObsNonRealisation,
    required this.onEnregistrerObsValidation,
    required this.formatDate,
  }) : super(key: key);

  @override
  State<ConsigneItemWidget> createState() => _ConsigneItemWidgetState();
}

class _ConsigneItemWidgetState extends State<ConsigneItemWidget>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = widget.consigne;
    final estPrioritaireActive = c.estPrioritaire && !c.estValidee;

    return Card(
      key: ValueKey(c.id),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: estPrioritaireActive
          ? Colors.red.shade50
          : (c.estValidee ? Colors.green.shade50 : Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color:
              estPrioritaireActive ? Colors.red.shade300 : Colors.grey.shade200,
        ),
      ),
      elevation: 1.0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // LIGNE PRINCIPALE
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Checkbox / statut
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: widget.peutAgirSurConsigne
                      ? Checkbox(
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          value: c.estValidee,
                          onChanged: (val) {
                            if (val != null) {
                              widget.onValidation(c, val);
                            }
                          },
                        )
                      : Icon(
                          c.estValidee
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: c.estValidee ? Colors.green : Colors.grey,
                          size: 20,
                        ),
                ),

                const SizedBox(width: 6),

                // TEXTE PRINCIPAL
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Titre + éventuel badge PRIORITAIRE sur la même ligne
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              c.contenu,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.2,
                                fontWeight: estPrioritaireActive
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: estPrioritaireActive
                                    ? Colors.red.shade800
                                    : (c.estValidee
                                        ? Colors.grey.shade700
                                        : Colors.black87),
                                decoration: c.estValidee
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                          if (estPrioritaireActive) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.shade100,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                "PRIORITAIRE",
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red.shade800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),

                      const SizedBox(height: 2),

                      // Ligne méta (auteur + date)
                      Text(
                        "Créée par ${c.auteurNomPrenomCreation} (${c.roleAuteurCreation}) le ${widget.formatDate(c.dateEmission)}",
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade600,
                          fontStyle: FontStyle.italic,
                        ),
                      ),

                      const SizedBox(height: 2),

                      // Ligne chips (catégorie + enjeu) sur une seule ligne quand possible
                      if ((c.categorie != null && c.categorie!.isNotEmpty) ||
                          (c.enjeu != null && c.enjeu!.isNotEmpty))
                        Wrap(
                          spacing: 3,
                          runSpacing: -2,
                          children: [
                            if (c.categorie != null && c.categorie!.isNotEmpty)
                              Chip(
                                label: Text(c.categorie!),
                                backgroundColor: Colors.blueGrey.shade50,
                                labelStyle: TextStyle(
                                  fontSize: 9,
                                  color: Colors.blueGrey.shade800,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 0,
                                ),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            if (c.enjeu != null && c.enjeu!.isNotEmpty)
                              Chip(
                                avatar: const Icon(
                                  Icons.shield_outlined,
                                  size: 12,
                                ),
                                label: Text(c.enjeu!),
                                backgroundColor: Colors.blue.shade50,
                                labelStyle: TextStyle(
                                  fontSize: 9,
                                  color: Colors.blue.shade900,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 0,
                                ),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                          ],
                        ),
                    ],
                  ),
                ),

                const SizedBox(width: 2),

                // ACTIONS
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.peutModifierConsigne && !c.estValidee)
                      IconButton(
                        icon: const Icon(
                          Icons.edit,
                          size: 18,
                          color: Colors.blue, // Couleur bleue
                        ),
                        tooltip: "Modifier",
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        onPressed: () => widget.onModification(c),
                      ),
                    if (widget.peutAgirSurConsigne && !c.estValidee)
                      IconButton(
                        icon: const Icon(
                          Icons.gps_fixed,
                          size: 18,
                          color: Color(0xFF92C022), // Couleur personnalisée
                        ),
                        tooltip: "Localiser",
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        onPressed: () => widget.onLocaliser(c.contenu),
                      ),
                    if (widget.peutSupprimerConsigneNonValidee && !c.estValidee)
                      IconButton(
                        icon: const Icon(
                          Icons.delete,
                          size: 18,
                          color: Colors.red, // Couleur rouge
                        ),
                        tooltip: "Supprimer",
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        onPressed: () => widget.onSuppression(c),
                      ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 6),

            // OBSERVATION NON REALISATION (champ visible)
            if (!c.estValidee && widget.peutAgirSurConsigne)
              _buildChampObservation(
                context: context,
                consigne: c,
                controller: widget.obsNonRealiseeController,
                label: "Observation (si non réalisée)",
                hint: "Raison de la non réalisation...",
                onSave: (texte) {
                  widget.onEnregistrerObsNonRealisation(c, texte);
                },
                backgroundColor: Colors.orange.shade50,
                iconColor: Colors.orange.shade800,
              ),

            // HISTORIQUE DES OBSERVATIONS NON REALISEES (déroulant)
            if (c.commentairesNonRealisation != null &&
                c.commentairesNonRealisation!.isNotEmpty)
              _buildChampObservationDeroulant(
                context: context,
                commentaires: c.commentairesNonRealisation!,
                label: "Observations précédentes",
                backgroundColor: Colors.orange.shade100,
                iconColor: Colors.orange.shade800,
              ),

            // OBSERVATION VALIDATION (champ visible)
            if (c.estValidee && widget.peutAgirSurConsigne)
              _buildChampObservation(
                context: context,
                consigne: c,
                controller: widget.obsValidationController,
                label: "Observation après validation",
                hint: "Ajouter un commentaire...",
                onSave: (texte) {
                  widget.onEnregistrerObsValidation(c, texte);
                },
                backgroundColor: Colors.green.shade50,
                iconColor: Colors.green.shade800,
              ),

            // DOSIMETRIE
            if (c.dosimetrieInfo != null && c.dosimetrieInfo!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    "Dosimétrie : ${c.dosimetrieInfo!}",
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.blue.shade900,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

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
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 3),
          TextField(
            controller: controller,
            maxLines: null,
            minLines: 1,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
              filled: true,
              fillColor: backgroundColor,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
                borderSide: BorderSide(
                    color: Theme.of(context).primaryColor, width: 1.4),
              ),
              suffixIconConstraints:
                  const BoxConstraints(minHeight: 32, minWidth: 32),
              suffixIcon: IconButton(
                icon: Icon(
                  Icons.save_alt_outlined,
                  color: iconColor,
                  size: 19,
                ),
                tooltip: "Enregistrer l'observation",
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  onSave(controller.text.trim());
                  FocusScope.of(context).unfocus();
                },
              ),
            ),
            onSubmitted: (text) {
              onSave(text.trim());
            },
          ),
        ],
      ),
    );
  }

  Widget _buildChampObservationDeroulant({
    required BuildContext context,
    required List<Commentaire> commentaires,
    required String label,
    Color backgroundColor = Colors.white,
    Color iconColor = Colors.grey,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: ExpansionTile(
        title: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: iconColor,
          ),
        ),
        children: commentaires.map((comment) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comment.texte,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "Par ${comment.auteurNomPrenom} le ${comment.date.toString().split(' ')[0]}",
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ConsignesStreamBuilder extends StatefulWidget {
  final String selectedTranche;
  final Stream<List<Consigne>> Function() getConsignesStream;
  final Widget Function(List<Consigne>) buildConsignesList;
  final _ConsignesCache cache;

  const _ConsignesStreamBuilder({
    required this.selectedTranche,
    required this.getConsignesStream,
    required this.buildConsignesList,
    required this.cache,
  });

  @override
  State<_ConsignesStreamBuilder> createState() =>
      _ConsignesStreamBuilderState();
}

class _ConsignesStreamBuilderState extends State<_ConsignesStreamBuilder> {
  late Stream<List<Consigne>> _filteredStream;

  @override
  void initState() {
    super.initState();
    // Créer un stream qui filtre les listes identiques
    _filteredStream = widget.getConsignesStream().where((newList) {
      return widget.cache.hasChanged(newList);
    });
  }

  @override
  void didUpdateWidget(_ConsignesStreamBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTranche != widget.selectedTranche) {
      widget.cache.clear();
      _filteredStream = widget.getConsignesStream().where((newList) {
        return widget.cache.hasChanged(newList);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Consigne>>(
      stream: _filteredStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Erreur: ${snapshot.error}'));
        }
        final toutesLesConsignes = snapshot.data ?? [];
        final consignesActives = toutesLesConsignes
            .where((consigne) => !consigne.estValidee)
            .toList();
        if (consignesActives.isEmpty) {
          return const Center(
            child: Text("Aucune consigne active pour cette tranche."),
          );
        }
        return widget.buildConsignesList(consignesActives);
      },
    );
  }
}
