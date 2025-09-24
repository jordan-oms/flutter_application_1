import 'package:flutter/material.dart';

class LoginChantierScreen extends StatefulWidget {
  final Function onSuccess;

  // Modification ici pour utiliser le super parameter pour 'key'
  const LoginChantierScreen({super.key, required this.onSuccess});

  @override
  State<LoginChantierScreen> createState() => _LoginChantierScreenState();
}

class _LoginChantierScreenState extends State<LoginChantierScreen> {
  final TextEditingController passwordController = TextEditingController();
  final String chantierPassword = "1234"; // à changer + sécuriser

  void _login() {
    if (passwordController.text == chantierPassword) {
      widget.onSuccess(); // retour à l'app principale
    } else {
      // Afficher un message si le contexte est toujours monté
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Mot de passe incorrect")),
        );
      }
    }
  }

  @override
  void dispose() {
    passwordController.dispose(); // Bonne pratique de disposer les controllers
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Connexion Chef de Chantier")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          // Pour mieux centrer le contenu
          children: [
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "Mot de passe",
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) =>
                  _login(), // Permet de se connecter en appuyant sur Entrée
            ),
            const SizedBox(height: 24), // Un peu plus d'espace
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 12), // Bouton un peu plus grand
              ),
              onPressed: _login,
              child: const Text("Se connecter"),
            ),
          ],
        ),
      ),
    );
  }
}