// lib/screens/chantier_plus_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChantierPlusScreen extends StatefulWidget {
  const ChantierPlusScreen({super.key});

  @override
  State<ChantierPlusScreen> createState() => _ChantierPlusScreenState();
}

class _ChantierPlusScreenState extends State<ChantierPlusScreen> {
  String searchText = "";

  // 🔹 On initialise sur la tranche "0" (T0) par défaut
  String selectedTranche = "0";
  bool isAdmin = false;

  final Color oMSGreen = const Color(0xFF8EBB21);

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
  }

  // 🔹 Fonction utilitaire pour formater la date et l'heure
  String _formatDateTime(dynamic timestamp) {
    if (timestamp == null) return "--/--";
    DateTime date = (timestamp as Timestamp).toDate();
    return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} à ${date.hour}h${date.minute.toString().padLeft(2, '0')}";
  }

  // 🔹 Vérification des droits administrateur
  Future<void> _checkAdminStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await FirebaseFirestore.instance
        .collection('utilisateurs')
        .doc(user.uid)
        .get();

    if (userDoc.exists) {
      final dynamic rolesField = userDoc.data()?['roles'];
      if (rolesField is List) {
        if (rolesField.contains('administrateur')) {
          setState(() => isAdmin = true);
        }
      } else if (rolesField is String) {
        if (rolesField.toLowerCase() == 'administrateur' ||
            rolesField.toLowerCase() == 'admin') {
          setState(() => isAdmin = true);
        }
      }
    }
  }

  // 🔹 Suppression d'un repère (Admin uniquement)
  Future<void> _deleteRepere(String id) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Supprimer le repère ?"),
        content: Text(
            "Voulez-vous vraiment supprimer définitivement le repère $id ?"),
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
      await FirebaseFirestore.instance.collection('reperes').doc(id).delete();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Repère $id supprimé")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Repères Fonctionnels',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        backgroundColor: oMSGreen,
        foregroundColor: Colors.black,
        centerTitle: true,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: oMSGreen,
        icon: const Icon(Icons.add, color: Colors.black),
        label: const Text("NOUVEAU",
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        onPressed: () => Navigator.pushNamed(context, "/ajouter_repere"),
      ),
      body: Column(
        children: [
          /// 🔹 EN-TÊTE AVEC RECHERCHE ET TRANCHES
          Container(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            decoration: BoxDecoration(
              color: oMSGreen,
              borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                TextField(
                  style: const TextStyle(color: Colors.black),
                  decoration: InputDecoration(
                    hintText: "Rechercher un repère...",
                    hintStyle: TextStyle(color: Colors.black38),
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: Icon(Icons.search, color: oMSGreen),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  onChanged: (value) {
                    setState(() {
                      searchText = value.toUpperCase();

                      // 🔹 DÉTECTION AUTOMATIQUE DE LA TRANCHE
                      if (value.isNotEmpty) {
                        String firstChar = value[0];
                        if (RegExp(r'^[0-9]$').hasMatch(firstChar)) {
                          selectedTranche = firstChar;
                        }
                      }
                    });
                  },
                ),
                const SizedBox(height: 15),

                // 🔹 Sélecteur de Tranches horizontal (TR0 à TR9)
                SizedBox(
                  height: 40,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: 10,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _buildTrancheChip(index.toString()),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          /// 🔹 LISTE FIRESTORE FILTRÉE
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('reperes')
                  .orderBy(FieldPath.documentId)
                  .startAt([selectedTranche]).endAt(
                      ['$selectedTranche\uf8ff']).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting)
                  return const Center(child: CircularProgressIndicator());

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
                  return _buildEmptyState(
                      "Aucun repère en Tranche $selectedTranche");

                final docs = snapshot.data!.docs
                    .where((doc) => doc.id.toUpperCase().contains(searchText))
                    .toList();

                if (docs.isEmpty)
                  return _buildEmptyState("Aucun résultat pour '$searchText'");

                return ListView.builder(
                  padding: const EdgeInsets.only(top: 10, bottom: 80),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final repere = docs[index];
                    final data = repere.data() as Map<String, dynamic>;

                    bool isRecent = false;
                    if (data['lastUpdate']?['date'] != null) {
                      final date =
                          (data['lastUpdate']['date'] as Timestamp).toDate();
                      isRecent = DateTime.now().difference(date).inHours < 24;
                    }

                    return _buildRepereCard(
                      id: repere.id,
                      chantier: data['chantier'] ?? "N/A",
                      local: data['local'] ?? "N/A",
                      diametre: data['diametre'] ?? "N/A",
                      isRecent: isRecent,
                      // Passages des données auteurs et dates
                      createdByUser: data['createdBy']?['nom'] ?? "Inconnu",
                      createdAtDate: data['createdBy']?['date'],
                      lastModByUser: data['lastUpdate']?['nom'] ?? "Inconnu",
                      lastModAtDate: data['lastUpdate']?['date'],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrancheChip(String digit) {
    bool isSelected = selectedTranche == digit;
    return ChoiceChip(
      label: Text("TR$digit",
          style: TextStyle(
              color: isSelected ? Colors.white : Colors.black54,
              fontWeight: FontWeight.bold)),
      selected: isSelected,
      selectedColor: const Color(0xFF6B8E19),
      backgroundColor: Colors.white.withOpacity(0.3),
      showCheckmark: false,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (val) {
        if (val) setState(() => selectedTranche = digit);
      },
    );
  }

  Widget _buildRepereCard({
    required String id,
    required String chantier,
    required String local,
    required String diametre,
    required bool isRecent,
    required String createdByUser,
    required dynamic createdAtDate,
    required String lastModByUser,
    required dynamic lastModAtDate,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 5,
              offset: const Offset(0, 2))
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: oMSGreen.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(Icons.location_on, color: oMSGreen, size: 20),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(id,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.black)),
                const SizedBox(width: 8),
                if (isRecent)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(4)),
                    child: const Text("RÉCENT",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            Text("🏗️ $chantier",
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: oMSGreen)),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.map_outlined, size: 12, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(local,
                      style: TextStyle(fontSize: 11, color: Colors.grey[700])),
                  const SizedBox(width: 10),
                  Icon(Icons.straighten, size: 12, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(diametre,
                      style: TextStyle(fontSize: 11, color: Colors.grey[700])),
                ],
              ),
              const Divider(height: 12, thickness: 0.5),
              // 🔹 CRÉÉ PAR (Persistent)
              Text("👤 Créé par : $createdByUser",
                  style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 10,
                      fontStyle: FontStyle.italic)),
              Text("📅 le ${_formatDateTime(createdAtDate)}",
                  style: TextStyle(color: Colors.grey[500], fontSize: 9)),
              const SizedBox(height: 4),
              // 🔹 DERNIÈRE MODIFICATION
              Text("✏️ Modifié par : $lastModByUser",
                  style: TextStyle(
                      color: oMSGreen.withOpacity(0.8),
                      fontSize: 10,
                      fontWeight: FontWeight.w600)),
              Text("🕒 le ${_formatDateTime(lastModAtDate)}",
                  style: TextStyle(color: Colors.grey[500], fontSize: 9)),
            ],
          ),
        ),
        trailing: isAdmin
            ? IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: Colors.redAccent, size: 20),
                onPressed: () => _deleteRepere(id),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(8),
              )
            : const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
        onTap: () =>
            Navigator.pushNamed(context, "/detail_repere", arguments: id),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(message,
              style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
