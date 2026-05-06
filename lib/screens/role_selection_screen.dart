// lib/screens/role_selection_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart'; // Pour accéder à la constante DEPLOYMENT_ID
import 'home_screen.dart';
import 'login_chantier_screen.dart';
import 'chantier_plus_screen.dart';
import 'localog_screen.dart';

// ... (Le début du fichier reste identique)
Future<void> _saveDeploymentId() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('deployment_id', DEPLOYMENT_ID);
  } catch (e) {
    debugPrint("Erreur lors de la sauvegarde de l'ID de déploiement : $e");
  }
}

class RoleSelectionScreen extends StatefulWidget {
  final bool isSwitching;
  const RoleSelectionScreen({super.key, this.isSwitching = false});

  static Future<bool?> triggerRoleReSelection(
      BuildContext externalContext) async {
    // On ne se déconnecte plus ici pour permettre le changement d'interface
    // Si on veut vraiment se déconnecter, on créera un autre bouton.
    if (!externalContext.mounted) return null;

    return await Navigator.pushAndRemoveUntil<bool?>(
      externalContext,
      MaterialPageRoute(
          builder: (_) => const RoleSelectionScreen(isSwitching: true)),
      (Route<dynamic> route) => false,
    );
  }

  // Méthode pour se déconnecter réellement
  static Future<void> forceSignOut(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
        (route) => false,
      );
    }
  }

  @override
  RoleSelectionScreenState createState() => RoleSelectionScreenState();
}

class RoleSelectionScreenState extends State<RoleSelectionScreen> {
  bool _isLoading = true;
  bool _isProcessingLogin = false;

  @override
  void initState() {
    super.initState();
    if (widget.isSwitching) {
      setState(() => _isLoading = false);
    } else {
      _checkUserAndNavigate();
    }
  }

  Future<void> _checkUserAndNavigate() async {
    setState(() => _isLoading = true);
    User? currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser != null) {
      final userDoc = await fs.FirebaseFirestore.instance
          .collection('utilisateurs')
          .doc(currentUser.uid)
          .get();
      if (!mounted) return;

      if (userDoc.exists) {
        final data = userDoc.data()!;
        final roles = List<String>.from(data['roles'] ?? []);
        final bool isAdmin = roles.contains('administrateur');
        final bool isAMCRAuthorized = data['isAMCR'] == true;
        final bool isConsignesAuthorized = data['isConsignes'] == true;
        final bool isLocaLogAuthorized = data['isLocaLog'] == true;

        // Déterminer l'interface par défaut et naviguer
        if (isConsignesAuthorized || isAdmin) {
          Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (_) => HomeScreen(
                  userId: currentUser.uid,
                  initialTranche: data['favoriteTranche'],
                  interfaceType: 'consignes',
                ),
              ),
              (Route<dynamic> route) => false);
          return;
        }

        if (isAMCRAuthorized) {
          Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (_) => HomeScreen(
                  userId: currentUser.uid,
                  initialTranche: data['favoriteTranche'],
                  interfaceType: 'amcr',
                ),
              ),
              (Route<dynamic> route) => false);
          return;
        }

        if (isLocaLogAuthorized) {
          Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (_) => LocalogScreen(userId: currentUser.uid),
              ),
              (Route<dynamic> route) => false);
          return;
        }

        // Si aucune autorisation spécifique, on tente HomeScreen par défaut (qui gèrera le refus)
        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) => HomeScreen(
                userId: currentUser.uid,
                initialTranche: data['favoriteTranche'],
                interfaceType: 'consignes',
              ),
            ),
            (Route<dynamic> route) => false);
        return;
      } else {
        await FirebaseAuth.instance.signOut();
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _startLoginProcess({String interfaceType = 'consignes'}) async {
    if (_isProcessingLogin) return;
    setState(() => _isProcessingLogin = true);

    try {
      User? currentUser = FirebaseAuth.instance.currentUser;
      bool loginSuccess = false;

      if (currentUser != null) {
        // Déjà connecté, on passe direct à la vérification des droits
        loginSuccess = true;
      } else {
        // Pas connecté, on demande l'auth
        bool? result = await Navigator.push<bool?>(
          context,
          MaterialPageRoute(
              builder: (_) => LoginChantierScreen(onSuccess: () {})),
        );
        loginSuccess = result == true;
        currentUser = FirebaseAuth.instance.currentUser;
      }

      if (loginSuccess && currentUser != null) {
        final userDoc = await fs.FirebaseFirestore.instance
            .collection('utilisateurs')
            .doc(currentUser.uid)
            .get();
        if (!mounted) return;

        final data = userDoc.data();
        final roles = List<String>.from(data?['roles'] ?? []);
        final bool isAdmin = roles.contains('administrateur');
        final bool isAMCRAuthorized = data?['isAMCR'] == true;
        final bool isConsignesAuthorized = data?['isConsignes'] == true;

        // --- VÉRIFICATION STRICTE DES DROITS ---
        if (interfaceType == 'consignes' &&
            !isConsignesAuthorized &&
            !isAdmin) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    "Accès refusé : L'administrateur ne vous a pas autorisé l'accès aux Consignes."),
                backgroundColor: Colors.red,
              ),
            );
            setState(() => _isProcessingLogin = false);
          }
          return;
        }

        if (interfaceType == 'amcr' && !isAMCRAuthorized && !isAdmin) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    "Accès refusé : L'administrateur ne vous a pas autorisé l'accès AMCR."),
                backgroundColor: Colors.red,
              ),
            );
            setState(() => _isProcessingLogin = false);
          }
          return;
        }

        // LocaLog est accessible à tous les utilisateurs authentifiés

        if (interfaceType == 'localog') {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) => LocalogScreen(userId: currentUser!.uid),
            ),
            (Route<dynamic> route) => false,
          );
        } else {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) => HomeScreen(
                userId: currentUser!.uid,
                initialTranche: data?['favoriteTranche'],
                interfaceType: interfaceType,
              ),
            ),
            (Route<dynamic> route) => false,
          );
        }
      } else {
        if (mounted) {
          setState(() => _isProcessingLogin = false);
        }
      }
    } catch (e, s) {
      debugPrint("ERREUR pendant _startLoginProcess: $e\n$s");
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Erreur: ${e.toString()}")));
        setState(() => _isProcessingLogin = false);
      }
    }
  }

  // --- 2. LA FONCTION POUR LE BOUTON CHANTIER+ N'EST PLUS NÉCESSAIRE ---
  // On la supprime car la navigation se fait directement dans le `onTap`.

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFD6F5D6),
        body: Center(child: CircularProgressIndicator(color: Colors.green)),
      );
    }

    const Color backgroundColor = Color(0xFFD6F5D6);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Image.asset(
                    'assets/images/oms-logo.png',
                    height: 200,
                    errorBuilder: (context, error, stackTrace) {
                      return const Text('OMS Énergie',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87));
                    },
                  ),
                  // ... (reste du code inchangé jusqu'au Row)

                  if (_isProcessingLogin)
                    const CircularProgressIndicator(color: Colors.green)
                  else
                    // On utilise une Column pour empiler le Row (Capi/Consignes) et le nouveau logo
                    Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // --- LOGO GAUCHE (CAPILog) ---
                            GestureDetector(
                              onTap: () async {
                                bool? loginSuccess =
                                    await Navigator.push<bool?>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        LoginChantierScreen(onSuccess: () {}),
                                  ),
                                );

                                if (loginSuccess == true) {
                                  if (!mounted) return;

                                  // VÉRIFICATION STRICTE POUR CAPILog
                                  final currentUser =
                                      FirebaseAuth.instance.currentUser;
                                  if (currentUser != null) {
                                    final userDoc = await fs
                                        .FirebaseFirestore.instance
                                        .collection('utilisateurs')
                                        .doc(currentUser.uid)
                                        .get();

                                    if (userDoc.exists) {
                                      final data = userDoc.data()!;
                                      final roles = List<String>.from(
                                          data['roles'] ?? []);
                                      final bool isAdmin =
                                          roles.contains('administrateur');
                                      final bool hasCAPILog =
                                          data['isCAPILog'] == true;

                                      if (!isAdmin && !hasCAPILog) {
                                        if (mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
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
                                  }

                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const ChantierPlusScreen(),
                                    ),
                                  );
                                }
                              },
                              child: Tooltip(
                                message:
                                    'Authentification requise pour CAPILog',
                                child: Image.asset(
                                  'assets/images/CAPILog.png',
                                  height: 100,
                                  // Ajusté légèrement pour l'équilibre
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(Icons.add_business_outlined,
                                          size: 100),
                                ),
                              ),
                            ),

                            const SizedBox(width: 40),

                            // --- LOGO DROITE (Consignes) ---
                            GestureDetector(
                              onTap: () => _startLoginProcess(
                                  interfaceType: 'consignes'),
                              child: Tooltip(
                                message:
                                    'Authentification requise pour Consignes',
                                child: Image.asset(
                                  'assets/images/icon1.png',
                                  height: 100,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(Icons.login, size: 100),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 30),
                        // Espace entre les deux lignes de logos

                        // --- LOGOS AMCR ET LOCALOG CÔTE À CÔTE ---
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // --- LOGO AMCR ---
                            GestureDetector(
                              onTap: () =>
                                  _startLoginProcess(interfaceType: 'amcr'),
                              child: Tooltip(
                                message: 'Accès interface AMCR',
                                child: Image.asset(
                                  'assets/images/AMCR.png',
                                  height: 110,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Icon(
                                      Icons.engineering,
                                      size: 110,
                                      color: Colors.blueGrey,
                                    );
                                  },
                                ),
                              ),
                            ),

                            const SizedBox(width: 40),

                            // --- LOGO LOCALOG ---
                            GestureDetector(
                              onTap: () =>
                                  _startLoginProcess(interfaceType: 'localog'),
                              child: Tooltip(
                                message: 'Accès interface LocaLog',
                                child: Image.asset(
                                  'assets/images/LocaLog.png',
                                  height: 110,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Icon(
                                      Icons.location_on,
                                      size: 110,
                                      color: Colors.blueGrey,
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                ],
              ),
            ),
            Positioned(
              left: 12.0,
              bottom: 12.0,
              child: Text(
                "V.${DEPLOYMENT_ID.replaceAll('v', '')}",
                style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 12.0,
                    fontWeight: FontWeight.normal),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
