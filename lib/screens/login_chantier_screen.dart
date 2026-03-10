import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'creation_de_compte.dart';
import 'home_screen.dart'; // Import pour la navigation

class LoginChantierScreen extends StatefulWidget {
  final Function onSuccess;

  const LoginChantierScreen({super.key, required this.onSuccess});

  @override
  State<LoginChantierScreen> createState() => _LoginChantierScreenState();
}

class _LoginChantierScreenState extends State<LoginChantierScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _isPasswordVisible = false;
  bool _rememberMe = false;

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  final LocalAuthentication auth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation =
        CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _animController.forward();
    _loadSavedEmail();
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString("saved_email");
    final remember = prefs.getBool("remember_me") ?? false;
    if (remember && savedEmail != null) {
      _emailController.text = savedEmail;
      setState(() => _rememberMe = true);
    }
  }

  Future<void> _saveEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString("saved_email", email);
      await prefs.setBool("remember_me", true);
    } else {
      await prefs.remove("saved_email");
      await prefs.setBool("remember_me", false);
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim());

      final userDoc = await FirebaseFirestore.instance
          .collection('utilisateurs')
          .doc(credential.user!.uid)
          .get();

      if (!userDoc.exists || userDoc.data()?['statut'] != 'valide') {
        await FirebaseAuth.instance.signOut();
        _showSnack(userDoc.exists
            ? "Votre compte n'a pas encore été validé par un administrateur."
            : "Utilisateur non trouvé. Veuillez créer un compte ou contacter un admin.");
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      await _saveEmail(_emailController.text.trim());
      if (mounted) Navigator.pop(context, true);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' ||
          e.code == 'wrong-password' ||
          e.code == 'invalid-credential') {
        _showSnack("Email ou mot de passe incorrect.");
      } else {
        _showSnack(e.message ?? "Erreur de connexion");
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final emailController = TextEditingController(text: _emailController.text);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (context, setStateDialog) {
        bool loading = false;
        return AlertDialog(
          title: const Text("Mot de passe oublié"),
          content: TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: "Votre email"),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Annuler"),
            ),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: CircularProgressIndicator(),
              )
            else
              ElevatedButton(
                onPressed: () async {
                  if (!_isValidEmail(emailController.text.trim())) {
                    if (mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Email invalide")));
                    return;
                  }
                  setStateDialog(() => loading = true);
                  try {
                    await FirebaseAuth.instance.sendPasswordResetEmail(
                        email: emailController.text.trim());
                    if (mounted) {
                      Navigator.pop(context);
                      _showSnack("Email de réinitialisation envoyé");
                    }
                  } catch (e) {
                    if (mounted)
                      _showSnack("Erreur lors de l'envoi de l'email");
                  } finally {
                    if (mounted) setStateDialog(() => loading = false);
                  }
                },
                child: const Text("Envoyer"),
              ),
          ],
        );
      }),
    );
  }

  bool _isValidEmail(String email) {
    return RegExp(r'\S+@\S+\.\S+').hasMatch(email);
  }

  void _showSnack(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _togglePassword() {
    setState(() => _isPasswordVisible = !_isPasswordVisible);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text("Authentification")),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text("Connexion", style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 25),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: "Email",
                          prefixIcon: Icon(Icons.email),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Veuillez entrer un email';
                          }
                          if (!_isValidEmail(value)) {
                            return 'Email invalide';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 15),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: !_isPasswordVisible,
                        decoration: InputDecoration(
                          labelText: "Mot de passe",
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.lock),
                          suffixIcon: IconButton(
                            icon: Icon(_isPasswordVisible
                                ? Icons.visibility
                                : Icons.visibility_off),
                            onPressed: _togglePassword,
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Veuillez entrer un mot de passe';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      CheckboxListTile(
                        value: _rememberMe,
                        title: const Text("Se souvenir de moi"),
                        onChanged: (value) {
                          setState(() => _rememberMe = value ?? false);
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 15),
                      _isLoading
                          ? const CircularProgressIndicator()
                          : SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.login),
                                label: const Text("Se connecter"),
                                onPressed: _login,
                                style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.all(15)),
                              ),
                            ),
                      const SizedBox(height: 15),
                      // ...
                      const Divider(),
                      TextButton.icon(
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text("Accéder en Lecture Seule"),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.blueGrey.shade700,
                        ),
                        onPressed: () {
                          // C'est ici que la modification a lieu
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              // On passe directement à HomeScreen avec le mode lecture seule activé
                              builder: (context) =>
                                  const HomeScreen(isReadOnly: true),
                            ),
                          );
                        },
                      ),
                      const Divider(),
// ...
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: _forgotPassword,
                            child: const Text("Mot de passe oublié ?"),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const CreationDeCompte(),
                                ),
                              );
                            },
                            child: const Text("Créer un compte"),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
