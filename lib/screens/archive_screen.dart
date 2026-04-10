// lib/screens/archive_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../model/consigne.dart';
import '../model/transfert.dart';
import 'excel_screen.dart';

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
  final Stream<List<Transfert>> Function() getTransfertsStream;
  final Future<void> Function(String) deleteTransfertDB;
  final Map<String, TextEditingController> obsNonRealiseeControllersTransferts;
  final Map<String, TextEditingController> obsValidationControllersTransferts;

  const ArchiveScreen({
    super.key,
    required this.selectedTranche,
    required this.tranches,
    required this.userRoles,
    required this.getConsignesStream,
    required this.deleteConsigneDB,
    required this.obsNonRealiseeControllers,
    required this.obsValidationControllers,
    required this.getTransfertsStream,
    required this.deleteTransfertDB,
    required this.obsNonRealiseeControllersTransferts,
    required this.obsValidationControllersTransferts,
  });

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  List<Consigne> _allConsignes = [];
  List<Transfert> _allTransferts = [];
  bool _isLoading = true;

  StreamSubscription? _consignesSub;
  StreamSubscription? _transfertsSub;

  @override
  void initState() {
    super.initState();
    _setupStreams();
    _searchController.addListener(() {
      if (mounted) setState(() => _searchQuery = _searchController.text);
    });
  }

  @override
  void didUpdateWidget(ArchiveScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Si la tranche sélectionnée a changé, on réinitialise les streams et les données
    if (oldWidget.selectedTranche != widget.selectedTranche) {
      setState(() {
        _allConsignes = [];
        _allTransferts = [];
        _isLoading = true;
      });
      _setupStreams();
    }
  }

  void _setupStreams() {
    _consignesSub?.cancel();
    _transfertsSub?.cancel();

    _consignesSub = widget.getConsignesStream().listen((data) {
      if (mounted) {
        setState(() {
          _allConsignes = data;
          _isLoading = false;
        });
      }
    });

    _transfertsSub = widget.getTransfertsStream().listen((data) {
      if (mounted) {
        setState(() {
          _allTransferts = data;
          _isLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _consignesSub?.cancel();
    _transfertsSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String _formatDateSimple(DateTime? date) {
    if (date == null) return 'Date inconnue';
    return DateFormat('dd/MM/yyyy HH:mm').format(date);
  }

  String _getDateKey(DateTime date) {
    int hour = date.hour;
    DateTime adjustedDate =
        (hour < 5) ? date.subtract(const Duration(days: 1)) : date;
    String shift = (hour >= 5 && hour < 13)
        ? 'morning'
        : (hour >= 13 && hour < 21 ? 'afternoon' : 'night');
    return "${adjustedDate.year}-${adjustedDate.month.toString().padLeft(2, '0')}-${adjustedDate.day.toString().padLeft(2, '0')}-$shift";
  }

  String _formatDateAndShiftFromKey(String key) {
    List<String> parts = key.split('-');
    String shiftName = (parts[3] == 'morning')
        ? 'Matin'
        : (parts[3] == 'afternoon' ? 'Après-midi' : 'Nuit');
    return '${parts[2]}/${parts[1]}/${parts[0]} - $shiftName';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.selectedTranche == null) {
      return const Scaffold(
          body: Center(child: Text("Sélectionnez une tranche")));
    }

    if (_isLoading && _allConsignes.isEmpty && _allTransferts.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final List<dynamic> combinedList = [..._allConsignes, ..._allTransferts];
    final filteredItems = combinedList.where((item) {
      final q = _searchQuery.toLowerCase();
      final String myTranche = widget.selectedTranche?.trim() ?? "";

      if (item is Consigne) {
        // On filtre les consignes par la tranche sélectionnée
        final bool memeTranche = (item.tranche?.trim() ?? "") == myTranche;
        return item.estValidee &&
            memeTranche &&
            (item.contenu.toLowerCase().contains(q) ||
                item.auteurNomPrenomCreation.toLowerCase().contains(q));
      } else if (item is Transfert) {
        // On filtre les transferts par la tranche d'origine (isolation des archives)
        final bool estOrigine = (item.tranche?.trim() ?? "") == myTranche;
        return item.estValidee &&
            estOrigine &&
            (item.contenu.toLowerCase().contains(q) ||
                item.auteurNomPrenomCreation.toLowerCase().contains(q));
      }
      return false;
    }).toList();

    Map<String, List<dynamic>> grouped = {};
    for (var item in filteredItems) {
      DateTime? dv = (item is Consigne)
          ? item.dateValidation
          : (item as Transfert).dateValidation;
      if (dv != null) {
        String key = _getDateKey(dv);
        grouped.putIfAbsent(key, () => []).add(item);
      }
    }

    List<String> sortedKeys = grouped.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return Scaffold(
      body: Column(
        children: [
          _buildArchiveHeader(),
          _buildSearchBar(),
          Expanded(
            child: ListView.builder(
              itemCount: sortedKeys.length,
              itemBuilder: (context, index) {
                String key = sortedKeys[index];
                List<dynamic> shiftItems = grouped[key]!;

                // TRI CHRONOLOGIQUE : On trie les items du poste par heure de validation
                shiftItems.sort((a, b) {
                  DateTime? dateA = (a is Consigne)
                      ? a.dateValidation
                      : (a as Transfert).dateValidation;
                  DateTime? dateB = (b is Consigne)
                      ? b.dateValidation
                      : (b as Transfert).dateValidation;
                  if (dateA == null) return 1;
                  if (dateB == null) return -1;
                  return dateA.compareTo(dateB);
                });

                return _buildShiftGroup(key, shiftItems);
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _buildExcelButton(filteredItems),
    );
  }

  Widget _buildArchiveHeader() {
    return Container(
      color: Colors.orange.shade100,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(children: [
        Expanded(
          child: Text(
            "Archives - ${widget.selectedTranche}",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: Colors.orange.shade900,
            ),
          ),
        ),
        Text(
          _formatDateSimple(DateTime.now()),
          style: TextStyle(fontSize: 14, color: Colors.orange.shade700),
        ),
      ]),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Rechercher...',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildShiftGroup(String key, List<dynamic> items) {
    double totalDosi = 0.0;
    final regex = RegExp(r'Total:\s*(\d+(?:[,.]\d+)?)');
    for (var it in items) {
      String? dosi = (it is Consigne)
          ? it.dosimetrieInfo
          : (it as Transfert).dosimetrieInfo;
      if (dosi != null) {
        final match = regex.firstMatch(dosi);
        if (match != null) {
          totalDosi +=
              double.tryParse(match.group(1)!.replaceAll(',', '.')) ?? 0.0;
        }
      }
    }

    int nbConsignes = items.whereType<Consigne>().length;
    int nbTransferts = items.whereType<Transfert>().length;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ExpansionTile(
        shape: const Border(),
        title: Row(
          children: [
            const Icon(Icons.calendar_today_outlined,
                size: 20, color: Colors.teal),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_formatDateAndShiftFromKey(key)} (Total dosimétrie: ${totalDosi.toStringAsFixed(3)} mSv)',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$nbConsignes Consigne(s) - $nbTransferts Transfert(s)',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        children: items
            .map((it) => it is Consigne
                ? _buildConsigneItem(it)
                : _buildTransfertItem(it as Transfert))
            .toList(),
      ),
    );
  }

  Widget _buildConsigneItem(Consigne c) {
    return Container(
      decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.grey.shade200))),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.access_time, size: 20, color: Colors.grey),
            Text(
              "${c.dateValidation?.hour.toString().padLeft(2, '0')}:${c.dateValidation?.minute.toString().padLeft(2, '0')}",
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87),
            ),
          ],
        ),
        title: Text(c.contenu,
            style: const TextStyle(
                decoration: TextDecoration.lineThrough, fontSize: 15)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
                "Créé par: ${c.auteurNomPrenomCreation} (${c.roleAuteurCreation}) le ${_formatDateSimple(c.dateEmission)}",
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Text("Validé par: ${c.nomPrenomValidation}",
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.black)),
            if (c.commentaireValidation != null &&
                c.commentaireValidation!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2.0),
                child: Text("Obs: ${c.commentaireValidation}",
                    style: const TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: Colors.brown)),
              ),
            if (c.categorie != null)
              Text("Catégorie: ${c.categorie}",
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            if (c.dosimetrieInfo != null)
              Text("Dosimétrie: ${c.dosimetrieInfo}",
                  style: const TextStyle(fontSize: 12, color: Colors.blue)),
            if (c.commentairesNonRealisation != null &&
                c.commentairesNonRealisation!.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: c.commentairesNonRealisation!.map((com) {
                  return Text(
                    "Non réalisé: ${com.texte} (Par ${com.auteurNomPrenom} le ${DateFormat('dd/MM/yyyy HH:mm').format(com.date)})",
                    style: const TextStyle(fontSize: 11, color: Colors.orange),
                  );
                }).toList(),
              ),
          ],
        ),
        trailing: widget.userRoles.contains(roleAdminString)
            ? IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => widget.deleteConsigneDB(c.id))
            : null,
      ),
    );
  }

  Widget _buildTransfertItem(Transfert t) {
    return Container(
      decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.grey.shade200))),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.swap_horiz, size: 20, color: Colors.blue),
            Text(
              "${t.dateValidation?.hour.toString().padLeft(2, '0')}:${t.dateValidation?.minute.toString().padLeft(2, '0')}",
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87),
            ),
          ],
        ),
        title: Text("${t.contenu} (${t.lieuDepart} → ${t.lieuArrivee})",
            style: const TextStyle(
                decoration: TextDecoration.lineThrough, fontSize: 14)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
                "Créé par: ${t.auteurNomPrenomCreation} le ${_formatDateSimple(t.dateEmission)}",
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Text("Validé par: ${t.nomPrenomValidation}",
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.black)),
            if (t.commentaireValidation != null &&
                t.commentaireValidation!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2.0),
                child: Text("Obs: ${t.commentaireValidation}",
                    style: const TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: Colors.brown)),
              ),
            if (t.dosimetrieInfo != null)
              Text("Dosimétrie: ${t.dosimetrieInfo}",
                  style: const TextStyle(fontSize: 12, color: Colors.blue)),
            if (t.heureDepartReel != null || t.heureArriveeReel != null)
              Text(
                  "Réel: ${t.heureDepartReel?.hour.toString().padLeft(2, '0')}:${t.heureDepartReel?.minute.toString().padLeft(2, '0')} -> ${t.heureArriveeReel?.hour.toString().padLeft(2, '0')}:${t.heureArriveeReel?.minute.toString().padLeft(2, '0')}",
                  style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
            if (t.commentairesNonRealisation != null &&
                t.commentairesNonRealisation!.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: t.commentairesNonRealisation!.map((com) {
                  return Text(
                    "Non réalisé: ${com.texte} (Par ${com.auteurNomPrenom} le ${DateFormat('dd/MM/yyyy HH:mm').format(com.date)})",
                    style: const TextStyle(fontSize: 11, color: Colors.orange),
                  );
                }).toList(),
              ),
          ],
        ),
        trailing: widget.userRoles.contains(roleAdminString)
            ? IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => widget.deleteTransfertDB(t.id))
            : null,
      ),
    );
  }

  Widget? _buildExcelButton(List<dynamic> items) {
    if (!(widget.userRoles.contains(roleAdminString) ||
        widget.userRoles.contains(roleChefDeChantierString))) return null;
    return FloatingActionButton(
      backgroundColor: Colors.green[700],
      child: const Icon(Icons.grid_on, color: Colors.white),
      onPressed: () {
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => ExcelScreen(
                    archives: items,
                    selectedTranche: widget.selectedTranche!)));
      },
    );
  }
}
