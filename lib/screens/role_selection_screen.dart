// lib/screens/role_selection_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart'; // Pour accéder à la constante DEPLOYMENT_ID
import 'home_screen.dart';
import 'login_chantier_screen.dart';
import 'chantier_plus_screen.dart'; // <-- 1. IMPORTER LE NOUVEL ÉCRAN

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
  const RoleSelectionScreen({super.key});

  static Future<bool?> triggerRoleReSelection(
      BuildContext externalContext) async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e, s) {
      debugPrint("Erreur pendant la déconnexion: $e\n$s");
    }

    if (!externalContext.mounted) return null;

    return await Navigator.pushAndRemoveUntil<bool?>(
      externalContext,
      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
      (Route<dynamic> route) => false,
    );
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
    _checkUserAndNavigate();
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
      final data = userDoc.data();
      final roles = data != null ? data['roles'] as List<dynamic>? : null;

      if (userDoc.exists && roles != null && roles.isNotEmpty) {
        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) => HomeScreen(
                userId: currentUser.uid,
                initialTranche: userDoc.data()?['favoriteTranche'],
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

  Future<void> _startLoginProcess() async {
    if (_isProcessingLogin) return;
    setState(() => _isProcessingLogin = true);

    try {
      bool? loginSuccess = await Navigator.push<bool?>(
        context,
        MaterialPageRoute(
            builder: (_) => LoginChantierScreen(onSuccess: () {})),
      );

      if (loginSuccess == true) {
        await _saveDeploymentId();
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser == null) {
          if (mounted) setState(() => _isProcessingLogin = false);
          return;
        }

        final userDoc = await fs.FirebaseFirestore.instance
            .collection('utilisateurs')
            .doc(currentUser.uid)
            .get();
        if (!mounted) return;

        final data = userDoc.data();
        final favoriteTranche =
            (userDoc.exists && data != null) ? data['favoriteTranche'] : null;

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => HomeScreen(
              userId: currentUser.uid,
              initialTranche: favoriteTranche,
            ),
          ),
          (Route<dynamic> route) => false,
        );
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
                  const SizedBox(height: 60),
                  if (_isProcessingLogin)
                    const CircularProgressIndicator(color: Colors.green)
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // --- 3. MISE À JOUR DU LOGO DE GAUCHE (Chantier+) ---
                        // --- MISE À JOUR DU LOGO DE GAUCHE (Chantier+) DANS BUILD ---
                        GestureDetector(
                          onTap: () async {
                            // 1. On lance l'écran de connexion d'abord
                            bool? loginSuccess = await Navigator.push<bool?>(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    LoginChantierScreen(onSuccess: () {}),
                              ),
                            );

                            // 2. Si la connexion est réussie, on va vers ChantierPlus
                            if (loginSuccess == true) {
                              if (!mounted) return;
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
                            message: 'Authentification requise pour Chantier+',
                            child: Image.asset(
                              'assets/images/KPILog.png',
                              height: 100,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(
                                  Icons.add_business_outlined,
                                  size: 100,
                                  color: Colors.blueGrey,
                                );
                              },
                            ),
                          ),
                        ),

                        const SizedBox(width: 40),

                        // --- Le logo de droite reste le bouton de connexion ---
                        GestureDetector(
                          onTap: _startLoginProcess, // Déclenche la connexion
                          child: Tooltip(
                            message: 'Accéder à l\'application',
                            child: Image.asset(
                              'assets/images/icon1.png',
                              height: 100,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(
                                  Icons.login,
                                  size: 100,
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
