// lib/main.dart
import 'package:flutter/material.dart'; // Fournit debugPrint
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs; // Alias pour cohérence

// IMPORTATION IMPORTANTE : Le fichier généré par FlutterFire CLI
import 'firebase_options.dart'; // Assurez-vous que le nom du fichier est correct

import 'screens/role_selection_screen.dart'; // Assurez-vous que ce chemin est correct

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Remplacé print par debugPrint
  debugPrint(
      "Firebase initialized with DefaultFirebaseOptions for current platform.");

  try {
    // Utilisation de l'alias fs pour FirebaseFirestore
    fs.FirebaseFirestore.instance.settings = const fs.Settings(
      persistenceEnabled: false,
    );
    // Remplacé print par debugPrint
    debugPrint("[Main] Firestore persistence explicitly disabled for testing.");
  } catch (e, s) { // Ajout de la StackTrace s
    // Remplacé print par debugPrint
    debugPrint(
        "[Main] Error setting Firestore persistence (might be already set or web): $e\nStackTrace: $s");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key}); // super.key est déjà bien utilisé ici

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gestion Chantier',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        // colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        // useMaterial3: true,
      ),
      home: const RoleSelectionScreen(),
      // routes: {
      //   // ...
      // },
    );
  }
}