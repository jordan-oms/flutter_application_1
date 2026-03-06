// lib/screens/splash_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../main.dart'; // Pour DEPLOYMENT_ID
import 'role_selection_screen.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeAndRedirect();
  }

  Future<void> _initializeAndRedirect() async {
    // --- OPTIMISATION : EXÉCUTION EN PARALLÈLE ---
    // On lance la lecture des préférences et le délai d'attente en même temps.
    final results = await Future.wait([
      SharedPreferences.getInstance(),
      Future.delayed(const Duration(seconds: 1)),
      // Garde le splash screen visible 1s
    ]);

    // On récupère les résultats. Le premier est SharedPreferences, le second est le résultat du délai (qu'on ignore).
    final prefs = results[0] as SharedPreferences;
    // --- FIN DE L'OPTIMISATION ---

    final storedDeploymentId = prefs.getString('deployment_id');
    final currentUser = FirebaseAuth.instance.currentUser;
    User? finalUser =
        currentUser; // On crée une variable mutable pour l'utilisateur

    if (storedDeploymentId != DEPLOYMENT_ID) {
      debugPrint(
          "Nouvelle version détectée ($DEPLOYMENT_ID). Déconnexion forcée.");
      if (currentUser != null) {
        await FirebaseAuth.instance.signOut();
        finalUser = null; // L'utilisateur est maintenant déconnecté
      }
      await prefs.clear();
      await prefs.setString('deployment_id', DEPLOYMENT_ID);
    }

    if (!mounted) return;

    if (finalUser == null) {
      // CAS 1 : Utilisateur non connecté (ou vient d'être déconnecté)
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
      );
    } else {
      // CAS 2 : Utilisateur connecté
      // On tente de charger ses données. Cette partie reste séquentielle car elle dépend de l'ID utilisateur.
      try {
        debugPrint(
            "Utilisateur ${finalUser.uid} connecté. Chargement des données...");

        // La lecture de Firestore reste un `await` car elle est critique.
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(finalUser.uid)
            .get();

        String? favoriteTranche;
        if (userDoc.exists &&
            (userDoc.data() as Map).containsKey('favoriteTranche')) {
          favoriteTranche = userDoc.get('favoriteTranche');
          debugPrint("Tranche favorite trouvée : $favoriteTranche");
        } else {
          debugPrint("Aucune tranche favorite définie pour cet utilisateur.");
        }

        if (!mounted) return;

        // Naviguer vers l'écran principal avec les données
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => HomeScreen(
              userId: finalUser!.uid,
              // On peut utiliser "!" car on a vérifié qu'il n'est pas null
              initialTranche: favoriteTranche,
            ),
          ),
        );
      } catch (e) {
        debugPrint(
            "Erreur critique lors du chargement des données utilisateur: $e");
        // En cas d'échec, déconnecter et rediriger est une stratégie sûre.
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text("Chargement de l'application..."),
          ],
        ),
      ),
    );
  }
}
