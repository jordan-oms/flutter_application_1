import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';

class DetailRepereScreen extends StatefulWidget {
  final String repereId;

  const DetailRepereScreen({super.key, required this.repereId});

  @override
  State<DetailRepereScreen> createState() => _DetailRepereScreenState();
}

class _DetailRepereScreenState extends State<DetailRepereScreen> {
  bool isLoading = true;
  bool isEditing = false;
  bool hasNewNotifications = false;
  bool isAdmin = false;

  final Color oMSGreen = const Color(0xFF8EBB21);

  final TextEditingController nomController = TextEditingController();
  final TextEditingController chantierController = TextEditingController();
  final TextEditingController localController = TextEditingController();
  final TextEditingController diametreController = TextEditingController();
  final TextEditingController metrecubeController = TextEditingController();

  Map<String, TextEditingController> materielControllers = {};
  Map<String, String> initialValues = {};
  Map<String, String> algorithmeTypes = {};
  Map<String, String> initialAlgoTypes = {};

  // --- NOUVEAU : SIMULATION PHOTOS ---
  List<String> selectedImages = [];

  String createdBy = "";
  Timestamp? createdAt;
  String lastModifiedBy = "Aucune";
  Timestamp? lastModifiedAt;

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

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
    _loadRepere();
    _checkNotifications();
  }

  Future<void> _checkAdminStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userDoc = await FirebaseFirestore.instance
        .collection('utilisateurs')
        .doc(user.uid)
        .get();
    if (userDoc.exists) {
      final roles = userDoc.data()?['roles'];
      if (roles is List && roles.contains('administrateur')) {
        setState(() => isAdmin = true);
      }
    }
  }

  Future<void> _loadRepere() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('reperes')
          .doc(widget.repereId)
          .get();
      if (!doc.exists) {
        if (mounted) Navigator.pop(context);
        return;
      }

      final data = doc.data() as Map<String, dynamic>;
      nomController.text = widget.repereId;
      chantierController.text = data['chantier'] ?? "";
      localController.text = data['local'] ?? "";
      diametreController.text = (data['diametre'] ?? "").replaceAll(" DM", "");
      metrecubeController.text =
          (data['metrecube'] ?? "").replaceAll(" M3", "");

      final mats = data['materiels'] as Map<String, dynamic>? ?? {};
      Map<String, TextEditingController> controllers = {};
      Map<String, String> initVals = {};
      Map<String, String> algoTypes = {};

      categories.forEach((cat, items) {
        for (var nom in items) {
          String val = "0";
          if ((nom == "Borne à air" ||
                  nom == "Nombre de protection biologique") &&
              mats[nom] is Map) {
            val = mats[nom]['quantite']?.toString() ?? "0";
            algoTypes[nom] = mats[nom]['type_algo'] ??
                (nom == "Borne à air" ? "UFS" : "standard");
          } else {
            val = mats[nom]?.toString() ?? "0";
          }
          controllers[nom] = TextEditingController(text: val);
          initVals[nom] = val;
        }
      });

      setState(() {
        materielControllers = controllers;
        initialValues = initVals;
        algorithmeTypes = algoTypes;
        initialAlgoTypes = Map.from(algoTypes);
        createdBy = data['createdBy']?['nom'] ?? "Inconnu";
        createdAt = data['createdBy']?['date'];
        lastModifiedBy = data['lastUpdate']?['nom'] ?? "Aucune";
        lastModifiedAt = data['lastUpdate']?['date'];
        isLoading = false;
      });
    } catch (e) {
      debugPrint("Erreur chargement: $e");
    }
  }

  Future<void> _saveChanges() async {
    setState(() => isLoading = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final Map<String, dynamic> matsFinal = {};
    materielControllers.forEach((key, controller) {
      int val = int.tryParse(controller.text) ?? 0;
      if (val > 0) {
        if (key == "Borne à air" || key == "Nombre de protection biologique") {
          matsFinal[key] = {
            'quantite': val,
            'type_algo': algorithmeTypes[key] ??
                (key == "Borne à air" ? "UFS" : "standard")
          };
        } else {
          matsFinal[key] = val;
        }
      }
    });

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('utilisateurs')
          .doc(user.uid)
          .get();
      String userName =
          "${userDoc.data()?['prenom'] ?? ""} ${userDoc.data()?['nom'] ?? ""}"
              .trim();

      final docRef =
          FirebaseFirestore.instance.collection('reperes').doc(widget.repereId);

      await docRef.update({
        'chantier': chantierController.text.trim(),
        'local': localController.text.trim(),
        'diametre': "${diametreController.text.trim()} DM",
        'metrecube': "${metrecubeController.text.trim()} M3",
        'materiels': matsFinal,
        'lastUpdate': {
          'userId': user.uid,
          'nom': userName,
          'date': Timestamp.now()
        }
      });

      await docRef.collection('modifications').add({
        'updatedBy': userName,
        'userId': user.uid,
        'date': Timestamp.now(),
        'materiels': matsFinal,
      });

      setState(() => isEditing = false);
      _loadRepere();
      _markAsRead();
    } catch (e) {
      debugPrint("Erreur sauvegarde: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _adjustValue(String key, int delta) {
    if (!isEditing) return;
    int current = int.tryParse(materielControllers[key]!.text) ?? 0;
    int newValue = (current + delta < 0) ? 0 : current + delta;
    setState(() => materielControllers[key]!.text = newValue.toString());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(widget.repereId,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: oMSGreen,
        foregroundColor: Colors.black,
        actions: [
          if (isAdmin)
            IconButton(
                onPressed: _deleteRepere,
                icon:
                    const Icon(Icons.delete_forever, color: Colors.redAccent)),
          Stack(
            children: [
              IconButton(
                  onPressed: () {
                    _markAsRead();
                    _showHistory();
                  },
                  icon: const Icon(Icons.notifications_none_rounded, size: 28)),
              if (hasNewNotifications)
                Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                            color: Colors.red, shape: BoxShape.circle))),
            ],
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                _buildGridHeader(),

                // --- SECTION DOCUMENTATION VISUELLE COMPACTE ---
                SliverToBoxAdapter(
                  child: _buildCompactMediaSection(),
                ),

                ...categories.entries.map((entry) {
                  final itemsToShow = isEditing
                      ? entry.value
                      : entry.value
                          .where((nom) =>
                              (int.tryParse(
                                      materielControllers[nom]?.text ?? "0") ??
                                  0) >
                              0)
                          .toList();

                  if (itemsToShow.isEmpty)
                    return const SliverToBoxAdapter(child: SizedBox.shrink());

                  return SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      if (index == 0)
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(20, 25, 20, 10),
                          child: Text(entry.key.toUpperCase(),
                              style: TextStyle(
                                  color: oMSGreen,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13)),
                        );
                      return _buildMaterielTile(itemsToShow[index - 1]);
                    }, childCount: itemsToShow.length + 1),
                  );
                }),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed:
            isEditing ? _saveChanges : () => setState(() => isEditing = true),
        backgroundColor: oMSGreen,
        icon: Icon(isEditing ? Icons.save : Icons.edit, color: Colors.black),
        label: Text(isEditing ? "ENREGISTRER" : "MODIFIER",
            style: const TextStyle(
                color: Colors.black, fontWeight: FontWeight.bold)),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  // --- BARRE DE MÉDIAS COMPACTE ET PROFESSIONNELLE ---
  Widget _buildCompactMediaSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 15, 16, 5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.camera_alt_outlined,
                  size: 18, color: Colors.grey.shade700),
              const SizedBox(width: 8),
              const Text("VISUELS DU REPÈRE",
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5)),
              const Spacer(),

              // Bouton d'ajout : Visible uniquement en mode EDITION
              if (isEditing)
                Material(
                  color: oMSGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    onTap: () {
                      setState(() => selectedImages.add("img_test"));
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      child: Row(
                        children: [
                          Icon(Icons.add, size: 14, color: oMSGreen),
                          const SizedBox(width: 4),
                          Text("AJOUTER",
                              style: TextStyle(
                                  color: oMSGreen,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (selectedImages.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 55,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: selectedImages.length,
                itemBuilder: (context, index) {
                  return Stack(
                    children: [
                      Container(
                        width: 55,
                        height: 55,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Icon(Icons.image_outlined,
                            size: 20, color: Colors.grey.shade400),
                      ),

                      // Bouton de suppression : Visible uniquement pour l'ADMIN
                      if (isAdmin)
                        Positioned(
                          top: 0,
                          right: 8,
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => selectedImages.removeAt(index)),
                            child: Container(
                              decoration: const BoxDecoration(
                                  color: Colors.red, shape: BoxShape.circle),
                              padding: const EdgeInsets.all(2),
                              child: const Icon(Icons.close,
                                  size: 10, color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMaterielTile(String nom) {
    bool isBorneAAir = nom == "Borne à air";
    bool isProtectionBio = nom == "Nombre de protection biologique";

    bool qtyChanged = materielControllers[nom]?.text != initialValues[nom];
    bool algoChanged = (isBorneAAir || isProtectionBio) &&
        algorithmeTypes[nom] != initialAlgoTypes[nom];
    bool hasChanged = qtyChanged || algoChanged;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: (isEditing && (isBorneAAir || isProtectionBio))
          ? const EdgeInsets.only(bottom: 12)
          : null,
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: hasChanged
              ? Border.all(color: Colors.red.shade300, width: 1.5)
              : null),
      child: Column(
        children: [
          ListTile(
            title: Text(nom,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight:
                        hasChanged ? FontWeight.bold : FontWeight.normal,
                    color: hasChanged ? Colors.red : Colors.black)),
            trailing: isEditing
                ? SizedBox(
                    width: 130,
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _btn(Icons.remove, () => _adjustValue(nom, -1),
                              Colors.red[50]!, Colors.red),
                          SizedBox(
                              width: 35,
                              child: Text(materielControllers[nom]!.text,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold))),
                          _btn(Icons.add, () => _adjustValue(nom, 1),
                              Colors.green[50]!, Colors.green),
                        ]))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isBorneAAir || isProtectionBio)
                        Text("${algorithmeTypes[nom] ?? ''}  ",
                            style: const TextStyle(
                                fontSize: 12,
                                color: Colors.blueGrey,
                                fontWeight: FontWeight.bold)),
                      Text(materielControllers[nom]?.text ?? "0",
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: oMSGreen)),
                    ],
                  ),
          ),
          if (isEditing && isBorneAAir)
            _buildTypeSelector(nom, ['UFS', 'BFS', 'Autre']),
          if (isEditing && isProtectionBio)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: DropdownButtonFormField<String>(
                value: algorithmeTypes[nom] ?? 'standard',
                style: const TextStyle(color: Colors.black, fontSize: 13),
                decoration: InputDecoration(
                  labelText: "Type de protection",
                  labelStyle: TextStyle(
                      color: oMSGreen,
                      fontWeight: FontWeight.bold,
                      fontSize: 12),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: oMSGreen),
                      borderRadius: BorderRadius.circular(10)),
                ),
                items: const [
                  DropdownMenuItem(value: 'standard', child: Text('Standard')),
                  DropdownMenuItem(value: '1500', child: Text('1500')),
                  DropdownMenuItem(value: 'TO/TP', child: Text('TO/TP')),
                  DropdownMenuItem(
                      value: 'Brique de plombs',
                      child: Text('Briques de plomb')),
                  DropdownMenuItem(value: 'Autre', child: Text('Autre')),
                ],
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() {
                      algorithmeTypes[nom] = newValue;
                    });
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTypeSelector(String nom, List<String> options) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Type :",
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              segments: options
                  .map((opt) => ButtonSegment(
                      value: opt,
                      label: Text(opt, style: const TextStyle(fontSize: 10))))
                  .toList(),
              selected: {algorithmeTypes[nom] ?? options.first},
              onSelectionChanged: (newSelection) =>
                  setState(() => algorithmeTypes[nom] = newSelection.first),
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                selectedBackgroundColor: oMSGreen,
                selectedForegroundColor: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridHeader() {
    String formatDate(Timestamp? ts) =>
        ts == null ? "N/A" : DateFormat('dd/MM/yy à HH:mm').format(ts.toDate());
    return SliverToBoxAdapter(
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
            color: oMSGreen,
            borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30))),
        child: Column(
          children: [
            Row(children: [
              Expanded(
                  child: _buildHeaderField(nomController, "REPÈRE",
                      enabled: false)),
              const SizedBox(width: 10),
              Expanded(
                  child: _buildHeaderField(chantierController, "CHANTIER",
                      enabled: isEditing)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  flex: 2,
                  child: _buildHeaderField(localController, "LOCAL",
                      enabled: isEditing && isAdmin)),
              const SizedBox(width: 8),
              Expanded(
                  flex: 1,
                  child: _buildHeaderNumberField(
                      diametreController, "DIA.", "DM",
                      enabled: isEditing && isAdmin)),
              const SizedBox(width: 8),
              Expanded(
                  flex: 1,
                  child: _buildHeaderNumberField(
                      metrecubeController, "VOL.", "M3",
                      enabled: isEditing && isAdmin)),
            ]),
            const SizedBox(height: 15),
            _buildTraceabilityBox(formatDate),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderField(TextEditingController controller, String label,
      {bool enabled = true}) {
    return TextField(
        controller: controller,
        enabled: enabled,
        style: const TextStyle(
            color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold),
        decoration: _inputStyle(label));
  }

  Widget _buildHeaderNumberField(
      TextEditingController controller, String label, String suffix,
      {required bool enabled}) {
    return TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: TextInputType.number,
        style: const TextStyle(
            color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold),
        decoration: _inputStyle(label).copyWith(
            suffixText: suffix,
            suffixStyle:
                const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)));
  }

  Widget _buildTraceabilityBox(Function formatDate) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.add_circle_outline, color: Colors.black54, size: 14),
          const SizedBox(width: 6),
          Text("Créé par : $createdBy",
              style:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          const Spacer(),
          Text(formatDate(createdAt),
              style: const TextStyle(fontSize: 10, color: Colors.black54)),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          const Icon(Icons.history, color: Colors.black54, size: 14),
          const SizedBox(width: 6),
          Text("Modifié par : $lastModifiedBy",
              style:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          const Spacer(),
          Text(formatDate(lastModifiedAt),
              style: const TextStyle(fontSize: 10, color: Colors.black54)),
        ]),
      ]),
    );
  }

  InputDecoration _inputStyle(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      labelStyle: const TextStyle(
          color: Colors.black, fontWeight: FontWeight.bold, fontSize: 10),
      filled: true,
      fillColor: Colors.white24,
      disabledBorder: OutlineInputBorder(
          borderSide: BorderSide.none, borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.white24),
          borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.white),
          borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _btn(IconData icon, VoidCallback onTap, Color bg, Color fg) => InkWell(
      onTap: onTap,
      child: Container(
          padding: const EdgeInsets.all(4),
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
          child: Icon(icon, size: 18, color: fg)));

  void _showHistory() {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
        builder: (context) => DraggableScrollableSheet(
              initialChildSize: 0.75,
              expand: false,
              builder: (context, scrollController) => Column(children: [
                const SizedBox(height: 20),
                const Text("Historique des modifications",
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('reperes')
                      .doc(widget.repereId)
                      .collection('modifications')
                      .orderBy('date', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData)
                      return const Center(child: CircularProgressIndicator());
                    final docs = snapshot.data!.docs;
                    return ListView.builder(
                        controller: scrollController,
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          var data = docs[index].data() as Map<String, dynamic>;
                          return ExpansionTile(
                            title: Text(data['updatedBy'],
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(DateFormat('dd/MM/yyyy HH:mm')
                                .format((data['date'] as Timestamp).toDate())),
                            children: [
                              Container(
                                  padding: const EdgeInsets.all(15),
                                  color: Colors.grey[50],
                                  child: Column(
                                      children: (data['materiels'] as Map)
                                          .entries
                                          .map((e) {
                                    final val = e.value is Map
                                        ? e.value['quantite']
                                        : e.value;
                                    final type = e.value is Map
                                        ? " (${e.value['type_algo']})"
                                        : "";
                                    return Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text("${e.key}$type"),
                                          Text(val.toString(),
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold)),
                                        ]);
                                  }).toList()))
                            ],
                          );
                        });
                  },
                ))
              ]),
            ));
  }

  Future<void> _deleteRepere() async {
    bool confirm = await showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text("Supprimer ?"),
              content: const Text(
                  "Voulez-vous supprimer ce repère et tout son historique ?"),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text("ANNULER")),
                ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text("SUPPRIMER",
                        style: TextStyle(color: Colors.white))),
              ],
            ));
    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('reperes')
          .doc(widget.repereId)
          .delete();
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _checkNotifications() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('reperes')
        .doc(widget.repereId)
        .get();
    final data = doc.data();
    if (data != null && data['lastUpdate'] != null) {
      Timestamp lastUpdate = data['lastUpdate']['date'];
      final readDoc = await FirebaseFirestore.instance
          .collection('reperes')
          .doc(widget.repereId)
          .collection('lectures')
          .doc(user.uid)
          .get();
      if (!readDoc.exists ||
          lastUpdate.seconds >
              (readDoc.data()?['lastRead'] as Timestamp).seconds) {
        setState(() => hasNewNotifications = true);
      }
    }
  }

  Future<void> _markAsRead() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance
        .collection('reperes')
        .doc(widget.repereId)
        .collection('lectures')
        .doc(user.uid)
        .set({'lastRead': Timestamp.now()});
    setState(() => hasNewNotifications = false);
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
}
