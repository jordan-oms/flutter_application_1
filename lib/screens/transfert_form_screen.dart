// lib/screens/transfert_form_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../model/transfert.dart';

class TransfertFormScreen extends StatefulWidget {
  final String selectedTranche;
  final List<String> allTranches;
  final String currentUserNomPrenom;
  final String roleDisplay;
  final Transfert? transfertAEditer;
  final String interfaceType;

  const TransfertFormScreen({
    super.key,
    required this.selectedTranche,
    required this.allTranches,
    required this.currentUserNomPrenom,
    required this.roleDisplay,
    this.transfertAEditer,
    this.interfaceType = 'consignes',
  });

  @override
  State<TransfertFormScreen> createState() => _TransfertFormScreenState();
}

class _TransfertFormScreenState extends State<TransfertFormScreen> {
  final TextEditingController _transfertController = TextEditingController();
  String? _lieuDepart;
  String? _lieuArrivee;
  DateTime? _dateDepart;
  TimeOfDay? _heureDepart;
  List<String> _selectedTranchesVisibles = [];

  static const List<String> lieuxOptions = [
    'BAN-9',
    'BAN-8',
    'BAN-7',
    'TRANSIT-9',
    'TRANSIT-8',
    'TRANSIT-7',
    'AOC',
    'ATC',
    'BSI',
    'BULLE-1',
    'BULLE-2',
    'BULLE-3',
    'BULLE-4',
    'BULLE-5',
    'BULLE-6',
    'AUTRE',
  ];

  late final CollectionReference _transfertsRefGlobal;

  @override
  void initState() {
    super.initState();
    _transfertsRefGlobal = FirebaseFirestore.instance.collection(
        widget.interfaceType == 'amcr' ? 'amcr_transferts' : 'transferts');

    if (widget.transfertAEditer != null) {
      _transfertController.text = widget.transfertAEditer!.contenu;
      _lieuDepart = widget.transfertAEditer!.lieuDepart;
      _lieuArrivee = widget.transfertAEditer!.lieuArrivee;
      _dateDepart = widget.transfertAEditer!.heureDepart;
      _heureDepart = widget.transfertAEditer!.heureDepart != null
          ? TimeOfDay.fromDateTime(widget.transfertAEditer!.heureDepart!)
          : null;
      _selectedTranchesVisibles =
          List<String>.from(widget.transfertAEditer!.tranchesVisibles ?? []);
    }
  }

  @override
  void dispose() {
    _transfertController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dateDepart ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('fr', 'FR'),
    );
    if (picked != null && mounted) {
      setState(() {
        _dateDepart = picked;
      });
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _heureDepart ?? TimeOfDay.now(),
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() {
        _heureDepart = picked;
      });
    }
  }

  String _formatDateSimple(DateTime? date, {bool showTime = true}) {
    if (date == null) return 'Date inconnue';
    final String day = date.day.toString().padLeft(2, '0');
    final String month = date.month.toString().padLeft(2, '0');
    final String year = date.year.toString();
    if (showTime) {
      final String hour = date.hour.toString().padLeft(2, '0');
      final String minute = date.minute.toString().padLeft(2, '0');
      return "$day/$month/$year $hour:$minute";
    }
    return "$day/$month/$year";
  }

  Future<void> _validerEtEnregistrer() async {
    final contenu = _transfertController.text.trim();

    // Vérification des champs obligatoires
    if (_lieuDepart == null) {
      _showErrorSnackBar("Veuillez sélectionner un lieu de départ.");
      return;
    }
    if (_lieuArrivee == null) {
      _showErrorSnackBar("Veuillez sélectionner un lieu d'arrivée.");
      return;
    }
    if (_dateDepart == null) {
      _showErrorSnackBar("Veuillez sélectionner une date.");
      return;
    }
    if (_heureDepart == null) {
      _showErrorSnackBar("Veuillez sélectionner une heure.");
      return;
    }
    if (contenu.isEmpty) {
      _showErrorSnackBar("Le détail du transfert ne peut pas être vide.");
      return;
    }

    final User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      DateTime? heureDepartComplete;
      if (_dateDepart != null && _heureDepart != null) {
        heureDepartComplete = DateTime(
          _dateDepart!.year,
          _dateDepart!.month,
          _dateDepart!.day,
          _heureDepart!.hour,
          _heureDepart!.minute,
        );
      }

      if (widget.transfertAEditer != null) {
        // Modification : on crée une copie de l'objet existant avec les nouvelles valeurs
        final transfertModifie = widget.transfertAEditer!.copyWith(
          contenu: contenu,
          lieuDepart: _lieuDepart,
          lieuArrivee: _lieuArrivee,
          heureDepart: heureDepartComplete,
          tranchesVisibles: _selectedTranchesVisibles,
        );

        // On met à jour le document avec les nouvelles données tout en gardant les anciennes (commentaires, etc.)
        await _transfertsRefGlobal
            .doc(transfertModifie.id)
            .update(transfertModifie.toJson());
        // On peut aussi ajouter les infos de modification si vous avez ces champs en base
        await _transfertsRefGlobal.doc(transfertModifie.id).update({
          'modifieLe': FieldValue.serverTimestamp(),
          'modifiePar': widget.currentUserNomPrenom,
        });
      } else {
        // Création
        final nouveauTransfert = Transfert(
          id: _transfertsRefGlobal.doc().id,
          tranche: widget.selectedTranche,
          tranchesVisibles: _selectedTranchesVisibles,
          contenu: contenu,
          dateEmission: DateTime.now(),
          auteurIdCreation: currentUser.uid,
          auteurNomPrenomCreation: widget.currentUserNomPrenom,
          roleAuteurCreation: widget.roleDisplay,
          commentairesNonRealisation: [],
          lieuDepart: _lieuDepart,
          lieuArrivee: _lieuArrivee,
          heureDepart: heureDepartComplete,
        );
        await _transfertsRefGlobal
            .doc(nouveauTransfert.id)
            .set(nouveauTransfert.toJson());
      }

      if (mounted) {
        Navigator.of(context).pop(); // Retour à la liste
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.transfertAEditer != null
                ? 'Transfert modifié !'
                : 'Transfert créé !'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur : $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool estEnModeModification = widget.transfertAEditer != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(estEnModeModification
            ? 'Modifier le transfert'
            : 'Nouveau transfert'),
        backgroundColor: const Color(0xFF102A43),
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFFF1F5F9),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: Colors.blueGrey.shade100),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('Lieu de départ'),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              border:
                                  Border.all(color: Colors.blueGrey.shade300),
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.white,
                            ),
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: _lieuDepart,
                              hint: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: Text('Sélectionner...'),
                              ),
                              onChanged: (String? newValue) {
                                setState(() {
                                  _lieuDepart = newValue;
                                });
                              },
                              items: lieuxOptions.map<DropdownMenuItem<String>>(
                                (String value) {
                                  return DropdownMenuItem<String>(
                                    value: value,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12),
                                      child: Text(value),
                                    ),
                                  );
                                },
                              ).toList(),
                              underline: const SizedBox(),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('Lieu d\'arrivée'),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              border:
                                  Border.all(color: Colors.blueGrey.shade300),
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.white,
                            ),
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: _lieuArrivee,
                              hint: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: Text('Sélectionner...'),
                              ),
                              onChanged: (String? newValue) {
                                setState(() {
                                  _lieuArrivee = newValue;
                                });
                              },
                              items: lieuxOptions.map<DropdownMenuItem<String>>(
                                (String value) {
                                  return DropdownMenuItem<String>(
                                    value: value,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12),
                                      child: Text(value),
                                    ),
                                  );
                                },
                              ).toList(),
                              underline: const SizedBox(),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _buildFieldLabel('Planification'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildPlanningTile(
                        icon: Icons.calendar_today_outlined,
                        label: 'Date',
                        value: _dateDepart != null
                            ? _formatDateSimple(_dateDepart!, showTime: false)
                            : 'Non définie',
                        color: const Color(0xFF0B4F8C),
                        onTap: () => _selectDate(context),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildPlanningTile(
                        icon: Icons.access_time_rounded,
                        label: 'Heure',
                        value: _heureDepart != null
                            ? _heureDepart!.format(context)
                            : 'Non définie',
                        color: const Color(0xFF0E7490),
                        onTap: () => _selectTime(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _buildFieldLabel('Visibilité (Portefeuille)'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: widget.allTranches
                      .where((t) => t != widget.selectedTranche)
                      .map((t) {
                    // On s'assure que la comparaison est stricte pour éviter les faux positifs
                    final isSelected = _selectedTranchesVisibles.contains(t);
                    return FilterChip(
                      label: Text(t),
                      selected: isSelected,
                      onSelected: (bool selected) {
                        setState(() {
                          if (selected) {
                            if (!_selectedTranchesVisibles.contains(t)) {
                              _selectedTranchesVisibles.add(t);
                            }
                          } else {
                            _selectedTranchesVisibles.remove(t);
                          }
                        });
                      },
                      selectedColor: const Color(0xFF102A43).withOpacity(0.2),
                      checkmarkColor: const Color(0xFF102A43),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),
                _buildFieldLabel('Détail du transfert'),
                const SizedBox(height: 8),
                TextField(
                  controller: _transfertController,
                  minLines: 4,
                  maxLines: 8,
                  decoration: _buildInputDecoration(
                    'Décrire précisément le transfert...',
                    Icons.description_outlined,
                  ),
                ),
                const SizedBox(height: 30),
                ElevatedButton.icon(
                  onPressed: _validerEtEnregistrer,
                  icon: Icon(estEnModeModification
                      ? Icons.save_rounded
                      : Icons.add_task_rounded),
                  label: Text(estEnModeModification
                      ? 'Enregistrer les modifications'
                      : 'Valider le transfert'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF102A43),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.blueGrey.shade800),
    );
  }

  InputDecoration _buildInputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.blueGrey.shade100),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.blueGrey.shade100),
      ),
    );
  }

  Widget _buildPlanningTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.blueGrey.shade100),
        ),
        child: Row(
          children: [
            Container(
              height: 42,
              width: 42,
              decoration: BoxDecoration(
                color: color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 12, color: Colors.blueGrey.shade600)),
                  Text(value,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF102A43))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange.shade800,
      ),
    );
  }
}
