// lib/screens/login_chantier_screen.dart
import 'package:flutter/material.dart'; // Fournit debugPrint et Key
import 'package:firebase_auth/firebase_auth.dart';
// Pas besoin d'importer 'package:flutter/foundation.dart' si 'material.dart' est là

class LoginChantierScreen extends StatefulWidget {
  final Function onSuccess;

  // Modifié pour super.key
  const LoginChantierScreen({super.key, required this.onSuccess});

  @override
  // Modifié pour retourner le type d'état public
  LoginChantierScreenState createState() => LoginChantierScreenState();
}

// Classe d'état renommée en LoginChantierScreenState (publique)
class LoginChantierScreenState extends State<LoginChantierScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _login() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Veuillez saisir l'e-mail et le mot de passe.")),
        );
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      // Remplacé print par debugPrint
      debugPrint(
          "[LoginChantierScreen] Tentative de connexion Firebase avec email: ${_emailController
              .text.trim()}");

      final UserCredential userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // Remplacé print par debugPrint
      debugPrint(
          "[LoginChantierScreen] Connexion Firebase RÉUSSIE. UID: ${userCredential
              .user?.uid}, Email: ${userCredential.user?.email}");

      if (userCredential.user != null) {
        // Remplacé print par debugPrint
        debugPrint(
            "[LoginChantierScreen] User non null. User ID: ${userCredential
                .user!.uid}. Appel de widget.onSuccess() et pop(true)...");

        // widget.onSuccess();

        if (mounted) {
          Navigator.pop(context, true);
        }
      } else {
        // Remplacé print par debugPrint
        debugPrint(
            "[LoginChantierScreen] Connexion Firebase réussie MAIS userCredential.user est NULL !");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text("Erreur inattendue lors de la connexion.")),
          );
          Navigator.pop(context, false);
        }
      }
    } on FirebaseAuthException catch (e, s) { // Ajout de la StackTrace s pour debugPrint
      // Remplacé print par debugPrint
      debugPrint(
          "[LoginChantierScreen] ERREUR de connexion Firebase: ${e.code} - ${e
              .message}\nStackTrace: $s");
      String errorMessage = "Une erreur s'est produite.";
      if (e.code == 'user-not-found' ||
          e.code ==
              'INVALID_LOGIN_CREDENTIALS' || // Nouveau code d'erreur possible
          e.code == 'invalid-credential') { // Code d'erreur plus récent
        errorMessage =
        "Aucun utilisateur trouvé pour cet e-mail ou mot de passe incorrect.";
      } else if (e.code == 'wrong-password') {
        errorMessage = "Mot de passe incorrect.";
      } else if (e.code == 'invalid-email') {
        errorMessage = "Format d'e-mail invalide.";
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
        Navigator.pop(context, false);
      }
    } catch (e, s) { // Ajout de la StackTrace s pour debugPrint
      // Remplacé print par debugPrint
      debugPrint(
          "[LoginChantierScreen] ERREUR inconnue pendant la connexion: $e\nStackTrace: $s");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Une erreur inconnue s'est produite.")),
        );
        Navigator.pop(context, false);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Connexion Chef de Chantier / Admin")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: "E-mail",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "Mot de passe",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
            ),
            const SizedBox(height: 24),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton.icon(
              icon: const Icon(Icons.login),
              onPressed: _login,
              label: const Text("Se connecter"),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}