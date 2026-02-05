import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';

class LoginChantierScreen extends StatefulWidget {
  final Function onSuccess;

  const LoginChantierScreen({super.key, required this.onSuccess});

  @override
  State<LoginChantierScreen> createState() => _LoginChantierScreenState();
}

class _LoginChantierScreenState extends State<LoginChantierScreen>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _isPasswordVisible = false;
  bool _rememberMe = false;

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  final LocalAuthentication auth = LocalAuthentication();
  bool _canCheckBiometrics = false;

  // ================= INIT =================
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
    _checkBiometrics();
  }

  // ================= LOAD EMAIL =================
  Future<void> _loadSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString("saved_email");
    final remember = prefs.getBool("remember_me") ?? false;

    if (remember && savedEmail != null) {
      _emailController.text = savedEmail;
      setState(() => _rememberMe = true);
    }
  }

  // ================= SAVE EMAIL =================
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

  // ================= BIOMETRICS =================
  Future<void> _checkBiometrics() async {
    try {
      final canCheck = await auth.canCheckBiometrics;
      setState(() => _canCheckBiometrics = canCheck);
    } catch (e) {
      setState(() => _canCheckBiometrics = false);
    }
  }

  Future<void> _authenticateWithBiometrics() async {
    try {
      final isAuthenticated = await auth.authenticate(
        localizedReason: 'Connectez-vous avec votre empreinte ou FaceID',
        biometricOnly: true,
      );

      if (isAuthenticated) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          if (mounted) Navigator.pop(context, true);
        } else {
          _showSnack("Veuillez d'abord vous connecter avec email/mot de passe");
        }
      }
    } catch (e) {
      _showSnack("Échec de l'authentification biométrique");
    }
  }

  // ================= LOGIN =================
  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showSnack("Veuillez remplir tous les champs");
      return;
    }

    if (!_isValidEmail(email)) {
      _showSnack("Email invalide");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final credential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      if (!credential.user!.emailVerified) {
        await credential.user!.sendEmailVerification();
        _showSnack("Veuillez vérifier votre email.");
        return;
      }

      await _saveEmail(email);

      if (mounted) Navigator.pop(context, true);
    } on FirebaseAuthException catch (e) {
      _showSnack(e.message ?? "Erreur connexion");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ================= RESET PASSWORD =================
  Future<void> _forgotPassword() async {
    final emailController = TextEditingController(text: _emailController.text);
    bool loading = false;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (context, setStateDialog) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
            loading
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(),
                  )
                : ElevatedButton(
                    onPressed: () async {
                      if (!_isValidEmail(emailController.text)) {
                        _showSnack("Email invalide");
                        return;
                      }

                      setStateDialog(() => loading = true);

                      try {
                        await FirebaseAuth.instance.sendPasswordResetEmail(
                            email: emailController.text.trim());

                        if (mounted) {
                          _showSnack("Email de réinitialisation envoyé");
                        }
                      } catch (e) {
                        _showSnack("Erreur envoi email");
                      }
                    },
                    child: const Text("Envoyer"),
                  ),
          ],
        );
      }),
    );
  }

  // ================= HELPERS =================
  bool _isValidEmail(String email) {
    return RegExp(r'\S+@\S+\.\S+').hasMatch(email);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _togglePassword() {
    setState(() => _isPasswordVisible = !_isPasswordVisible);
  }

  // ================= DISPOSE =================
  @override
  void dispose() {
    _animController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar:
          AppBar(title: const Text("Connexion Chef de Chantier/Adminitrateur")),
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
                child: Column(
                  children: [
                    Text("Connexion", style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 25),

                    // EMAIL
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: "Email",
                        prefixIcon: Icon(Icons.email),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 15),

                    // PASSWORD
                    TextField(
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
                    ),
                    const SizedBox(height: 10),

                    // REMEMBER ME
                    CheckboxListTile(
                      value: _rememberMe,
                      title: const Text("Se souvenir de moi"),
                      onChanged: (value) {
                        setState(() => _rememberMe = value ?? false);
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    const SizedBox(height: 15),

                    // LOGIN BUTTON
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
                    const SizedBox(height: 10),

                    // BIOMETRICS BUTTON
                    if (_canCheckBiometrics)
                      ElevatedButton.icon(
                        icon: const Icon(Icons.fingerprint),
                        label: const Text("Connexion biométrique"),
                        onPressed: _authenticateWithBiometrics,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                        ),
                      ),

                    const SizedBox(height: 10),

                    // RESET PASSWORD
                    TextButton(
                      onPressed: _forgotPassword,
                      child: const Text("Mot de passe oublié ?"),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
