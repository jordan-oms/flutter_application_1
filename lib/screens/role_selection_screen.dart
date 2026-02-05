// lib/screens/role_selection_screen.dart
import 'package:flutter/material.dart'; // Fournit debugPrint et Key
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'
    as fs; // Alias pour cohérence

import 'home_screen.dart';
import 'login_chantier_screen.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen(
      {super.key}); // super.key est déjà utilisé, c'est bien

  static Future<void> triggerRoleReSelection(
      BuildContext externalContext) async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e, s) {
      // Remplacé print par debugPrint
      debugPrint(
          "[RoleSelectionScreen] triggerRoleReSelection: ERREUR pendant la déconnexion: $e\nStackTrace: $s");
    }

    if (!externalContext.mounted) {
      // Remplacé print par debugPrint
      debugPrint(
          "[RoleSelectionScreen] triggerRoleReSelection: Contexte externe non monté. Navigation annulée.");
      return;
    }
    Navigator.pushAndRemoveUntil(
      externalContext,
      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
      (Route<dynamic> route) => false,
    );
  }

  @override
  // Modifié pour retourner le type d'état public
  RoleSelectionScreenState createState() => RoleSelectionScreenState();
}

// Classe d'état renommée en RoleSelectionScreenState (publique)
class RoleSelectionScreenState extends State<RoleSelectionScreen> {
  bool _isLoading = true;
  bool _isProcessingLogin = false;

  final List<String> _postesDeTravail = [
    "Poste du matin",
    "Poste d'après-midi",
    "Poste de nuit",
    "HN",
  ];

  final List<int> _numerosEquipe = [1, 2, 3, 4];

  @override
  void initState() {
    super.initState();
    _checkUserAndNavigateBasedOnFirestoreRoles();
  }

  Future<List<String>> _getUserRolesFromFirestore(String uid) async {
    try {
      fs.DocumentSnapshot userDoc = await fs.FirebaseFirestore.instance
          .collection('utilisateurs')
          .doc(uid)
          .get();

      if (userDoc.exists && userDoc.data() != null) {
        var data = userDoc.data() as Map<String, dynamic>;
        if (data.containsKey('roles') && data['roles'] is List) {
          List<String> roles =
              List<String>.from(data['roles'].map((role) => role.toString()));
          return roles;
        }
      }
    } catch (e, s) {
      // Remplacé print par debugPrint
      debugPrint(
          "[RoleSelectionScreen] _getUserRolesFromFirestore: ERREUR lors de la récupération des rôles pour $uid: $e\nStackTrace: $s");
    }
    // Remplacé print par debugPrint
    debugPrint(
        "[RoleSelectionScreen] _getUserRolesFromFirestore: Retour d'une liste de rôles vide pour UID: $uid (suite à une erreur ou données manquantes).");
    return [];
  }

  Future<void> _checkUserAndNavigateBasedOnFirestoreRoles() async {
    if (!mounted) {
      setState(() {
        _isLoading = false;
      });
      return;
    }
    setState(() {
      _isLoading = true;
    });

    User? currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser != null) {
      // Remplacé print par debugPrint
      debugPrint(
          "[RoleSelectionScreen] _checkUserAndNavigateBasedOnFirestoreRoles: Utilisateur Firebase connecté. UID: ${currentUser.uid}");
      List<String> roles = await _getUserRolesFromFirestore(currentUser.uid);

      if (!mounted) return;

      bool dataValidePourChefEquipe = true;
      if (roles.contains('chef_equipe')) {
        fs.DocumentSnapshot userDocData = await fs.FirebaseFirestore.instance
            .collection('utilisateurs')
            .doc(currentUser.uid)
            .get();
        if (!mounted) return;

        if (userDocData.exists && userDocData.data() != null) {
          var data = userDocData.data() as Map<String, dynamic>;
          if (!data.containsKey('numeroEquipe') ||
              data['numeroEquipe'] == null ||
              !data.containsKey('poste_actuel') ||
              data['poste_actuel'] == null) {
            dataValidePourChefEquipe = false;
          }
        } else {
          dataValidePourChefEquipe = false;
        }
      }

      if (roles.isNotEmpty && dataValidePourChefEquipe) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (Route<dynamic> route) => false,
        );
        return;
      } else {
        String causeAffichageOptions = roles.isEmpty
            ? "rôles Firestore vides"
            : "données chef d'équipe (numeroEquipe/poste_actuel) invalides";
        // Remplacé print par debugPrint
        debugPrint(
            "[RoleSelectionScreen] _checkUserAndNavigateBasedOnFirestoreRoles: Utilisateur Firebase connecté (UID: ${currentUser.uid}) mais $causeAffichageOptions. Affichage options.");
      }
    } else {
      // Remplacé print par debugPrint
      debugPrint(
          "[RoleSelectionScreen] _checkUserAndNavigateBasedOnFirestoreRoles: Pas d'utilisateur Firebase connecté. Affichage options.");
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
    // Remplacé print par debugPrint
    debugPrint(
        "[RoleSelectionScreen] _checkUserAndNavigateBasedOnFirestoreRoles: FIN - Affichage des options. _isLoading: $_isLoading");
  }

  Future<String?> _showPosteSelectionDialog() async {
    if (!mounted) return null;
    return await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Choisir un poste'),
          content: SingleChildScrollView(
            child: ListBody(
              children: _postesDeTravail.map((poste) {
                return ListTile(
                  title: Text(poste),
                  onTap: () {
                    Navigator.of(dialogContext).pop(poste);
                  },
                );
              }).toList(),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('ANNULER'),
              onPressed: () {
                Navigator.of(dialogContext).pop(null);
              },
            ),
          ],
        );
      },
    );
  }

  Future<int?> _showEquipeSelectionDialog() async {
    if (!mounted) {
      // Remplacé print par debugPrint
      debugPrint(
          "[RoleSelectionScreen] _showEquipeSelectionDialog: Non monté, retour null.");
      return null;
    }
    // Remplacé print par debugPrint
    debugPrint(
        "[RoleSelectionScreen] _showEquipeSelectionDialog: Début fonction, affichage dialogue.");

    return await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        // Remplacé print par debugPrint
        debugPrint(
            "[RoleSelectionScreen] _showEquipeSelectionDialog: Builder du dialogue appelé.");
        return AlertDialog(
          title: const Text('Choisir une Équipe'),
          content: SingleChildScrollView(
            child: ListBody(
              children: _numerosEquipe.map((numero) {
                return ListTile(
                  title: Text('Équipe $numero'),
                  onTap: () {
                    // Remplacé print par debugPrint
                    debugPrint(
                        "[RoleSelectionScreen] _showEquipeSelectionDialog: Équipe $numero choisie.");
                    Navigator.of(dialogContext).pop(numero);
                  },
                );
              }).toList(),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('ANNULER'),
              onPressed: () {
                // Remplacé print par debugPrint
                debugPrint(
                    "[RoleSelectionScreen] _showEquipeSelectionDialog: Annuler cliqué.");
                Navigator.of(dialogContext).pop(null);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleLoginAttemptForRoleType(String roleType) async {
    if (_isProcessingLogin) return;
    // Remplacé print par debugPrint
    debugPrint(
        "[RoleSelectionScreen] _handleLoginAttemptForRoleType: Tentative de connexion pour type: $roleType");
    if (!mounted) return;

    setState(() {
      _isProcessingLogin = true;
    });

    String? selectedPoste;
    int? selectedTeamNumber;

    try {
      User? user;

      if (roleType == "chef_equipe") {
        // Remplacé print par debugPrint
        debugPrint(
            "[RoleSelectionScreen] _handleLoginAttemptForRoleType: AVANT APPEL _showPosteSelectionDialog");
        selectedPoste = await _showPosteSelectionDialog();
        // Remplacé print par debugPrint
        debugPrint(
            "[RoleSelectionScreen] _handleLoginAttemptForRoleType: APRES APPEL _showPosteSelectionDialog. selectedPoste: $selectedPoste");

        if (selectedPoste == null) {
          // Remplacé print par debugPrint
          debugPrint(
              "[RoleSelectionScreen] _handleLoginAttemptForRoleType: Poste annulé.");
          if (mounted) {
            setState(() {
              _isProcessingLogin = false;
            });
          }
          return;
        }
        // Remplacé print par debugPrint
        debugPrint(
            "[RoleSelectionScreen] _handleLoginAttemptForRoleType: Poste sélectionné pour chef d'équipe: $selectedPoste");

        // Remplacé print par debugPrint
        debugPrint(
            "[RoleSelectionScreen] _handleLoginAttemptForRoleType: AVANT APPEL _showEquipeSelectionDialog...");
        selectedTeamNumber = await _showEquipeSelectionDialog();
        // Remplacé print par debugPrint
        debugPrint(
            "[RoleSelectionScreen] _handleLoginAttemptForRoleType: APRES APPEL _showEquipeSelectionDialog. selectedTeamNumber: $selectedTeamNumber");

        if (selectedTeamNumber == null) {
          // Remplacé print par debugPrint
          debugPrint(
              "[RoleSelectionScreen] _handleLoginAttemptForRoleType: Équipe annulée.");
          if (mounted) {
            setState(() {
              _isProcessingLogin = false;
            });
          }
          return;
        }
        // Remplacé print par debugPrint
        debugPrint(
            "[RoleSelectionScreen] _handleLoginAttemptForRoleType: Numéro d'équipe sélectionné: $selectedTeamNumber");

        User? currentAuthUser = FirebaseAuth.instance.currentUser;
        if (currentAuthUser != null && !currentAuthUser.isAnonymous) {
          await FirebaseAuth.instance.signOut();
          currentAuthUser = null;
        }

        if (currentAuthUser == null || !currentAuthUser.isAnonymous) {
          user = (await FirebaseAuth.instance.signInAnonymously()).user;
        } else {
          user = currentAuthUser;
        }
        // Remplacé print par debugPrint
        debugPrint(
            "[RoleSelectionScreen] _handleLoginAttemptForRoleType: Connexion anonyme réussie/utilisée. UID: ${user?.uid}");

        if (user != null) {
          fs.DocumentReference userDocRef = fs.FirebaseFirestore.instance
              .collection('utilisateurs')
              .doc(user.uid);
          String nomCompletEquipePoste =
              "Équipe $selectedTeamNumber - $selectedPoste";
          Map<String, dynamic> userDataToSet = {
            'uid': user.uid,
            'email': null,
            'nom': nomCompletEquipePoste,
            'prenom': '',
            'createdAt': fs.FieldValue.serverTimestamp(),
            'roles': ['chef_equipe'],
            'poste_actuel': selectedPoste,
            'numeroEquipe': selectedTeamNumber,
            'derniere_selection_poste_equipe': fs.FieldValue.serverTimestamp(),
          };
          await userDocRef.set(userDataToSet, fs.SetOptions(merge: true));
          // Remplacé print par debugPrint
          debugPrint(
              "[RoleSelectionScreen] _handleLoginAttemptForRoleType: Document pour chef d'équipe ($nomCompletEquipePoste) traité. UID: ${user.uid}. Navigation.");
          if (mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const HomeScreen()),
              (Route<dynamic> route) => false,
            );
          }
          return;
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Erreur de connexion anonyme.")));
            setState(() {
              _isProcessingLogin = false;
            });
          }
          return;
        }
      } else if (roleType == "chef_de_chantier" ||
          roleType == "administrateur") {
        // Remplacé print par debugPrint
        debugPrint(
            "[RoleSelectionScreen] _handleLoginAttemptForRoleType: Navigation vers LoginChantierScreen pour $roleType...");
        bool? loginSuccess = await Navigator.push<bool?>(
          context,
          MaterialPageRoute(
              builder: (_) => LoginChantierScreen(onSuccess: () {})),
        );
        // Remplacé print par debugPrint
        debugPrint(
            "[RoleSelectionScreen] _handleLoginAttemptForRoleType: Retour de LoginChantierScreen. loginSuccess: $loginSuccess pour $roleType.");
        if (loginSuccess == true) {
          if (mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const HomeScreen()),
              (Route<dynamic> route) => false,
            );
          }
          return;
        } else {
          if (mounted) {
            setState(() {
              _isProcessingLogin = false;
            });
          }
          return;
        }
      }

      if (mounted) {
        setState(() {
          _isProcessingLogin = false;
        });
      }
    } catch (e, s) {
      // Ajout de la StackTrace s
      // Remplacé print par debugPrint
      debugPrint(
          "[RoleSelectionScreen] ERREUR pendant _handleLoginAttemptForRoleType($roleType): $e\nStackTrace: $s");
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Erreur: ${e.toString()}")));
        setState(() {
          _isProcessingLogin = false;
        });
      }
    }
  }

  Widget _buildRoleButton(BuildContext context,
      {required String text,
      required Color color,
      Color textColor = Colors.white,
      required String roleKey}) {
    final double buttonWidth = MediaQuery.of(context).size.width * 0.40;
    const double buttonHeight = 35.0;

    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: textColor,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 3,
        fixedSize: Size(buttonWidth, buttonHeight),
      ),
      onPressed: _isProcessingLogin
          ? null
          : () {
              _handleLoginAttemptForRoleType(roleKey);
            },
      child: Text(text),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Remplacé print par debugPrint
    debugPrint(
        "[RoleSelectionScreen] build: APPELÉ. _isLoading=$_isLoading, _isProcessingLogin=$_isProcessingLogin");

    if (_isLoading) {
      // Remplacé print par debugPrint
      debugPrint(
          "[RoleSelectionScreen] build: Affichage du CircularProgressIndicator initial (_isLoading=true).");
      return const Scaffold(
        backgroundColor: Color(0xFFD6F5D6),
        body: Center(child: CircularProgressIndicator(color: Colors.green)),
      );
    }

    const Color backgroundColor = Color(0xFFD6F5D6);
    const Color buttonChefColor = Color(0xFF90C22E);
    const Color buttonAdminColor = Color(0xFFE53935);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 30.0, vertical: 20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Image.asset(
                      'assets/images/oms-logo.png',
                      height: 200,
                      errorBuilder: (context, error, stackTrace) {
                        return const Text(
                          'OMS Énergie',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87),
                        );
                      },
                    ),
                    const SizedBox(height: 50),
                    if (_isProcessingLogin)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20.0),
                        child: Column(
                          children: [
                            CircularProgressIndicator(color: Colors.green),
                            SizedBox(height: 20),
                            Text("Traitement en cours...",
                                style: TextStyle(
                                    fontSize: 16, color: Colors.black54)),
                          ],
                        ),
                      )
                    else
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildRoleButton(context,
                              text: 'Chef d\'équipe',
                              color: buttonChefColor,
                              roleKey: 'chef_equipe'),
                          const SizedBox(height: 15),
                          _buildRoleButton(context,
                              text: 'Chef de chantier',
                              color: buttonChefColor,
                              roleKey: 'chef_de_chantier'),
                          const SizedBox(height: 15),
                          _buildRoleButton(context,
                              text: 'Administrateur',
                              color: buttonAdminColor,
                              roleKey: 'administrateur'),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 12.0,
              bottom: 12.0,
              child: Text(
                "V.BETA 2.0",
                // Vous pouvez envisager de rendre cela dynamique avec package_info_plus
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 12.0,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
