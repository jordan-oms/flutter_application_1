// lib/main.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

// Imports des écrans existants
import 'screens/role_selection_screen.dart';
import 'screens/home_screen.dart';
import 'firebase_options.dart';

// Imports des nouveaux écrans de repères
import 'screens/ajouter_repere_screen.dart';
import 'screens/detail_repere_screen.dart';

const String DEPLOYMENT_ID = "4.0";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static FirebaseAnalytics analytics = FirebaseAnalytics.instance;
  static FirebaseAnalyticsObserver observer =
      FirebaseAnalyticsObserver(analytics: analytics);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gestion Chantier',
      theme: ThemeData(primarySwatch: Colors.blue),
      navigatorObservers: <NavigatorObserver>[observer],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('fr', 'FR'),
        Locale('en', 'US'),
      ],
      home: const AuthWrapper(),

      // Utilisation de onGenerateRoute pour gérer le passage du repereId
      onGenerateRoute: (settings) {
        if (settings.name == '/ajouter_repere') {
          return MaterialPageRoute(
            builder: (context) => const AjouterRepereScreen(),
            settings: settings,
          );
        }

        if (settings.name == '/detail_repere') {
          // On récupère le String passé dans 'arguments' depuis chantier_plus_screen.dart
          final String repereId = settings.arguments as String;
          return MaterialPageRoute(
            builder: (context) => DetailRepereScreen(repereId: repereId),
            settings: settings,
          );
        }

        return null; // Route non trouvée
      },
    );
  }
}

/// Wrapper qui gère l'état de connexion de l'utilisateur
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  Future<void> _setupAnalytics(User user) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('utilisateurs')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        final nom = data['nom'] ?? 'Inconnu';
        final prenom = data['prenom'] ?? 'Inconnu';
        final nomComplet = "$prenom $nom";
        final heureArrivee =
            DateTime.now().toString().substring(11, 16); // Ex: 14:30

        // La ligne "Tout-en-un" pour votre tableau Realtime
        final infoGlobale = "$nomComplet | Connecté à: $heureArrivee";

        debugPrint("📊 Analytics: $infoGlobale");

        await FirebaseAnalytics.instance.setUserId(id: user.uid);
        await FirebaseAnalytics.instance
            .setUserProperty(name: 'info_utilisateur', value: infoGlobale);

        // On enregistre un ÉVÉNEMENT pour l'historique
        await FirebaseAnalytics.instance.logEvent(
          name: 'connexion_utilisateur',
          parameters: {
            'identite': nomComplet,
            'horaire': heureArrivee,
          },
        );

        // On garde les autres pour les rapports détaillés si besoin
        await FirebaseAnalytics.instance
            .setUserProperty(name: 'nom_complet', value: nomComplet);

        // On force l'envoi avec un événement de login
        await FirebaseAnalytics.instance.logLogin(loginMethod: 'email');
        debugPrint("📊 Analytics: Données envoyées avec succès");
      } else {
        debugPrint(
            "⚠️ Analytics: Aucun document trouvé en base pour l'UID: ${user.uid}");
      }
    } catch (e) {
      debugPrint("❌ Erreur Analytics: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final User? currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser != null) {
      _setupAnalytics(currentUser);
      return HomeScreen(userId: currentUser.uid);
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData && snapshot.data != null) {
          _setupAnalytics(snapshot.data!);
          return HomeScreen(
            userId: snapshot.data!.uid,
          );
        }

        return const RoleSelectionScreen();
      },
    );
  }
}
