// lib/screens/creation_de_compte.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CreationDeCompte extends StatefulWidget {
  const CreationDeCompte({Key? key}) : super(key: key);

  @override
  _CreationDeCompteState createState() => _CreationDeCompteState();
}

class _CreationDeCompteState extends State<CreationDeCompte> {
  final _formKey = GlobalKey<FormState>();

  // Contrôleurs pour chaque champ de texte
  final _nomController = TextEditingController();
  final _prenomController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    // Libérer la mémoire pour tous les contrôleurs
    _nomController.dispose();
    _prenomController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _creerCompte() async {
    // Vérifie si le formulaire est valide
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 1. Créer l'utilisateur dans Firebase Auth
      final userCredential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // 2. Sauvegarder TOUTES les informations dans Firestore
      await FirebaseFirestore.instance
          .collection('utilisateurs')
          .doc(userCredential.user!.uid)
          .set({
        'uid': userCredential.user!.uid,
        'nom': _nomController.text.trim(),
        'prenom': _prenomController.text.trim(),
        'email': _emailController.text.trim(),
        // Le rôle par défaut pour un utilisateur qui se crée lui-même.
        'roles': ['intervenant'],
        'statut': 'en_attente', // Statut initial
        'createdAt': Timestamp.now(),
      });

      // 3. Envoyer un email de vérification
      await userCredential.user!.sendEmailVerification();

      // 4. Afficher un message de succès et revenir en arrière
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.green,
          content: Text(
              'Compte créé ! En attente de validation par l\'administrateur.'),
        ),
      );
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      // Message d'erreur plus clair pour l'utilisateur
      String message;
      if (e.code == 'email-already-in-use') {
        message = 'Cette adresse e-mail est déjà utilisée par un autre compte.';
      } else if (e.code == 'weak-password') {
        message = 'Le mot de passe est trop faible.';
      } else {
        message = 'Une erreur est survenue. Veuillez réessayer.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Créer un compte'),
      ),
      body: SingleChildScrollView(
        // Ajout de SingleChildScrollView pour éviter les erreurs sur petits écrans
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextFormField(
                  controller: _nomController,
                  decoration: const InputDecoration(
                      labelText: 'Nom', border: OutlineInputBorder()),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Veuillez entrer votre nom';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _prenomController,
                  decoration: const InputDecoration(
                      labelText: 'Prénom', border: OutlineInputBorder()),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Veuillez entrer votre prénom';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                      labelText: 'Email', border: OutlineInputBorder()),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Veuillez entrer votre email';
                    }
                    if (!RegExp(
                            r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+")
                        .hasMatch(value)) {
                      return 'Veuillez entrer un email valide';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                      labelText: 'Mot de passe', border: OutlineInputBorder()),
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Veuillez entrer votre mot de passe';
                    }
                    if (value.length < 6) {
                      return 'Le mot de passe doit contenir au moins 6 caractères';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 30),
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        onPressed: _creerCompte,
                        style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16)),
                        child: const Text('Créer mon compte'),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
