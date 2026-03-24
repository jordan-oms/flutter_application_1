// lib/screens/archive_screen.dart

import 'package:flutter/material.dart';
import '../model/consigne.dart';
import 'excel_screen.dart';

// Constantes nécessaires
const String roleAdminString = "administrateur";
const String roleChefDeChantierString = "chef_de_chantier";

class ArchiveScreen extends StatefulWidget {
  final String? selectedTranche;
  final List<String> tranches;
  final List<String> userRoles;
  final Stream<List<Consigne>> Function() getConsignesStream;
  final Future<void> Function(String) deleteConsigneDB;
  final Map<String, TextEditingController> obsNonRealiseeControllers;
  final Map<String, TextEditingController> obsValidationControllers;

  const ArchiveScreen({
    super.key,
    required this.selectedTranche,
    required this.tranches,
    required this.userRoles,
    required this.getConsignesStream,
    required this.deleteConsigneDB,
    required this.obsNonRealiseeControllers,
    required this.obsValidationControllers,
  });

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) {
        setState(() => _searchQuery = _searchController.text);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Formate la date pour l'affichage
  String _formatDateSimple(DateTime? date, {bool showTime = true}) {
    if (date == null) return 'Date inconnue';
    String day = date.day.toString().padLeft(2, '0');
    String month = date.month.toString().padLeft(2, '0');
    String year = date.year.toString();
    if (showTime) {
      String hour = date.hour.toString().padLeft(2, '0');
      String minute = date.minute.toString().padLeft(2, '0');
      return "$day/$month/$year $hour:$minute";
    }
    return "$day/$month/$year";
  }

  // Formate la date pour servir de clé de groupe (YYYY-MM-DD)
  String _getDateKey(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  Widget _buildBlocHeader(String title,
      {MaterialColor headerColor = Colors.green}) {
    return Container(
      color: headerColor.shade100,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(children: [
        Expanded(
            child: Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: headerColor.shade900))),
        Icon(Icons.history, color: headerColor.shade700),
      ]),
    );
  }

  Future<void> _confirmerEtSupprimerConsigneArchivee(Consigne consigne) async {
    if (!widget.userRoles.contains(roleAdminString)) return;

    final bool confirmation = await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) {
            return AlertDialog(
              title: const Text('Suppression définitive'),
              content: Text(
                  "Voulez-vous supprimer définitivement l'archive : ${consigne.contenu} ?"),
              actions: <Widget>[
                TextButton(
                    child: const Text('ANNULER'),
                    onPressed: () => Navigator.of(dialogContext).pop(false)),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('SUPPRIMER'),
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                ),
              ],
            );
          },
        ) ??
        false;

    if (confirmation) {
      await widget.deleteConsigneDB(consigne.id);
    }
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 12.0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Rechercher un contenu, auteur, catégorie...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => _searchController.clear())
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(30.0)),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.selectedTranche == null) {
      return const Center(child: Text("Veuillez sélectionner une tranche."));
    }

    return StreamBuilder<List<Consigne>>(
      stream: widget.getConsignesStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        // 1. Filtrage par recherche
        final archivesInitiales =
            (snapshot.data ?? []).where((c) => c.estValidee).toList();
        final filteredArchives = archivesInitiales.where((c) {
          final q = _searchQuery.toLowerCase();
          return c.contenu.toLowerCase().contains(q) ||
              (c.auteurNomPrenomCreation
                  .toLowerCase()
                  .contains(q)) || // Recherche par auteur
              (c.nomPrenomValidation?.toLowerCase().contains(q) ?? false) ||
              (c.categorie?.toLowerCase().contains(q) ?? false);
        }).toList();

        // 2. Groupement par date
        Map<String, List<Consigne>> groupedArchives = {};
        for (var c in filteredArchives) {
          if (c.dateValidation != null) {
            String key = _getDateKey(c.dateValidation!);
            if (!groupedArchives.containsKey(key)) groupedArchives[key] = [];
            groupedArchives[key]!.add(c);
          }
        }

        // 3. Tri des dates (du plus récent au plus ancien)
        List<String> sortedKeys = groupedArchives.keys.toList()
          ..sort((a, b) => b.compareTo(a));

        return Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildBlocHeader("Archives - ${widget.selectedTranche}",
                    headerColor: Colors.teal),
                _buildSearchBar(),
                Expanded(
                  child: filteredArchives.isEmpty
                      ? const Center(child: Text("Aucune archive trouvée."))
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 80),
                          itemCount: sortedKeys.length,
                          itemBuilder: (context, index) {
                            String dateKey = sortedKeys[index];
                            List<Consigne> dayConsignes =
                                groupedArchives[dateKey]!;

                            // TRI INTERNE : Du plus vieux au plus récent (par heure)
                            dayConsignes.sort((a, b) =>
                                a.dateValidation!.compareTo(b.dateValidation!));

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              child: ExpansionTile(
                                leading: const Icon(Icons.calendar_today,
                                    color: Colors.teal),
                                title: Text(
                                  _formatDateSimple(
                                      dayConsignes.first.dateValidation,
                                      showTime: false),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(
                                    "${dayConsignes.length} consigne(s) validée(s)"),
                                children: dayConsignes
                                    .map((c) => _buildArchiveItem(c))
                                    .toList(),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
            // Bouton Excel
            if (filteredArchives.isNotEmpty &&
                (widget.userRoles.contains(roleAdminString) ||
                    widget.userRoles.contains(roleChefDeChantierString)))
              Positioned(
                bottom: 16.0,
                right: 16.0,
                child: FloatingActionButton(
                  backgroundColor: Colors.green[700],
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => ExcelScreen(
                              archives: filteredArchives,
                              selectedTranche: widget.selectedTranche!))),
                  child: const Icon(Icons.grid_on, color: Colors.white),
                ),
              ),
          ],
        );
      },
    );
  }

  // Widget pour chaque ligne de consigne à l'intérieur du groupe
  Widget _buildArchiveItem(Consigne c) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        color: Colors.white,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.access_time, size: 16, color: Colors.grey),
            Text(
              "${c.dateValidation!.hour.toString().padLeft(2, '0')}:${c.dateValidation!.minute.toString().padLeft(2, '0')}",
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        title: Text(
          c.contenu,
          style: const TextStyle(
              decoration: TextDecoration.lineThrough, fontSize: 14),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Ligne modifiée pour inclure le créateur (auteur)
              Text("Créé par: ${c.auteurNomPrenomCreation}",
                  style: const TextStyle(fontSize: 11, color: Colors.black54)),
              Text("Validé par: ${c.nomPrenomValidation ?? 'Inconnu'}",
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87)),
              if (c.categorie != null)
                Text("Catégorie: ${c.categorie}",
                    style: const TextStyle(fontSize: 11)),
              if (c.commentaireValidation != null &&
                  c.commentaireValidation!.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(4)),
                  child: Text("Obs: ${c.commentaireValidation}",
                      style: const TextStyle(
                          fontSize: 11, fontStyle: FontStyle.italic)),
                ),
              if (c.dosimetrieInfo != null)
                Text("Dosimétrie: ${c.dosimetrieInfo}",
                    style: const TextStyle(fontSize: 11, color: Colors.blue)),
            ],
          ),
        ),
        trailing: widget.userRoles.contains(roleAdminString)
            ? IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => _confirmerEtSupprimerConsigneArchivee(c),
              )
            : null,
      ),
    );
  }
}
