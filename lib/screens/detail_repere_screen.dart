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

  // Contrôleurs pour les infos de l'en-tête
  final TextEditingController nomController = TextEditingController();
  final TextEditingController chantierController = TextEditingController();
  final TextEditingController localController = TextEditingController();
  final TextEditingController diametreController = TextEditingController();
  final TextEditingController metrecubeController =
      TextEditingController(); // 🔹 Nouveau

  Map<String, TextEditingController> materielControllers = {};
  Map<String, String> initialValues = {};

  // Infos Création
  String createdBy = "";
  Timestamp? createdAt;

  // Infos Dernière Modification
  String lastModifiedBy = "Aucune";
  Timestamp? lastModifiedAt;

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
      final dynamic rolesField = userDoc.data()?['roles'];
      if (rolesField is List && rolesField.contains('administrateur')) {
        setState(() => isAdmin = true);
      }
    }
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child:
                const Text("SUPPRIMER", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
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

      // Remplissage des contrôleurs du header
      nomController.text = widget.repereId;
      chantierController.text = data['chantier'] ?? "";
      localController.text = data['local'] ?? "";
      diametreController.text = (data['diametre'] ?? "").replaceAll(" DM", "");
      metrecubeController.text =
          (data['metrecube'] ?? "").replaceAll(" M3", ""); // 🔹 Nouveau

      final mats = data['materiels'] as Map<String, dynamic>? ?? {};
      Map<String, TextEditingController> controllers = {};
      Map<String, String> initVals = {};

      categories.forEach((cat, items) {
        for (var nom in items) {
          String val = mats[nom]?.toString() ?? "0";
          controllers[nom] = TextEditingController(text: val);
          initVals[nom] = val;
        }
      });

      setState(() {
        materielControllers = controllers;
        initialValues = initVals;
        createdBy = data['createdBy']?['nom'] ?? "Inconnu";
        createdAt = data['createdBy']?['date'];

        // 🔹 Récupération des infos de modification
        lastModifiedBy = data['lastUpdate']?['nom'] ?? "Aucune";
        lastModifiedAt = data['lastUpdate']?['date'];

        isLoading = false;
      });
    } catch (e) {
      debugPrint("Erreur: $e");
    }
  }

  void _adjustValue(String key, int delta) {
    if (!isEditing) return;
    int current = int.tryParse(materielControllers[key]!.text) ?? 0;
    int newValue = (current + delta < 0) ? 0 : current + delta;
    setState(() => materielControllers[key]!.text = newValue.toString());
  }

  Future<void> _saveChanges() async {
    setState(() => isLoading = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final Map<String, int> matsFinal = {};
    materielControllers.forEach((key, controller) {
      int val = int.tryParse(controller.text) ?? 0;
      if (val > 0) matsFinal[key] = val;
    });

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('utilisateurs')
          .doc(user.uid)
          .get();
      String userName =
          "${userDoc.data()?['prenom'] ?? ""} ${userDoc.data()?['nom'] ?? ""}"
              .trim();

      // 🔹 1. On définit docRef ici pour pouvoir l'utiliser deux fois
      final docRef =
          FirebaseFirestore.instance.collection('reperes').doc(widget.repereId);

      // 🔹 2. On utilise docRef pour la mise à jour
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

      // 🔹 3. On utilise docRef pour ajouter l'historique
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
      debugPrint("Erreur lors de la sauvegarde : $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
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
                ...categories.entries.map((entry) {
                  final itemsToShow = isEditing
                      ? entry.value
                      : entry.value
                          .where((nom) =>
                              (int.tryParse(initialValues[nom] ?? "0") ?? 0) >
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

  Widget _buildGridHeader() {
    String formatDate(Timestamp? ts) {
      if (ts == null) return "N/A";
      return DateFormat('dd/MM/yy à HH:mm').format(ts.toDate());
    }

    return SliverToBoxAdapter(
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: oMSGreen,
          borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(30),
              bottomRight: Radius.circular(30)),
        ),
        child: Column(
          children: [
            // Ligne 1 : Repère + Chantier
            Row(
              children: [
                Expanded(
                    child: _buildHeaderField(nomController, "REPÈRE",
                        enabled: false)),
                const SizedBox(width: 10),
                Expanded(
                    child: _buildHeaderField(chantierController, "CHANTIER",
                        enabled: isEditing)),
              ],
            ),
            const SizedBox(height: 12),
            // Ligne 2 : Local + Diamètre + Mètre Cube (Dividé en 3)
            Row(
              children: [
                Expanded(
                    flex: 2,
                    child: _buildHeaderField(localController, "LOCAL",
                        enabled: isEditing)),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: diametreController,
                    enabled: isEditing,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                        color: Colors.black,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                    decoration: _inputStyle("DIA.").copyWith(
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
                    enabled: isEditing,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                        color: Colors.black,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                    decoration: _inputStyle("VOL.").copyWith(
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
            const SizedBox(height: 15),
            // 🔹 INFOS TRAÇABILITÉ (Création + Modification)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.add_circle_outline,
                          color: Colors.black54, size: 14),
                      const SizedBox(width: 6),
                      Text("Créé par : $createdBy",
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Text(formatDate(createdAt),
                          style: const TextStyle(
                              fontSize: 10, color: Colors.black54)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.history,
                          color: Colors.black54, size: 14),
                      const SizedBox(width: 6),
                      Text("Modifié par : $lastModifiedBy",
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Text(formatDate(lastModifiedAt),
                          style: const TextStyle(
                              fontSize: 10, color: Colors.black54)),
                    ],
                  ),
                ],
              ),
            )
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
      decoration: _inputStyle(label),
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

  Widget _buildMaterielTile(String nom) {
    bool hasChanged = materielControllers[nom]?.text != initialValues[nom];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: hasChanged ? Border.all(color: Colors.red.shade300) : null),
      child: ListTile(
        title: Text(nom,
            style: TextStyle(
                fontSize: 14,
                fontWeight: hasChanged ? FontWeight.bold : FontWeight.normal,
                color: hasChanged ? Colors.red : Colors.black)),
        trailing: isEditing
            ? SizedBox(
                width: 130,
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  _btn(Icons.remove, () => _adjustValue(nom, -1),
                      Colors.red[50]!, Colors.red),
                  SizedBox(
                      width: 35,
                      child: Text(materielControllers[nom]!.text,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.bold))),
                  _btn(Icons.add, () => _adjustValue(nom, 1), Colors.green[50]!,
                      Colors.green),
                ]))
            : Text(initialValues[nom] ?? "0",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: oMSGreen)),
      ),
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
                          Map<String, dynamic> prev = (index + 1 < docs.length)
                              ? docs[index + 1].data() as Map<String, dynamic>
                              : {};
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
                                    bool changed = e.value.toString() !=
                                        (prev['materiels']?[e.key]
                                                ?.toString() ??
                                            "0");
                                    return Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(e.key,
                                              style: TextStyle(
                                                  color: changed
                                                      ? Colors.red
                                                      : Colors.black,
                                                  fontWeight: changed
                                                      ? FontWeight.bold
                                                      : FontWeight.normal)),
                                          Text(e.value.toString(),
                                              style: TextStyle(
                                                  color: changed
                                                      ? Colors.red
                                                      : Colors.blueGrey,
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

  @override
  void dispose() {
    nomController.dispose();
    chantierController.dispose();
    localController.dispose();
    diametreController.dispose();
    metrecubeController.dispose(); // 🔹 Nouveau
    materielControllers.forEach((_, c) => c.dispose());
    super.dispose();
  }
}
