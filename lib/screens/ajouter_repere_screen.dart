import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

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
      "Plaque de SAS 2*1",
      "Tapis piégeant",
      "Saut de zone",
      "Contaminamètre",
      "Borne à air",
      "Nombre de protection biologique",
      "Boyau d'alimentation",
      "Boyau 10m",
      "Boyau 25m",
    ],
    "Aspiration": [
      "Déprimogéne 3000",
      "Déprimogéne 1500",
      "Déprimogéne 1200",
      "Déprimogéne 500",
      "Déprimogéne 300",
      "Nombre de gaine Déprimogéne ",
    ],
    "Structure": [
      "Structure pro-bio",
      "Barre de structure de SAS 2m",
      "Barre de structure de SAS 1m",
      "Barre de structure de SAS 0,7m",
      "Barre de structure de SAS 0,5m",
      "Barre de structure de SAS 0,25m",
      "Pôteau de structure de SAS ",
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
          algorithmeTypes[item] = "Standard";
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

  Future<void> importerMassif() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      if (result == null) return;
      setState(() => isLoading = true);

      String content;
      if (kIsWeb) {
        content = utf8.decode(result.files.single.bytes!);
      } else {
        final file = File(result.files.single.path!);
        content = await file.readAsString(encoding: utf8);
      }

      final fields =
          const CsvToListConverter(fieldDelimiter: ';').convert(content);
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Récupération des infos utilisateur une seule fois avant la boucle
      final userDoc = await FirebaseFirestore.instance
          .collection('utilisateurs')
          .doc(user.uid)
          .get();

      String nomComplet =
          "${userDoc.data()?['prenom'] ?? ""} ${userDoc.data()?['nom'] ?? ""}"
              .trim();
      Timestamp maintenant = Timestamp.now();

      WriteBatch batch = FirebaseFirestore.instance.batch();
      int importCount = 0;
      int operationCount = 0;
      int totalRows = fields.length - 1;

      for (var i = 1; i < fields.length; i++) {
        var row = fields[i];
        if (row.length < 5) continue;

        String nomRepere = row[0].toString().trim().toUpperCase();
        // Regex de validation
        if (!RegExp(r'^\d[A-Z]{3}\d{3}[A-Z]{2}$').hasMatch(nomRepere)) continue;

        int? firstDigit = int.tryParse(nomRepere[0]);
        String typeDetecte =
            (firstDigit != null && firstDigit % 2 == 0) ? "Pair" : "Impair";

        DocumentReference docRef =
            FirebaseFirestore.instance.collection('reperes').doc(nomRepere);

        batch.set(docRef, {
          'type': typeDetecte,
          'chantier': row[1].toString(),
          'local': row[2].toString(),
          'diametre': "${row[3]} DM",
          'metrecube': "${row[4]} M3",
          'materiels': {},
          'createdBy': {
            'userId': user.uid,
            'nom': nomComplet,
            'date': maintenant
          },
          'lastUpdate': {
            'userId': user.uid,
            'nom': nomComplet,
            'date': maintenant
          }
        });

        importCount++;
        operationCount++;

        // Tous les 500 documents (limite max d'un batch Firestore)
        if (operationCount == 500) {
          await batch.commit();
          batch = FirebaseFirestore.instance.batch();
          operationCount = 0;

          // CRUCIAL : Pause pour éviter que le PC ne fige et laisser le réseau respirer
          await Future.delayed(const Duration(milliseconds: 100));
          print("Importation en cours : $importCount / $totalRows");
        }
      }

      // Envoi du reliquat
      if (operationCount > 0) await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("$importCount repères importés avec succès !"),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      print("Erreur Import CSV: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red));
      }
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
      final String firstChar = nomRepere[0];
      final String suffix = nomRepere.substring(1);
      List<String> tranchesCibles = [];

      // Définition des groupes de duplication
      if (['1', '3', '5'].contains(firstChar)) {
        tranchesCibles = ['1', '3', '5'];
      } else if (['2', '4', '6'].contains(firstChar)) {
        tranchesCibles = ['2', '4', '6'];
      } else {
        // Tranches hors groupe (0, 7, 8, 9, etc.)
        tranchesCibles = [firstChar];
      }

      // 1. VÉRIFICATION ANTI-DOUBLON SUR TOUT LE GROUPE
      List<String> dejaExistants = [];
      for (String tr in tranchesCibles) {
        String idVerif = tr + suffix;
        final doc = await FirebaseFirestore.instance
            .collection('reperes')
            .doc(idVerif)
            .get();
        if (doc.exists) {
          dejaExistants.add(idVerif);
        }
      }

      if (dejaExistants.isNotEmpty) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text("Repère(s) déjà existant(s)"),
              content: Text(
                  "Impossible de créer ce groupe : le(s) repère(s) suivant(s) existe(nt) déjà : ${dejaExistants.join(', ')}"),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("OK"),
                ),
              ],
            ),
          );
        }
        setState(() => isLoading = false);
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('utilisateurs')
          .doc(user.uid)
          .get();
      String nomComplet =
          "${userDoc.data()?['prenom'] ?? ""} ${userDoc.data()?['nom'] ?? ""}"
              .trim();
      Timestamp maintenant = Timestamp.now();

      final Map<String, dynamic> materiels = {};
      materielControllers.forEach((key, controller) {
        final val = int.tryParse(controller.text) ?? 0;
        if (val > 0) {
          if (key == "Borne à air" ||
              key == "Nombre de protection biologique") {
            materiels[key] = {
              'quantite': val,
              'type_algo': algorithmeTypes[key] ??
                  (key == "Borne à air" ? "UFS" : "Standard")
            };
          } else {
            materiels[key] = val;
          }
        }
      });

      // 2. CRÉATION EN BATCH (Atomique)
      WriteBatch batch = FirebaseFirestore.instance.batch();

      for (String tr in tranchesCibles) {
        String idFinal = tr + suffix;
        int? numTr = int.tryParse(tr);
        String typeTr = (numTr != null && numTr % 2 == 0) ? "Pair" : "Impair";

        DocumentReference docRef =
            FirebaseFirestore.instance.collection('reperes').doc(idFinal);

        batch.set(docRef, {
          'type': typeTr,
          'chantier': chantierController.text.trim(),
          'local': localController.text.trim(),
          'diametre': "${diametreController.text.trim()} DM",
          'metrecube': "${metrecubeController.text.trim()} M3",
          'materiels': materiels,
          'createdBy': {
            'userId': user.uid,
            'nom': nomComplet,
            'date': maintenant
          },
          'lastUpdate': {
            'userId': user.uid,
            'nom': nomComplet,
            'date': maintenant
          }
        });
      }

      await batch.commit();

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
              tooltip: "Import CSV massif")
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
                                  decoration: _inputStyle(
                                      "NOM DU CHANTIER", "Chantier"))),
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
          if (isLoading)
            Container(
              color: Colors.black26,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 20),
                    Text(
                        "Importation en cours...\nVeuillez ne pas fermer l'application.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
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
    bool isBorneAAir = nom == "Borne à air";
    bool isProtectionBio = nom == "Nombre de protection biologique";
    int quantite = int.tryParse(materielControllers[nom]!.text) ?? 0;

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
                      onPressed: () => _adjustValue(nom, -1)),
                  Text(materielControllers[nom]!.text,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  IconButton(
                      icon: const Icon(Icons.add_circle_outline,
                          color: Colors.green),
                      onPressed: () => _adjustValue(nom, 1)),
                ],
              ),
            ),
          ),
          if ((isBorneAAir || isProtectionBio) && quantite > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: isProtectionBio
                  ? _buildProtectionDropdown(nom)
                  : _buildBorneSelector(nom),
            ),
        ],
      ),
    );
  }

  Widget _buildProtectionDropdown(String nom) {
    return DropdownButtonFormField<String>(
      value: algorithmeTypes[nom],
      decoration: _dropdownDecoration("Type de protection"),
      items: const [
        DropdownMenuItem(
            value: "Standard",
            child: Text("Standard", style: TextStyle(fontSize: 13))),
        DropdownMenuItem(
            value: "Brique de plombs",
            child: Text("Brique de plombs", style: TextStyle(fontSize: 13))),
        DropdownMenuItem(
            value: "TO/TP",
            child: Text("TO/TP", style: TextStyle(fontSize: 13))),
        DropdownMenuItem(
            value: "Autre",
            child: Text("Autre", style: TextStyle(fontSize: 13))),
      ],
      onChanged: (val) {
        if (val != null) setState(() => algorithmeTypes[nom] = val);
      },
    );
  }

  Widget _buildBorneSelector(String nom) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("TYPE D'ALGORITHME :",
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 8),
        Row(
          children: [
            _choiceChip(nom, "UFS"),
            const SizedBox(width: 8),
            _choiceChip(nom, "BFS"),
          ],
        ),
      ],
    );
  }

  Widget _choiceChip(String itemKey, String value) {
    bool isSelected = algorithmeTypes[itemKey] == value;
    return ChoiceChip(
      label: Text(value,
          style: TextStyle(
              fontSize: 11, color: isSelected ? Colors.white : Colors.black)),
      selected: isSelected,
      selectedColor: oMSGreen,
      onSelected: (bool selected) {
        if (selected) setState(() => algorithmeTypes[itemKey] = value);
      },
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

  InputDecoration _dropdownDecoration(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      labelStyle: const TextStyle(
          fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300)),
    );
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
    if (text.isEmpty ||
        RegExp(r'^\d?[A-Z]{0,3}\d{0,3}[A-Z]{0,2}$').hasMatch(text)) {
      return newValue.copyWith(text: text, selection: newValue.selection);
    }
    return oldValue;
  }
}
