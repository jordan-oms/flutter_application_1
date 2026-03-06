// lib/screens/archive_screen.dart

import 'package:flutter/material.dart';
import '../model/consigne.dart'; // Assurez-vous que le chemin est correct
// Assurez-vous que le fichier excel_screen.dart existe bien dans le dossier screens
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
        setState(() {
          _searchQuery = _searchController.text;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
        Text(_formatDateSimple(DateTime.now(), showTime: false),
            style: TextStyle(fontSize: 14, color: headerColor.shade700)),
      ]),
    );
  }

  Future<void> _confirmerEtSupprimerConsigneArchivee(Consigne consigne) async {
    // ... (Cette fonction reste inchangée)
    if (!widget.userRoles.contains(roleAdminString)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Action non autorisée.")),
        );
      }
      return;
    }
    final bool confirmation = await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) {
            return AlertDialog(
              title: const Text('Confirmer la suppression'),
              content: Text(
                  "Êtes-vous sûr de vouloir supprimer définitivement l'archive : ${consigne.contenu} ? Cette action est irréversible."),
              actions: <Widget>[
                TextButton(
                  child: const Text('ANNULER'),
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('SUPPRIMER DÉFINITIVEMENT'),
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                ),
              ],
            );
          },
        ) ??
        false;

    if (confirmation) {
      try {
        widget.obsNonRealiseeControllers.remove(consigne.id)?.dispose();
        widget.obsValidationControllers.remove(consigne.id)?.dispose();
        await widget.deleteConsigneDB(consigne.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Archive "${consigne.contenu}" supprimée définitivement.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    "Erreur lors de la suppression de l'archive : ${e.toString()}")),
          );
        }
      }
    }
  }

  Widget _buildSearchBar() {
    // ... (Cette fonction reste inchangée)
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 12.0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Rechercher dans les archives...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30.0),
            borderSide: const BorderSide(color: Colors.grey),
          ),
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: widget.tranches.isEmpty
              ? const Text("Aucune tranche n'est configurée pour les archives.")
              : const Text(
                  "Veuillez sélectionner une tranche pour voir les archives."),
        ),
      );
    }

    return StreamBuilder<List<Consigne>>(
      stream: widget.getConsignesStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(
              child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.teal)));
        }
        if (snapshot.hasError) {
          return Center(
              child: Text('Erreur chargement archives: ${snapshot.error}'));
        }

        final toutesLesArchives =
            (snapshot.data ?? []).where((c) => c.estValidee).toList();

        final List<Consigne> consignesFiltrees;
        if (_searchQuery.isNotEmpty) {
          consignesFiltrees = toutesLesArchives.where((consigne) {
            final query = _searchQuery.toLowerCase();
            return consigne.contenu.toLowerCase().contains(query) ||
                (consigne.categorie?.toLowerCase().contains(query) ?? false) ||
                consigne.auteurNomPrenomCreation
                    .toLowerCase()
                    .contains(query) ||
                (consigne.commentaireValidation
                        ?.toLowerCase()
                        .contains(query) ??
                    false) ||
                // AJOUT DU NOUVEAU CHAMP À LA RECHERCHE
                (consigne.dosimetrieInfo?.toLowerCase().contains(query) ??
                    false);
          }).toList();
        } else {
          consignesFiltrees = toutesLesArchives;
        }

        return Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildBlocHeader(
                    "Archives (Consignes) - ${widget.selectedTranche}",
                    headerColor: Colors.teal),
                _buildSearchBar(),
                Expanded(
                  child: consignesFiltrees.isEmpty
                      ? Center(
                          child: Text(_searchQuery.isNotEmpty
                              ? "Aucun résultat pour '$_searchQuery'"
                              : "Aucune consigne archivée pour cette tranche."),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 80),
                          // Espace pour le FAB
                          itemCount: consignesFiltrees.length,
                          itemBuilder: (context, index) {
                            final c = consignesFiltrees[index];
                            return Card(
                                key: ValueKey("archive_${c.id}"),
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                color: Colors.green.shade50,
                                child: ListTile(
                                  leading: const Icon(
                                      Icons.check_circle_outline,
                                      color: Colors.green),
                                  title: Text(c.contenu,
                                      style: const TextStyle(
                                          decoration:
                                              TextDecoration.lineThrough)),
                                  subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            "Créée par: ${c.auteurNomPrenomCreation} (${c.roleAuteurCreation})"),
                                        if (c.categorie != null &&
                                            c.categorie!.isNotEmpty)
                                          Text("Catégorie: ${c.categorie}",
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors
                                                      .blueGrey.shade600)),
                                        if (c.enjeu != null &&
                                            c.enjeu!.isNotEmpty)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 2.0),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.shield_outlined,
                                                    color: Colors.blue.shade600,
                                                    size: 12),
                                                const SizedBox(width: 3),
                                                Text("Enjeu: ${c.enjeu}",
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: Colors
                                                            .blue.shade700)),
                                              ],
                                            ),
                                          ),
                                        if (c.estValidee &&
                                            c.dateValidation != null)
                                          Text(
                                              "Validée le: ${_formatDateSimple(c.dateValidation, showTime: true)}",
                                              style: const TextStyle(
                                                  fontSize: 11)),

                                        // --- CORRECTION FINALE APPLIQUÉE À VOTRE MISE EN PAGE ---

                                        // BLOC POUR L'OBSERVATION
                                        if (c.commentaireValidation != null &&
                                            c.commentaireValidation!.isNotEmpty)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 4.0),
                                            child: Text(
                                              // Votre format préféré
                                              "Obs: ${c.commentaireValidation}",
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.black54),
                                              // Permet au texte de passer à la ligne si besoin
                                              maxLines: 5,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),

                                        // BLOC POUR LA DOSIMÉTRIE
                                        if (c.dosimetrieInfo != null &&
                                            c.dosimetrieInfo!.isNotEmpty)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 4.0),
                                            child: Text(
                                              // Affiche le texte de la dosimétrie tel quel
                                              c.dosimetrieInfo!,
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.black54),
                                              maxLines: 5,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        // --- FIN DE LA CORRECTION ---
                                      ]),
                                  trailing:
                                      widget.userRoles.contains(roleAdminString)
                                          ? IconButton(
                                              icon: Icon(
                                                  Icons.delete_forever_outlined,
                                                  color: Colors.red.shade700),
                                              tooltip:
                                                  'Supprimer définitivement l\'archive',
                                              onPressed: () {
                                                _confirmerEtSupprimerConsigneArchivee(
                                                    c);
                                              },
                                            )
                                          : null,
                                ));
                          },
                        ),
                ),
              ],
            ),
            if (consignesFiltrees.isNotEmpty &&
                (widget.userRoles.contains(roleAdminString) ||
                    widget.userRoles.contains(roleChefDeChantierString)))
              Positioned(
                bottom: 16.0,
                right: 16.0,
                child: FloatingActionButton(
                  heroTag: 'exportExcelButton',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ExcelScreen(
                          archives: consignesFiltrees,
                          selectedTranche: widget.selectedTranche ?? 'Inconnue',
                        ),
                      ),
                    );
                  },
                  backgroundColor: Colors.green[700],
                  tooltip: 'Exporter en Excel',
                  child: const Icon(Icons.grid_on, color: Colors.white),
                ),
              ),
          ],
        );
      },
    );
  }
}
