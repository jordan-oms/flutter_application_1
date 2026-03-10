import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

class AjouterRepereScreen extends StatefulWidget {
  const AjouterRepereScreen({super.key});

  @override
  State<AjouterRepereScreen> createState() => _AjouterRepereScreenState();
}

class _AjouterRepereScreenState extends State<AjouterRepereScreen> {
  final TextEditingController nomController = TextEditingController();
  final TextEditingController chantierController = TextEditingController();
  final TextEditingController localController = TextEditingController();
  final TextEditingController diametreController = TextEditingController();
  final TextEditingController metrecubeController = TextEditingController();

  bool isLoading = false;
  String type = "Pair"; // Piloté automatiquement par le listener

  final Color oMSGreen = const Color(0xFF8EBB21);

  final Map<String, List<String>> categories = {
    "Contrôle & Protection ": [
      "Besoin d'un SAS",
      "Plaque macrelon",
      "Tapis piégeant",
      "Saut de zone",
      "MIP 10",
      "Pro-Bio",
      "UFS",
      "BFS",
      "Boyau d'alimentation",
      "Boyau 10m",
      "Boyau 25m",
    ],
    "Aspiration": [
      "Cylair  3000",
      "Cylair  1500",
      "Cylair  1200",
      "Cylair  500",
      "Cylair 300",
      "Nombre de gaine cyclair",
    ],
    "Échafaudage & Structure": [
      "Tructure échafaudage pro-bio",
      "Barre échafaudage 2m",
      "Barre échafaudage 1m",
      "Barre échafaudage 70cm",
      "Barre échafaudage 50cm",
      "Barre échafaudage 25cm",
      "Pôteau échafaudage ",
    ],
  };

  final Map<String, TextEditingController> materielControllers = {};

  @override
  void initState() {
    super.initState();
    categories.forEach((cat, items) {
      for (var item in items) {
        materielControllers[item] = TextEditingController(text: "0");
      }
    });
    nomController.addListener(_autoDetectType);
  }

  void _autoDetectType() {
    String text = nomController.text.trim();
    if (text.isNotEmpty) {
      int? firstDigit = int.tryParse(text[0]);
      if (firstDigit != null) {
        String newType = (firstDigit % 2 == 0) ? "Pair" : "Impair";
        if (type != newType) {
          setState(() {
            type = newType;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    nomController.removeListener(_autoDetectType);
    nomController.dispose();
    chantierController.dispose();
    localController.dispose();
    diametreController.dispose();
    metrecubeController.dispose();
    materielControllers.forEach((_, c) => c.dispose());
    super.dispose();
  }

  void _adjustValue(String key, int delta) {
    int current = int.tryParse(materielControllers[key]!.text) ?? 0;
    int newValue = current + delta;
    if (newValue < 0) newValue = 0;
    setState(() {
      materielControllers[key]!.text = newValue.toString();
    });
  }

  Future<void> ajouterRepere() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    String nomRepere = nomController.text.trim().toUpperCase();

    final regExpComplet = RegExp(r'^\d[A-Z]{3}\d{3}[A-Z]{2}$');
    if (!regExpComplet.hasMatch(nomRepere)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                "Format de repère invalide ou incomplet ! (Ex: 1ABC123DE)"),
            backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => isLoading = true);
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('utilisateurs')
          .doc(user.uid)
          .get();
      String nomComplet =
          "${userDoc.data()?['prenom'] ?? ""} ${userDoc.data()?['nom'] ?? ""}"
              .trim();

      final docRef =
          FirebaseFirestore.instance.collection('reperes').doc(nomRepere);
      final doc = await docRef.get();

      if (doc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Ce repère existe déjà"),
            backgroundColor: Colors.red));
        setState(() => isLoading = false);
        return;
      }

      final Map<String, int> materiels = {};
      materielControllers.forEach((key, controller) {
        final val = int.tryParse(controller.text) ?? 0;
        if (val > 0) materiels[key] = val;
      });

      await docRef.set({
        'type': type,
        'chantier': chantierController.text.trim(),
        'local': localController.text.trim(),
        'diametre': "${diametreController.text.trim()} DM",
        'metrecube': "${metrecubeController.text.trim()} M3",
        'materiels': materiels,
        'createdBy': {
          'userId': user.uid,
          'nom': nomComplet,
          'date': Timestamp.now()
        },
        'lastUpdate': {
          'userId': user.uid,
          'nom': nomComplet,
          'date': Timestamp.now()
        }
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Créé avec succès"), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Erreur : $e")));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Nouveau Repère",
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: oMSGreen,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(15, 15, 15, 25),
                  // Padding ajusté
                  decoration: BoxDecoration(
                    color: oMSGreen,
                    borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(30),
                        bottomRight: Radius.circular(30)),
                  ),
                  child: Column(
                    children: [
                      // --- LIGNE 1 : Repère + Chantier ---
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: nomController,
                              style: const TextStyle(
                                  color: Colors.black, fontSize: 14),
                              inputFormatters: [
                                LengthLimitingTextInputFormatter(9),
                                RepereInputFormatter()
                              ],
                              decoration: _inputStyle(
                                  "REPÈRE FONCTIONNEL", "1ABC123DE"),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: chantierController,
                              style: const TextStyle(
                                  color: Colors.black, fontSize: 14),
                              decoration:
                                  _inputStyle("NOM DU CHANTIER", "Chantier"),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // --- LIGNE 2 : Local + Diamètre + Mètre Cube ---
                      Row(
                        children: [
                          Expanded(
                            flex: 2, // Un peu plus large pour le local
                            child: TextField(
                              controller: localController,
                              style: const TextStyle(
                                  color: Colors.black, fontSize: 14),
                              decoration: _inputStyle("LOCAL", "Position"),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 1,
                            child: TextField(
                              controller: diametreController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(
                                  color: Colors.black, fontSize: 14),
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              decoration: _inputStyle("DIA.", "Ø").copyWith(
                                suffixText: "DM",
                                suffixStyle: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 1,
                            child: TextField(
                              controller: metrecubeController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(
                                  color: Colors.black, fontSize: 14),
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              decoration: _inputStyle("VOL.", "M3").copyWith(
                                suffixText: "M3",
                                suffixStyle: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              ...categories.entries.map((entry) => SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index == 0) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(20, 25, 20, 10),
                            child: Text(entry.key.toUpperCase(),
                                style: TextStyle(
                                    color: oMSGreen,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    letterSpacing: 1.2)),
                          );
                        }
                        return _buildMaterielTile(entry.value[index - 1]);
                      },
                      childCount: entry.value.length + 1,
                    ),
                  )),
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: SizedBox(
              height: 60,
              child: ElevatedButton(
                onPressed: isLoading ? null : ajouterRepere,
                style: ElevatedButton.styleFrom(
                  backgroundColor: oMSGreen,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  elevation: 5,
                ),
                child: isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("CRÉER LE REPÈRE",
                        style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaterielTile(String nom) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ]),
      child: ListTile(
        title: Text(nom,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        trailing: SizedBox(
          width: 140,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _btnCounter(Icons.remove, () => _adjustValue(nom, -1),
                  Colors.red[50]!, Colors.red[700]!),
              SizedBox(
                  width: 40,
                  child: TextField(
                      controller: materielControllers[nom],
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(border: InputBorder.none),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                      onChanged: (v) => setState(() {}))),
              _btnCounter(Icons.add, () => _adjustValue(nom, 1),
                  Colors.green[50]!, Colors.green[700]!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _btnCounter(
      IconData icon, VoidCallback onPressed, Color bg, Color fg) {
    return InkWell(
        onTap: onPressed,
        child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 18, color: fg)));
  }

  InputDecoration _inputStyle(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: true,
      hintStyle: const TextStyle(color: Colors.black38, fontSize: 11),
      labelStyle: const TextStyle(
          color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11),
      enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.white24),
          borderRadius: BorderRadius.circular(15)),
      focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.white),
          borderRadius: BorderRadius.circular(15)),
      filled: true,
      fillColor: Colors.white24,
    );
  }
}

class RepereInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text.toUpperCase();
    if (text.isEmpty) return newValue;
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      if (i == 0) {
        if (!RegExp(r'[0-9]').hasMatch(char)) return oldValue;
      } else if (i >= 1 && i <= 3) {
        if (!RegExp(r'[A-Z]').hasMatch(char)) return oldValue;
      } else if (i >= 4 && i <= 6) {
        if (!RegExp(r'[0-9]').hasMatch(char)) return oldValue;
      } else if (i >= 7 && i <= 8) {
        if (!RegExp(r'[A-Z]').hasMatch(char)) return oldValue;
      }
    }
    return newValue.copyWith(text: text, selection: newValue.selection);
  }
}
