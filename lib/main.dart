// lib/main.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

// Imports des écrans existants
import 'screens/role_selection_screen.dart';
import 'screens/home_screen.dart';
import 'firebase_options.dart';

// Imports des nouveaux écrans de repères
import 'screens/ajouter_repere_screen.dart';
import 'screens/detail_repere_screen.dart';

const String DEPLOYMENT_ID = "3.0";

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gestion Chantier',
      theme: ThemeData(primarySwatch: Colors.blue),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('fr', 'FR'),
        Locale('en', 'US'),
      ],
      home: const AppInitializer(),

      // Utilisation de onGenerateRoute pour gérer le passage du repereId
      onGenerateRoute: (settings) {
        if (settings.name == '/ajouter_repere') {
          return MaterialPageRoute(
            builder: (context) => const AjouterRepereScreen(),
          );
        }

        if (settings.name == '/detail_repere') {
          // On récupère le String passé dans 'arguments' depuis chantier_plus_screen.dart
          final String repereId = settings.arguments as String;
          return MaterialPageRoute(
            builder: (context) => DetailRepereScreen(repereId: repereId),
          );
        }

        return null; // Route non trouvée
      },
    );
  }
}

/// Écran qui initialise Firebase et gère l'état d'authentification
class AppInitializer extends StatelessWidget {
  const AppInitializer({super.key});

  Future<FirebaseApp> _initializeFirebase() async {
    return Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FirebaseApp>(
      future: _initializeFirebase(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(
              child: Text(
                'Erreur d\'initialisation Firebase',
                style: TextStyle(color: Colors.red),
              ),
            ),
          );
        }

        return const AuthWrapper();
      },
    );
  }
}

/// Wrapper qui gère l'état de connexion de l'utilisateur
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final User? currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser != null) {
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

        if (!snapshot.hasData) {
          return const RoleSelectionScreen();
        }

        return HomeScreen(userId: snapshot.data!.uid);
      },
    );
  }
}
