import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';

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
  String type = "Pair";
  List<String> selectedImages = [];
  final Color oMSGreen = const Color(0xFF8EBB21);

  final Map<String, List<String>> categories = {
    "Contrôle & Protection ": [
      "Pas besoin de Micout",
      "Plaque de SAS 2*1",
      "Tapis piégeant",
      "Saut de zone",
      "Contaminamètre",
      "Nombre de matelas",
      "Borne à air",
      "Nombre de protection biologique",
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
      "Structure pro-bio",
      "Barre échafaudage 2m",
      "Barre échafaudage 1m",
      "Barre échafaudage 70cm",
      "Barre échafaudage 50cm",
      "Barre échafaudage 25cm",
      "Pôteau échafaudage ",
      "Semelles",
    ],
  };

  final Map<String, TextEditingController> materielControllers = {};
  final Map<String, String> algorithmeTypes = {};

  @override
  void initState() {
    super.initState();
    categories.forEach((cat, items) {
      for (var item in items) {
        materielControllers[item] = TextEditingController(text: "0");
        if (item == "Borne à air") {
          algorithmeTypes[item] = "UFS";
        } else if (item == "Nombre de protection biologique") {
          algorithmeTypes[item] = "standard";
        }
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
        if (type != newType) setState(() => type = newType);
      }
    }
  }

  @override
  void dispose() {
    nomController.dispose();
    chantierController.dispose();
    localController.dispose();
    diametreController.dispose();
    metrecubeController.dispose();
    materielControllers.forEach((_, c) => c.dispose());
    super.dispose();
  }

  // --- FONCTION D'IMPORTATION MASSIVE (5000 REPERES) ---
  Future<void> importerMassif() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result == null) return;

      setState(() => isLoading = true);
      final file = File(result.files.single.path!);
      final input = file.openRead();

      // Transforme le flux CSV en liste de listes
      final fields = await input
          .transform(utf8.decoder)
          .transform(const CsvToListConverter(
              fieldDelimiter: ';')) // <--- Correction ici
          .toList();

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userDoc = await FirebaseFirestore.instance
          .collection('utilisateurs')
          .doc(user.uid)
          .get();
      String nomComplet =
          "${userDoc.data()?['prenom'] ?? ""} ${userDoc.data()?['nom'] ?? ""}"
              .trim();

      int importCount = 0;
      // On commence à i=1 pour sauter l'en-tête du tableau
      for (var i = 1; i < fields.length; i++) {
        var row = fields[i];
        if (row.length < 5) continue;

        String nomRepere = row[0].toString().trim().toUpperCase();
        // Validation du format 1ABC123DE
        if (!RegExp(r'^\d[A-Z]{3}\d{3}[A-Z]{2}$').hasMatch(nomRepere)) continue;

        int? firstDigit = int.tryParse(nomRepere[0]);
        String typeDetecte =
            (firstDigit != null && firstDigit % 2 == 0) ? "Pair" : "Impair";

        await FirebaseFirestore.instance
            .collection('reperes')
            .doc(nomRepere)
            .set({
          'type': typeDetecte,
          'chantier': row[1].toString(),
          'local': row[2].toString(),
          'diametre': "${row[3]} DM",
          'metrecube': "${row[4]} M3",
          'materiels': {},
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
        importCount++;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("$importCount repères importés !"),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Erreur: $e")));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> ajouterRepere() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    String nomRepere = nomController.text.trim().toUpperCase();
    if (!RegExp(r'^\d[A-Z]{3}\d{3}[A-Z]{2}$').hasMatch(nomRepere)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Format invalide !"), backgroundColor: Colors.red));
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

      final Map<String, dynamic> materiels = {};
      materielControllers.forEach((key, controller) {
        final val = int.tryParse(controller.text) ?? 0;
        if (val > 0) {
          if (key == "Borne à air" ||
              key == "Nombre de protection biologique") {
            materiels[key] = {
              'quantite': val,
              'type_algo': algorithmeTypes[key] ?? "standard"
            };
          } else {
            materiels[key] = val;
          }
        }
      });

      await FirebaseFirestore.instance
          .collection('reperes')
          .doc(nomRepere)
          .set({
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

      if (mounted) Navigator.pop(context);
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
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload),
            onPressed: isLoading ? null : importerMassif,
            tooltip: "Import CSV massif",
          )
        ],
      ),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(15, 15, 15, 20),
                  decoration: BoxDecoration(
                    color: oMSGreen,
                    borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(30),
                        bottomRight: Radius.circular(30)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: nomController,
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
                              decoration:
                                  _inputStyle("NOM DU CHANTIER", "Chantier"),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                              flex: 2,
                              child: TextField(
                                  controller: localController,
                                  decoration:
                                      _inputStyle("LOCAL", "Position"))),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 1,
                            child: TextField(
                              controller: diametreController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              decoration: _inputStyle("DIA.", "Ø")
                                  .copyWith(suffixText: "DM"),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 1,
                            child: TextField(
                              controller: metrecubeController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              decoration: _inputStyle("VOL.", "M3")
                                  .copyWith(suffixText: "M3"),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(child: _buildCompactMediaSection()),
              ...categories.entries.map((entry) => SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index == 0) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                            child: Text(entry.key.toUpperCase(),
                                style: TextStyle(
                                    color: oMSGreen,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12)),
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
          if (isLoading) const Center(child: CircularProgressIndicator()),
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
                        borderRadius: BorderRadius.circular(20))),
                child: const Text("CRÉER LE REPÈRE",
                    style: TextStyle(
                        color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- LES WIDGETS DE SOUTIEN (REPRIS DE VOTRE CODE) ---
  Widget _buildCompactMediaSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 15, 16, 5),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(15)),
      child: Row(
        children: [
          const Icon(Icons.camera_alt_outlined, size: 18),
          const SizedBox(width: 8),
          const Text("VISUELS DU REPÈRE",
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          const Spacer(),
          TextButton(
              onPressed: () => setState(() => selectedImages.add("img")),
              child: const Text("+ AJOUTER"))
        ],
      ),
    );
  }

  Widget _buildMaterielTile(String nom) {
    bool custom =
        nom == "Borne à air" || nom == "Nombre de protection biologique";
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(15)),
      child: Column(
        children: [
          ListTile(
            title: Text(nom, style: const TextStyle(fontSize: 14)),
            trailing: SizedBox(
              width: 130,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline,
                        color: Colors.red),
                    onPressed: () => _adjustValue(nom, -1),
                  ),
                  Text(
                    materielControllers[nom]!.text,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline,
                        color: Colors.green),
                    onPressed: () => _adjustValue(nom, 1),
                  ),
                ],
              ),
            ),
          ),
          if (custom)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text("Paramètres spécifiques (Optionnel)",
                  style: TextStyle(fontSize: 10, color: Colors.grey)),
            ),
        ],
      ),
    );
  }

  void _adjustValue(String key, int delta) {
    int val = (int.tryParse(materielControllers[key]!.text) ?? 0) + delta;
    if (val >= 0) {
      setState(() {
        materielControllers[key]!.text = val.toString();
      });
    }
  }

  InputDecoration _inputStyle(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Colors.white24,
      labelStyle: const TextStyle(
          color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
      enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.white24),
          borderRadius: BorderRadius.circular(15)),
    );
  }
}

class RepereInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text.toUpperCase();
    // Permet la saisie progressive tout en restant en majuscule
    if (text.isEmpty ||
        RegExp(r'^\d?[A-Z]{0,3}\d{0,3}[A-Z]{0,2}$').hasMatch(text)) {
      return newValue.copyWith(
        text: text,
        selection: newValue.selection,
      );
    }
    return oldValue;
  }
}
