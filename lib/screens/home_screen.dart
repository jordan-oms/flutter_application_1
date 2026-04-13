// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:ui';
import 'dart:async';

// Importez vos modèles
import '../model/consigne.dart';
import '../model/info_chantier.dart';
import '../model/commentaire.dart';
import '../model/transfert.dart';

// Importez vos autres écrans
import './role_selection_screen.dart';
import './admin/manage_tranches_screen.dart';
import 'archive_screen.dart';
import 'dosimetrie_dialog.dart';
import 'gerer_les_utilisateur.dart';
import './chantier_plus_screen.dart';
import './transfert_screen.dart';

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
  final String? userId;
  final String? initialTranche;
  final bool isReadOnly;
  final String interfaceType; // 'consignes' ou 'amcr'

  const HomeScreen({
    super.key,
    this.userId,
    this.initialTranche,
    this.isReadOnly = false,
    this.interfaceType = 'consignes', // Par défaut 'consignes'
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
  DateTime? _derniereDateInfo; // Pour suivre les modifications
  int _unvalidatedTransfertsCount = 0;
  final Set<String> _dismissedTransfertAlerts = {};
  final Set<String> _currentlyShowingAlerts = {};
  late ValueNotifier<int> _unreadCountNotifier;

  // Variables pour le popup récurrent des Infos
  Timer? _infosPopupTimer;
  DateTime? _lastInfosPopupTime;
  String? _lastUnreadInfoId;
  bool _isInfosPopupShowing = false;

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

  late CollectionReference _consignesRefGlobal;
  late CollectionReference _transfertsRefGlobal;
  final Map<String, TextEditingController> _obsNonRealiseeControllers = {};
  final Map<String, TextEditingController> _obsValidationControllers = {};
  final Map<String, TextEditingController>
      _obsNonRealiseeControllersTransferts = {};
  final Map<String, TextEditingController> _obsValidationControllersTransferts =
      {};

  StreamSubscription<List<Transfert>>? _transfertsBadgeSubscription;
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
  late CollectionReference _infosChantierRefGlobal;
  final DocumentReference _tranchesConfigRef = FirebaseFirestore.instance
      .collection('app_config')
      .doc('tranches_config');
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // On ajoute un raccourci pour savoir si on est en mode lecture seule
  bool get _isReadOnly => widget.isReadOnly;
  String get _interfaceType => widget.interfaceType;

  bool _hasConsignes = false;
  bool _hasAMCR = false;
  bool _hasCAPILog = false;

  @override
  void initState() {
    super.initState();
    _unreadCountNotifier = ValueNotifier<int>(0);

    // Initialisation dynamique des collections selon l'interface
    final String prefix = _interfaceType == 'amcr' ? 'amcr_' : '';
    _consignesRefGlobal =
        FirebaseFirestore.instance.collection('${prefix}consignes');
    _transfertsRefGlobal =
        FirebaseFirestore.instance.collection('${prefix}transferts');
    _infosChantierRefGlobal =
        FirebaseFirestore.instance.collection('${prefix}infos_chantier');

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

    // Timer pour le popup récurrent des infos (toutes les minutes pour vérifier si on doit l'afficher)
    _infosPopupTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      final bool isClient = _userRoles.contains('client_amcr') ||
          _userRoles.contains('client_alog') ||
          _userRoles.contains('client');
      if (!isClient) {
        _checkAndShowInfosPopup();
      }
    });
  }

  void _checkAndShowInfosPopup() {
    final bool isClient = _userRoles.contains('client_amcr') ||
        _userRoles.contains('client_alog') ||
        _userRoles.contains('client');
    if (isClient) return; // Pas de popup pour les clients

    if (_currentIndex == 2) return; // Déjà sur l'onglet Infos
    if (_unreadInfosCount == 0) return; // Pas d'infos non lues
    if (_isInfosPopupShowing) return; // Déjà affiché

    final now = DateTime.now();
    if (_lastInfosPopupTime == null ||
        now.difference(_lastInfosPopupTime!).inMinutes >= 15) {
      _showInfosPriorityPopup();
    }
  }

  void _showInfosPriorityPopup() {
    if (!mounted) return;
    setState(() {
      _isInfosPopupShowing = true;
      _lastInfosPopupTime = DateTime.now();
    });

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: "Nouvelle Info",
      barrierColor: Colors.black.withOpacity(0.5),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: AlertDialog(
            title: Row(
              children: [
                Icon(Icons.info, color: Colors.blue.shade700, size: 28),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    "Nouvelle Information",
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: Text(
              "Vous avez $_unreadInfosCount information${_unreadInfosCount > 1 ? 's' : ''} non lue${_unreadInfosCount > 1 ? 's' : ''}. Veuillez en prendre connaissance sur l'onglet Infos.",
              style: const TextStyle(fontSize: 16),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  setState(() {
                    // Calcul de l'index de l'onglet Infos
                    final bool isClient = _userRoles.contains('client_amcr') ||
                        _userRoles.contains('client');
                    bool isAmcrMode = _interfaceType == 'amcr' || isClient;
                    _currentIndex = isAmcrMode ? 1 : 2;
                    _isInfosPopupShowing = false;
                  });
                  Navigator.of(context).pop();
                },
                child: const Text("COMPRIS (VOIR L'INFO)"),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _infosPopupTimer?.cancel();
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
    final bool isClient = _userRoles.contains('client_amcr') ||
        _userRoles.contains('client_alog') ||
        _userRoles.contains('client');

    if (isClient) {
      if (mounted && _unreadInfosCount != 0) {
        setState(() {
          _unreadInfosCount = 0;
        });
      }
      return;
    }

    int count = 0;
    DateTime? plusRecenteDate;

    for (final info in infos) {
      final bool estLueParUtilisateur =
          info.lectures.any((lecture) => lecture.userId == _currentUser?.uid);
      final bool estAuteur = info.auteurIdCreation == _currentUser?.uid;

      // On ne compte l'info que si elle n'est pas lue ET qu'on n'est pas l'auteur
      if (!estLueParUtilisateur && !estAuteur) {
        count++;
        // On cherche la date de l'info non lue la plus récente
        if (plusRecenteDate == null ||
            info.dateEmission.isAfter(plusRecenteDate)) {
          plusRecenteDate = info.dateEmission;
        }
      }
    }

    if (mounted) {
      // Calculer dynamiquement l'index de l'onglet Infos pour savoir s'il faut afficher le popup
      // En mode AMCR, c'est l'index 1, sinon c'est l'index 2
      final int infosTabIndex = (_interfaceType == 'amcr') ? 1 : 2;

      final bool nouvelleModifDetectee = plusRecenteDate != null &&
          (_derniereDateInfo == null ||
              plusRecenteDate.isAfter(_derniereDateInfo!));

      if (_unreadInfosCount != count || nouvelleModifDetectee) {
        setState(() {
          _unreadInfosCount = count;
          _derniereDateInfo = plusRecenteDate;
        });

        // Déclencher le popup si on n'est pas déjà sur l'onglet Infos
        if (count > 0 &&
            nouvelleModifDetectee &&
            _currentIndex != infosTabIndex) {
          _showInfosPriorityPopup();
        }
      }
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
          // --- VÉRIFICATION DE SÉCURITÉ CAPILog ---
          final userDoc = await FirebaseFirestore.instance
              .collection('utilisateurs')
              .doc(_currentUser?.uid)
              .get();

          if (userDoc.exists) {
            final data = userDoc.data()!;
            final roles = List<String>.from(data['roles'] ?? []);
            final bool isAdmin = roles.contains('administrateur');
            final bool hasCAPILog = data['isCAPILog'] == true;

            if (!isAdmin && !hasCAPILog) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        "Accès refusé : L'administrateur ne vous a pas autorisé l'accès CAPILog."),
                    backgroundColor: Colors.red,
                  ),
                );
              }
              return;
            }
          }
          // ---------------------------------------

          // Si le repère existe et que l'utilisateur a les droits, on ouvre ses détails
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
  Future<void> _allerVersChantierPlus() async {
    // Vérification de la permission CAPILog
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('utilisateurs')
          .doc(_currentUser?.uid)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data()!;
        final roles = List<String>.from(data['roles'] ?? []);
        final bool isAdmin = roles.contains('administrateur');
        final bool hasCAPILog = data['isCAPILog'] == true;

        if (!isAdmin && !hasCAPILog) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    "Accès refusé : L'administrateur ne vous a pas autorisé l'accès CAPILog."),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }
    } catch (e) {
      debugPrint("Erreur lors de la vérification CAPILog: $e");
    }

    if (!mounted) return;
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

        // Récupération des permissions granulaires
        final bool isAdmin = _userRoles.contains(roleAdminString);
        _hasConsignes = isAdmin || data['isConsignes'] == true;
        _hasAMCR = isAdmin || data['isAMCR'] == true;
        _hasCAPILog = isAdmin || data['isCAPILog'] == true;

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

      // --- NOUVELLE LOGIQUE POUR DÉTERMINER L'INTERFACE ---
      if (_userRoles.contains(roleAdminString)) {
        _roleDisplay = "Administrateur";
      } else if (_userRoles.contains(roleChefDeChantierString) ||
          _userRoles.contains('chef_de_chantier_amcr')) {
        _roleDisplay = "Chef de chantier";
      } else if (_userRoles.contains(roleChefEquipeString) ||
          _userRoles.contains('referent_amcr')) {
        _roleDisplay = "Référent / Chef d'équipe";
      } else if (_userRoles.contains(roleIntervenantString) ||
          _userRoles.contains('intervenant_amcr')) {
        _roleDisplay = "Intervenant";
      } else if (_userRoles.contains('client_amcr') ||
          _userRoles.contains('client_alog')) {
        _roleDisplay = "Client (Lecture seule)";
      } else {
        _roleDisplay = "Rôle Indéfini";
      }

      // Si l'utilisateur est passé par la sélection initiale d'interface,
      // il ne faut pas forcer le switch à chaque _loadUserDataAndRoles,
      // car widget.interfaceType est censé avoir la priorité.
      // Cependant, si on vient du démarrage et que widget.interfaceType est 'consignes' (par défaut),
      // on peut faire un switch vers 'amcr' si l'utilisateur n'a QUE des rôles AMCR.

      final bool onlyAMCR =
          _userRoles.isNotEmpty && _userRoles.every((r) => r.contains('amcr'));
      if (onlyAMCR &&
          widget.interfaceType == 'consignes' &&
          _interfaceType != 'amcr') {
        // Dans ce cas, on pourrait soit forcer le changement d'état (si mutable)
        // soit accepter que la navigation initiale a bien fait son boulot.
        // Pour l'instant on garde la sélection de la navigation initiale.
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

  Stream<List<Transfert>> getTransfertsStream() {
    if (_selectedTranche == null) {
      return Stream.value([]);
    }
    // Mise à jour de la requête pour inclure les transferts partagés (portefeuille)
    return _transfertsRefGlobal
        .where(Filter.or(
          Filter('tranche', isEqualTo: _selectedTranche),
          Filter('tranchesVisibles', arrayContains: _selectedTranche),
        ))
        .orderBy('dateEmission', descending: true)
        .snapshots()
        .map((snapshot) {
      final transferts = snapshot.docs
          .map((doc) {
            try {
              return Transfert.fromJson(doc.data() as Map<String, dynamic>);
            } catch (e) {
              debugPrint("Erreur de parsing d'un transfert: $e");
              return null;
            }
          })
          .whereType<Transfert>()
          .toList();

      // Logique pour le badge et les alertes : on passe toujours par la mise à jour
      _updateTransfertsStatus(transferts);

      return transferts;
    });
  }

  void _setupTransfertsBadgeListener() {
    _transfertsBadgeSubscription?.cancel();
    if (_selectedTranche == null) return;

    _transfertsBadgeSubscription = _transfertsRefGlobal
        .where(Filter.or(
          Filter('tranche', isEqualTo: _selectedTranche),
          Filter('tranchesVisibles', arrayContains: _selectedTranche),
        ))
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) {
            try {
              return Transfert.fromJson(doc.data() as Map<String, dynamic>);
            } catch (e) {
              return null;
            }
          })
          .whereType<Transfert>()
          .toList();
    }).listen((transferts) {
      _updateTransfertsStatus(transferts);
    });
  }

  void _updateTransfertsStatus(List<Transfert> transferts) {
    int unvalidatedCount = 0;
    final now = DateTime.now();
    final myTranche = _selectedTranche?.trim();

    for (var t in transferts) {
      // LE BADGE ET L'ALERTE S'AFFICHENT SI :
      final String myTrancheNorm = myTranche ?? "";
      final bool estOrigine = (t.tranche?.trim() ?? "") == myTrancheNorm;
      final bool estDansPortefeuille =
          t.tranchesVisibles?.any((e) => e.trim() == myTrancheNorm) ?? false;

      if ((estOrigine || estDansPortefeuille) && !t.estValidee) {
        unvalidatedCount++;

        // Alerte pour toutes les tranches concernées (Origine + Portefeuille)
        if (t.heureDepart != null) {
          final difference = t.heureDepart!.difference(now);
          final alertKey = "${t.id}_$_selectedTranche";

          if (difference.inMinutes <= 60 &&
              difference.inMinutes > -15 &&
              !_dismissedTransfertAlerts.contains(alertKey) &&
              !_currentlyShowingAlerts.contains(alertKey)) {
            _currentlyShowingAlerts.add(alertKey);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _showTransfertAlert(t, alertKey);
            });
          }
        }
      }
    }

    // Mise à jour du badge
    if (_unvalidatedTransfertsCount != unvalidatedCount) {
      _safelySetState(() {
        _unvalidatedTransfertsCount = unvalidatedCount;
      });
    }
  }

  void _showTransfertAlert(Transfert t, String alertKey) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: "Alerte Transfert",
      barrierColor: Colors.black.withOpacity(0.3),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, anim1, anim2) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Transfert imminent",
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Attention, vous avez un transfert de prévu :"),
                const SizedBox(height: 12),
                Text(
                  t.contenu,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.access_time_filled,
                          size: 18, color: Colors.blue.shade800),
                      const SizedBox(width: 8),
                      Text(
                        "PLANIFIÉ : ${t.heureDepart != null ? DateFormat('HH:mm').format(t.heureDepart!) : '--:--'}",
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.blue.shade900,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  if (mounted) {
                    setState(() {
                      _dismissedTransfertAlerts.add(alertKey);
                      _currentlyShowingAlerts.remove(alertKey);
                    });
                  }
                  Navigator.of(context).pop();
                },
                child: const Text("COMPRIS"),
              ),
            ],
          ),
        );
      },
    );
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

  Future<void> _deleteTransfertDB(String id) async {
    // Nouvelle fonction pour supprimer un transfert par ID
    try {
      await _transfertsRefGlobal.doc(id).delete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erreur de suppression du transfert: $e")));
      }
    }
  }

  // --- CORRECTION 1 : SIMPLIFICATION DE _updateConsigneDB ---
  Future<void> _updateConsigneDB(Consigne consigne) async {
    // La méthode toJson() dans votre modèle Consigne fait déjà tout le travail.
    // Cette fonction devient donc beaucoup plus simple.
    try {
      await _consignesRefGlobal.doc(consigne.id).set(consigne.toJson());
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

    // Restriction lecture seule pour les clients
    final bool isClient = _userRoles.contains('client_amcr') ||
        _userRoles.contains('client_alog');
    if (isClient) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Action non autorisée en mode Client.")),
      );
      return;
    }

    final bool peutAjouter = (_userRoles.contains(roleAdminString) ||
            _userRoles.contains(roleChefDeChantierString) ||
            _userRoles.contains('chef_de_chantier_amcr')) &&
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

  /// Getter dynamique pour obtenir la bonne collection d'informations selon l'interface
  CollectionReference get _infosCollection {
    // Si l'utilisateur est un chef AMCR, on le dirige PRIORITAIREMENT vers amcr_infos_chantier
    if (_userRoles.contains('chef_de_chantier_amcr')) {
      return FirebaseFirestore.instance.collection('amcr_infos_chantier');
    }

    // Sinon, on suit l'interface sélectionnée
    final String prefix = _interfaceType == 'amcr' ? 'amcr_' : '';
    return FirebaseFirestore.instance.collection('${prefix}infos_chantier');
  }

  Stream<List<InfoChantier>> getInfosChantierStream() {
    if (_selectedTranche == null) {
      return Stream.value([]);
    }
    return _infosCollection
        .where('tranche', isEqualTo: _selectedTranche)
        .orderBy('dateEmission', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) {
            try {
              final data = doc.data() as Map<String, dynamic>;
              // On s'assure que l'ID n'est JAMAIS vide en prenant l'ID du document
              // si le champ interne est manquant ou vide
              if (data['id'] == null || data['id'].toString().isEmpty) {
                data['id'] = doc.id;
              }
              return InfoChantier.fromJson(data);
            } catch (e) {
              debugPrint("Erreur parsing InfoChantier: $e");
              return null;
            }
          })
          .whereType<InfoChantier>()
          .toList();
    });
  }

  Future<void> _addInfoChantierDB(InfoChantier info) async {
    try {
      // On utilise l'ID déjà présent dans l'objet info
      if (info.id.isEmpty) {
        throw Exception("L'ID de l'information ne peut pas être vide.");
      }

      await _infosCollection.doc(info.id).set(info.toJson());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Information ajoutée avec succès.")),
        );
      }
    } catch (e) {
      debugPrint("Erreur Firestore (Add Info): $e");
      if (mounted) {
        // Message plus explicite pour l'utilisateur
        String errorMsg =
            "Erreur de permission: Vérifiez que votre rôle 'chef_de_chantier' est bien configuré.";
        if (e.toString().contains('permission-denied')) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(errorMsg), duration: const Duration(seconds: 5)));
        } else {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text("Erreur: $e")));
        }
      }
    }
  }

  Future<void> _deleteInfoChantierDB(String infoId) async {
    try {
      await _infosCollection.doc(infoId).delete();
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
      final DateTime maintenant = DateTime.now();

      // IMPORTANT: On n'envoie que les champs modifiables pour éviter de
      // déclencher des restrictions sur les champs 'auteurId' ou 'roleAuteur'
      // si les règles Firestore sont très strictes sur le diff().
      await _infosCollection.doc(info.id).update({
        'contenu': info.contenu,
        'dateEmission': Timestamp.fromDate(maintenant),
        'lectures': [],
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text("Information mise à jour et notifications renvoyées.")),
        );
      }
    } catch (e) {
      debugPrint("Erreur Firestore (Update Info): $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Erreur de modification (Vérifiez vos droits): $e")));
      }
    }
  }

  /// Méthode dédiée uniquement à la mise à jour des lectures pour respecter les règles Firestore
  Future<void> _updateInfoLecturesOnly(InfoChantier info) async {
    if (info.id.isEmpty) {
      debugPrint(
          "Erreur: Tentative de mise à jour d'une info avec un ID vide.");
      return;
    }
    try {
      await _infosCollection.doc(info.id).update({
        'lectures': info.lectures.map((l) => l.toJson()).toList(),
      });
    } catch (e) {
      debugPrint("Erreur lors de la mise à jour des lectures: $e");
      rethrow;
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

    final bool isClient = _userRoles.contains('client_amcr') ||
        _userRoles.contains('client_alog');
    if (isClient) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Action non autorisée en mode Client.")),
      );
      return;
    }

    final bool peutAjouterInfo = (_userRoles.contains(roleAdminString) ||
            _userRoles.contains(roleChefDeChantierString) ||
            _userRoles.contains('chef_de_chantier_amcr')) &&
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
    // On génère un ID Firestore à l'avance
    final String nouvelId = _infosCollection.doc().id;

    final nouvelleInfo = InfoChantier(
      id: nouvelId,
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
                if (nouveauContenu.isNotEmpty) {
                  // On crée l'objet mis à jour
                  final infoMiseAJour =
                      infoAmodifier.copyWith(contenu: nouveauContenu);

                  if (Navigator.canPop(dialogContext)) {
                    Navigator.of(dialogContext).pop();
                  }

                  // On appelle la mise à jour qui va forcer la nouvelle date
                  await _updateInfoChantierDB(infoMiseAJour);
                } else {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                        content: Text('Le contenu ne peut pas être vide.')),
                  );
                }
              },
              child: const Text("Enregistrer"),
            ),
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

      // On utilise une méthode dédiée pour ne mettre à jour que les lectures
      // afin d'éviter les erreurs de permissions Firestore sur les autres champs
      await _updateInfoLecturesOnly(infoMiseAJour);

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
    final bool isClient = _userRoles.contains('client_amcr') ||
        _userRoles.contains('client_alog');
    if (isClient) return const SizedBox.shrink();

    final bool peutAfficherChampAjout = (_userRoles.contains(roleAdminString) ||
            _userRoles.contains(roleChefDeChantierString) ||
            _userRoles.contains('chef_de_chantier_amcr')) &&
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
    final bool isClient = _userRoles.contains('client_amcr') ||
        _userRoles.contains('client_alog');
    if (isClient) return const SizedBox.shrink();

    final bool peutAfficherChampAjoutInfo =
        (_userRoles.contains(roleAdminString) ||
                _userRoles.contains(roleChefDeChantierString) ||
                _userRoles.contains('chef_de_chantier_amcr')) &&
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

    final bool isClient = _userRoles.contains('client_amcr') ||
        _userRoles.contains('client_alog');

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

    final bool peutAgirSurConsigne = !isClient &&
        (_userRoles.contains(roleAdminString) ||
            _userRoles.contains(roleChefDeChantierString) ||
            _userRoles.contains(roleChefEquipeString) ||
            _userRoles.contains(roleIntervenantString) ||
            _userRoles.contains('chef_de_chantier_amcr') ||
            _userRoles.contains('referent_amcr') ||
            _userRoles.contains('intervenant_amcr')) &&
        _currentUser != null;

    final bool peutModifierConsigne = !isClient &&
        (_userRoles.contains(roleAdminString) ||
            _userRoles.contains(roleChefDeChantierString) ||
            _userRoles.contains('chef_de_chantier_amcr')) &&
        _currentUser != null;

    final bool peutSupprimerConsigneNonValidee = !isClient &&
        (_userRoles.contains(roleAdminString) ||
            _userRoles.contains(roleChefDeChantierString) ||
            _userRoles.contains('chef_de_chantier_amcr')) &&
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
            interfaceType: widget.interfaceType,
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
    final bool isClient = _userRoles.contains('client_amcr') ||
        _userRoles.contains('client_alog');

    final bool peutModifierInfo = !isClient &&
        (_userRoles.contains(roleAdminString) ||
            _userRoles.contains(roleChefDeChantierString) ||
            _userRoles.contains('chef_de_chantier_amcr')) &&
        _currentUser != null;
    final bool peutSupprimerInfo =
        _userRoles.contains(roleAdminString) && _currentUser != null;

    final bool peutVoirLectures = _userRoles.contains(roleAdminString) ||
        _userRoles.contains(roleChefDeChantierString) ||
        _userRoles.contains('chef_de_chantier_amcr');

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
                  final bool estNouvelleInfo = !estLue && !estAuteur;

                  return BlinkingInfoCard(
                    key: ValueKey(info.id),
                    info: info,
                    estLue: estLue,
                    estAuteur: estAuteur,
                    estNouvelleInfo: estNouvelleInfo,
                    peutModifierInfo: estAuteur, // Seul l'auteur peut modifier
                    peutSupprimerInfo: peutSupprimerInfo,
                    peutVoirLectures: peutVoirLectures,
                    onMarquerLue: () => _marquerInfoCommeLue(info),
                    onVoirLectures: () =>
                        _presenterDialogueLectures(itemBuilderContext, info),
                    onModifier: () =>
                        _presenterModificationInfo(itemBuilderContext, info),
                    onSupprimer: () => _confirmerEtSupprimerInfo(
                        itemBuilderContext, info.id, info.contenu),
                    formatDate: _formatDateSimple,
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
      // ... (code existant)
    }

    final bool isClient = _userRoles.contains('client_amcr') ||
        _userRoles.contains('client_alog');
    final bool hasAMCR = _userRoles.any((r) => r.contains('amcr')) ||
        _userRoles.contains(roleAdminString);
    final bool hasConsignes = _userRoles.any((r) =>
            r == 'chef_de_chantier' ||
            r == 'chef_equipe' ||
            r == 'intervenant' ||
            r == 'client_alog') ||
        _userRoles.contains(roleAdminString);

    if (_selectedTranche == null &&
        _tranches.isEmpty &&
        _loadingState == HomeScreenLoadingState.ready) {
      // ... (code existant)
    }

    Color appBarColor = _interfaceType == 'amcr'
        ? Colors.blueGrey.shade800
        : Colors.green.shade700;
    if (_userRoles.contains(roleAdminString)) {
      appBarColor = Colors.redAccent.shade700;
    }

    List<Widget> stackChildren = [
      _buildConsignesBlocWidget(),
    ];

    if (_interfaceType != 'amcr' && !isClient) {
      stackChildren.add(TransfertScreen(
        selectedTranche: _selectedTranche ?? '',
        allTranches: _tranches,
        userRoles: _userRoles,
        currentUserNomPrenom: _currentUserNomPrenom,
        roleDisplay: _roleDisplay,
        interfaceType: _interfaceType,
      ));
    }

    if (!isClient) {
      stackChildren.add(_buildInfosBlocWidget());
    }

    stackChildren.add(ArchiveScreen(
      selectedTranche: _selectedTranche,
      tranches: _tranches,
      userRoles: _userRoles,
      getConsignesStream: getConsignesStream,
      deleteConsigneDB: _deleteConsigneDB,
      obsNonRealiseeControllers: _obsNonRealiseeControllers,
      obsValidationControllers: _obsValidationControllers,
      getTransfertsStream: getTransfertsStream,
      deleteTransfertDB: _deleteTransfertDB,
      obsNonRealiseeControllersTransferts: _obsNonRealiseeControllersTransferts,
      obsValidationControllersTransferts: _obsValidationControllersTransferts,
      interfaceType: _interfaceType,
      currentUserUid: _currentUser?.uid,
      currentUserNomPrenom: _currentUserNomPrenom,
      roleDisplay: _roleDisplay,
      addConsigneDB: _addConsigneDB,
    ));

    List<BottomNavigationBarItem> navBarItems = [
      const BottomNavigationBarItem(
          icon: Icon(Icons.list_alt_outlined), label: 'Consignes'),
    ];

    if (_interfaceType != 'amcr' && !isClient) {
      navBarItems.add(BottomNavigationBarItem(
        icon: Badge(
          label: Text(_unvalidatedTransfertsCount.toString()),
          isLabelVisible: _unvalidatedTransfertsCount > 0,
          child: const Icon(Icons.transfer_within_a_station_outlined),
        ),
        label: 'Transferts',
      ));
    }

    if (!isClient) {
      navBarItems.add(BottomNavigationBarItem(
          icon: Badge(
            label: Text(_unreadInfosCount.toString()),
            isLabelVisible: _unreadInfosCount > 0,
            child: const Icon(Icons.info_outline),
          ),
          label: 'Infos'));
    }

    navBarItems.add(const BottomNavigationBarItem(
        icon: Icon(Icons.archive_outlined), label: 'Archives'));

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

    // On compte combien d'interfaces l'utilisateur peut accéder
    int interfacesCount = 0;
    if (_hasConsignes) interfacesCount++;
    if (_hasAMCR) interfacesCount++;
    if (_hasCAPILog) interfacesCount++;

    final bool showSwitcher = interfacesCount > 1;

    if (_currentIndex >= stackChildren.length) {
      _currentIndex = 0;
    }
    return Scaffold(
      appBar: AppBar(
          title: InkWell(
            onTap: showSwitcher
                ? () {
                    // Menu pour basculer d'interface si multi-rôles
                    showModalBottomSheet(
                      context: context,
                      builder: (context) => SafeArea(
                        child: Wrap(
                          children: [
                            if (_hasConsignes)
                              ListTile(
                                leading: Image.asset('assets/images/icon1.png',
                                    height: 24,
                                    errorBuilder: (c, e, s) => const Icon(
                                        Icons.assignment_outlined,
                                        color: Colors.green)),
                                title: const Text("Interface Consignes"),
                                subtitle: _interfaceType == 'consignes'
                                    ? const Text("Interface actuelle")
                                    : null,
                                onTap: () {
                                  Navigator.pop(context);
                                  if (_interfaceType != 'consignes') {
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => HomeScreen(
                                          userId: widget.userId,
                                          initialTranche: _selectedTranche,
                                          interfaceType: 'consignes',
                                        ),
                                      ),
                                    );
                                  }
                                },
                              ),
                            if (_hasAMCR)
                              ListTile(
                                leading: Image.asset('assets/images/AMCR.png',
                                    height: 24,
                                    errorBuilder: (c, e, s) => const Icon(
                                        Icons.engineering_outlined,
                                        color: Colors.blueGrey)),
                                title: const Text("Interface AMCR"),
                                subtitle: _interfaceType == 'amcr'
                                    ? const Text("Interface actuelle")
                                    : null,
                                onTap: () {
                                  Navigator.pop(context);
                                  if (_interfaceType != 'amcr') {
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => HomeScreen(
                                          userId: widget.userId,
                                          initialTranche: _selectedTranche,
                                          interfaceType: 'amcr',
                                        ),
                                      ),
                                    );
                                  }
                                },
                              ),
                            if (_hasCAPILog)
                              ListTile(
                                leading: Image.asset(
                                    'assets/images/CAPILog.png',
                                    height: 24,
                                    errorBuilder: (c, e, s) => const Icon(
                                        Icons.business,
                                        color: Colors.blue)),
                                title: const Text("Interface CAPILog"),
                                onTap: () {
                                  Navigator.pop(context);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const ChantierPlusScreen(),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    );
                  }
                : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "${_interfaceType.toUpperCase()} - Tranche: ${_selectedTranche ?? 'Sélectionner...'}",
                        style: const TextStyle(fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      if (_isReadOnly || isClient)
                        const Text(
                          "Mode: Lecture Seule (Client)",
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.normal),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        )
                      else
                        Text(
                          "Mode: $_roleDisplay ($_currentUserNomPrenom)",
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.normal),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                    ],
                  ),
                ),
                if (showSwitcher)
                  const Icon(Icons.arrow_drop_down, color: Colors.white70),
              ],
            ),
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
                      // CRUCIAL : On remet le badge à zéro immédiatement
                      // pour éviter l'effet "fantôme" pendant le chargement
                      _safelySetState(() {
                        _selectedTranche = nouvelleTranche;
                        _unvalidatedTransfertsCount = 0;
                      });
                      _setupTransfertsBadgeListener();

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
  final String interfaceType;
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
    required this.interfaceType,
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
                    if (widget.peutAgirSurConsigne &&
                        !c.estValidee &&
                        widget.interfaceType != 'amcr')
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
                    "Par ${comment.auteurNomPrenom} le ${DateFormat('dd/MM/yyyy HH:mm').format(comment.date)}",
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

  bool _hasConsignes = false;
  bool _hasAMCR = false;
  bool _hasCAPILog = false;

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

class BlinkingInfoCard extends StatefulWidget {
  final InfoChantier info;
  final bool estLue;
  final bool estAuteur;
  final bool estNouvelleInfo;
  final bool peutModifierInfo;
  final bool peutSupprimerInfo;
  final bool peutVoirLectures;
  final VoidCallback onMarquerLue;
  final VoidCallback onVoirLectures;
  final VoidCallback onModifier;
  final VoidCallback onSupprimer;
  final String Function(DateTime) formatDate;

  const BlinkingInfoCard({
    super.key,
    required this.info,
    required this.estLue,
    required this.estAuteur,
    required this.estNouvelleInfo,
    required this.peutModifierInfo,
    required this.peutSupprimerInfo,
    required this.peutVoirLectures,
    required this.onMarquerLue,
    required this.onVoirLectures,
    required this.onModifier,
    required this.onSupprimer,
    required this.formatDate,
  });

  @override
  State<BlinkingInfoCard> createState() => _BlinkingInfoCardState();
}

class _BlinkingInfoCardState extends State<BlinkingInfoCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _animation = Tween<double>(begin: 1.0, end: 0.4).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    if (widget.estNouvelleInfo) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(BlinkingInfoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.estNouvelleInfo && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.estNouvelleInfo && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;

    return FadeTransition(
      opacity: widget.estNouvelleInfo
          ? _animation
          : const AlwaysStoppedAnimation(1.0),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        elevation: widget.estNouvelleInfo ? 4 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: widget.estNouvelleInfo
                ? Colors.blue.shade700
                : Colors.grey.shade200,
            width: widget.estNouvelleInfo ? 2 : 1,
          ),
        ),
        color: widget.estNouvelleInfo ? Colors.blue.shade50 : Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          widget.estNouvelleInfo
                              ? Icons.notification_important
                              : Icons.info_outline,
                          color:
                              widget.estNouvelleInfo ? Colors.red : Colors.blue,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.formatDate(info.dateEmission),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.peutModifierInfo || widget.peutSupprimerInfo)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.peutModifierInfo)
                          IconButton(
                            icon: const Icon(Icons.edit,
                                size: 18, color: Colors.blue),
                            onPressed: widget.onModifier,
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(4),
                          ),
                        if (widget.peutSupprimerInfo)
                          IconButton(
                            icon: const Icon(Icons.delete,
                                size: 18, color: Colors.red),
                            onPressed: widget.onSupprimer,
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(4),
                          ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                info.contenu,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: widget.estNouvelleInfo
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Par: ${info.auteurNomPrenomCreation} (${info.roleAuteurCreation})",
                style:
                    const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (widget.peutVoirLectures)
                    TextButton.icon(
                      onPressed: widget.onVoirLectures,
                      icon: const Icon(Icons.people_outline, size: 16),
                      label: Text(
                        "Lectures (${info.lectures.length})",
                        style: const TextStyle(fontSize: 12),
                      ),
                    )
                  else
                    const SizedBox.shrink(),
                  if (widget.estNouvelleInfo)
                    ElevatedButton.icon(
                      onPressed: widget.onMarquerLue,
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text("MARQUER COMME LU",
                          style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                    )
                  else if (!widget.estAuteur)
                    const Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 16),
                        const SizedBox(width: 4),
                        Text("Lu",
                            style: TextStyle(
                                color: Colors.green,
                                fontSize: 12,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
