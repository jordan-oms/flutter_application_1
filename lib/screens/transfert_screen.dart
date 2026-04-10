// lib/screens/transfert_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../model/commentaire.dart';
import '../model/transfert.dart';
import 'transfert_form_screen.dart';

const String roleAdminString = "administrateur";
const String roleChefDeChantierString = "chef_de_chantier";
const String roleChefEquipeString = "chef_equipe";
const String roleIntervenantString = "intervenant";

class _TransfertsCache {
  List<Transfert>? _lastList;

  bool hasChanged(List<Transfert> newList) {
    if (_lastList == null) {
      _lastList = newList;
      return true;
    }

    if (_lastList!.length != newList.length) {
      _lastList = newList;
      return true;
    }

    for (int i = 0; i < _lastList!.length; i++) {
      final oldC = _lastList![i];
      final newC = newList[i];

      if (oldC.id != newC.id ||
          oldC.estValidee != newC.estValidee ||
          oldC.contenu != newC.contenu ||
          oldC.lieuDepart != newC.lieuDepart ||
          oldC.lieuArrivee != newC.lieuArrivee ||
          oldC.heureDepart != newC.heureDepart ||
          oldC.commentairesNonRealisation?.length !=
              newC.commentairesNonRealisation?.length ||
          oldC.dosimetrieInfo != newC.dosimetrieInfo) {
        _lastList = newList;
        return true;
      }
    }

    return false;
  }

  void clear() {
    _lastList = null;
  }
}

class TransfertScreen extends StatefulWidget {
  final String selectedTranche;
  final List<String> allTranches;
  final List<String> userRoles;
  final String currentUserNomPrenom;
  final String roleDisplay;

  const TransfertScreen({
    super.key,
    required this.selectedTranche,
    required this.allTranches,
    required this.userRoles,
    required this.currentUserNomPrenom,
    required this.roleDisplay,
  });

  @override
  State<TransfertScreen> createState() => _TransfertScreenState();
}

class _TransfertScreenState extends State<TransfertScreen> {
  final _TransfertsCache _transfertsCache = _TransfertsCache();

  String? _selectedTranche;

  final TextEditingController _observationValidationDialogController =
      TextEditingController();

  final CollectionReference _transfertsRefGlobal =
      FirebaseFirestore.instance.collection('transferts');

  final Map<String, TextEditingController> _obsNonRealiseeControllers = {};
  final Map<String, TextEditingController> _obsValidationControllers = {};

  @override
  void initState() {
    super.initState();
    _selectedTranche = widget.selectedTranche;
  }

  @override
  void didUpdateWidget(covariant TransfertScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTranche != widget.selectedTranche) {
      setState(() {
        _selectedTranche = widget.selectedTranche;
        _transfertsCache.clear();
      });
    }
  }

  @override
  void dispose() {
    _obsNonRealiseeControllers.forEach((_, controller) => controller.dispose());
    _obsNonRealiseeControllers.clear();

    _obsValidationControllers.forEach((_, controller) => controller.dispose());
    _obsValidationControllers.clear();

    _observationValidationDialogController.dispose();
    super.dispose();
  }

  void _presenterAjoutTransfert() {
    if (_selectedTranche == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TransfertFormScreen(
          selectedTranche: _selectedTranche!,
          allTranches: widget.allTranches,
          currentUserNomPrenom: widget.currentUserNomPrenom,
          roleDisplay: widget.roleDisplay,
        ),
      ),
    );
  }

  void _presenterModificationTransfert(Transfert transfert) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TransfertFormScreen(
          selectedTranche: _selectedTranche!,
          allTranches: widget.allTranches,
          currentUserNomPrenom: widget.currentUserNomPrenom,
          roleDisplay: widget.roleDisplay,
          transfertAEditer: transfert,
        ),
      ),
    );
  }

  void _confirmerSuppressionTransfert(Transfert transfert) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirmer la suppression'),
          content: Text(
            'Êtes-vous sûr de vouloir supprimer le transfert : "${transfert.contenu}" ?',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Annuler'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Supprimer'),
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                try {
                  await _transfertsRefGlobal.doc(transfert.id).delete();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Transfert supprimé avec succès.'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Erreur lors de la suppression : $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  Stream<List<Transfert>> getTransfertsStream() {
    if (_selectedTranche == null) {
      return Stream.value([]);
    }

    return _transfertsRefGlobal
        .where(Filter.or(
          Filter('tranche', isEqualTo: _selectedTranche),
          Filter('tranchesVisibles', arrayContains: _selectedTranche),
        ))
        .orderBy('heureDepart', descending: false)
        .orderBy('dateEmission', descending: false)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) {
            try {
              return Transfert.fromJson(doc.data() as Map<String, dynamic>);
            } catch (e) {
              debugPrint("Erreur de parsing d'un transfert: $e");
              return null;
            }
          })
          .whereType<Transfert>()
          .toList();
    });
  }

  Future<void> _updateTransfertDB(Transfert transfert) async {
    try {
      await _transfertsRefGlobal.doc(transfert.id).update({
        'estValidee': transfert.estValidee,
        'dateValidation': transfert.dateValidation != null
            ? Timestamp.fromDate(transfert.dateValidation!)
            : null,
        'commentaireValidation': transfert.commentaireValidation,
        'idAuteurValidation': transfert.idAuteurValidation,
        'nomPrenomValidation': transfert.nomPrenomValidation,
        'estNonRealiseeEffectivement': transfert.estNonRealiseeEffectivement,
        'commentairesNonRealisation': transfert.commentairesNonRealisation
            ?.map((c) => c.toJson())
            .toList(),
        'heureDepartReel': transfert.heureDepartReel,
        'heureArriveeReel': transfert.heureArriveeReel,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur de mise à jour du transfert: $e")),
        );
      }
    }
  }

  void _presenterValidationTransfert(
    Transfert transfert,
    bool estValideeMaintenant,
  ) {
    if (estValideeMaintenant) {
      _presenterDialogObservationValidation(transfert);
    } else {
      final Transfert transfertMiseAJour = transfert.copyWith(
        estValidee: false,
        clearDateValidation: true,
        clearCommentaireValidation: true,
        clearIdAuteurValidation: true,
        clearNomPrenomValidation: true,
      );
      _updateTransfertDB(transfertMiseAJour);
    }
  }

  Future<void> _presenterDialogObservationValidation(
    Transfert transfertAValider,
  ) async {
    String initialComment = "";
    if (transfertAValider.idAuteurValidation ==
            FirebaseAuth.instance.currentUser?.uid &&
        transfertAValider.commentaireValidation != null) {
      initialComment = transfertAValider.commentaireValidation!;
    }

    _observationValidationDialogController.text = initialComment;

    DateTime? selectedHeureDepartReel = transfertAValider.heureDepartReel;
    DateTime? selectedHeureArriveeReel = transfertAValider.heureArriveeReel;

    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return AlertDialog(
              title: const Text('Validation du transfert'),
              content: SingleChildScrollView(
                child: ListBody(
                  children: <Widget>[
                    Text(
                      'Veuillez saisir une observation pour le transfert : "${transfertAValider.contenu}"',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _observationValidationDialogController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Saisir votre observation ici (optionnel)...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.green.shade50,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Heure de départ réelle',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade700,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            selectedHeureDepartReel != null
                                ? _formatDateSimple(
                                    selectedHeureDepartReel,
                                    showTime: true,
                                  )
                                : 'Non sélectionnée',
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.green.shade900,
                                    ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final TimeOfDay? picked = await showTimePicker(
                                  context: context,
                                  initialTime: selectedHeureDepartReel != null
                                      ? TimeOfDay.fromDateTime(
                                          selectedHeureDepartReel!)
                                      : TimeOfDay.now(),
                                  builder:
                                      (BuildContext context, Widget? child) {
                                    return MediaQuery(
                                      data: MediaQuery.of(context).copyWith(
                                          alwaysUse24HourFormat: true),
                                      child: child!,
                                    );
                                  },
                                );
                                if (picked != null) {
                                  final now = DateTime.now();
                                  final selectedDateTime = DateTime(
                                    now.year,
                                    now.month,
                                    now.day,
                                    picked.hour,
                                    picked.minute,
                                  );
                                  setModalState(() {
                                    selectedHeureDepartReel = selectedDateTime;
                                  });
                                }
                              },
                              icon: const Icon(Icons.access_time),
                              label: const Text('Sélectionner'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade600,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.orange.shade50,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Heure d'arrivée réelle",
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade700,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            selectedHeureArriveeReel != null
                                ? _formatDateSimple(
                                    selectedHeureArriveeReel,
                                    showTime: true,
                                  )
                                : 'Non sélectionnée',
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.orange.shade900,
                                    ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final TimeOfDay? picked = await showTimePicker(
                                  context: context,
                                  initialTime: selectedHeureArriveeReel != null
                                      ? TimeOfDay.fromDateTime(
                                          selectedHeureArriveeReel!)
                                      : TimeOfDay.now(),
                                  builder:
                                      (BuildContext context, Widget? child) {
                                    return MediaQuery(
                                      data: MediaQuery.of(context).copyWith(
                                          alwaysUse24HourFormat: true),
                                      child: child!,
                                    );
                                  },
                                );
                                if (picked != null) {
                                  final now = DateTime.now();
                                  final selectedDateTime = DateTime(
                                    now.year,
                                    now.month,
                                    now.day,
                                    picked.hour,
                                    picked.minute,
                                  );
                                  setModalState(() {
                                    selectedHeureArriveeReel = selectedDateTime;
                                  });
                                }
                              },
                              icon: const Icon(Icons.access_time),
                              label: const Text('Sélectionner'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange.shade600,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('ANNULER'),
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    _observationValidationDialogController.clear();
                  },
                ),
                ElevatedButton(
                  child: const Text('VALIDER'),
                  onPressed: () {
                    if (selectedHeureDepartReel == null ||
                        selectedHeureArriveeReel == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              "L'heure de départ et d'arrivée réelle sont obligatoires pour valider."),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    final String observationTexte =
                        _observationValidationDialogController.text.trim();

                    String commentaireAvecAuteur = "";
                    if (observationTexte.isNotEmpty) {
                      commentaireAvecAuteur = observationTexte;
                    }

                    Navigator.of(dialogContext).pop();
                    _observationValidationDialogController.clear();

                    final transfertMisAJour = transfertAValider.copyWith(
                      estValidee: true,
                      dateValidation: DateTime.now(),
                      idAuteurValidation:
                          FirebaseAuth.instance.currentUser!.uid,
                      nomPrenomValidation: widget.currentUserNomPrenom,
                      commentaireValidation: commentaireAvecAuteur.isNotEmpty
                          ? commentaireAvecAuteur
                          : null,
                      heureDepartReel: selectedHeureDepartReel,
                      heureArriveeReel: selectedHeureArriveeReel,
                    );

                    _updateTransfertDB(transfertMisAJour);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _enregistrerObservationNonRealisation(
    Transfert transfert,
    String texteNouvelleObservation,
  ) async {
    if (texteNouvelleObservation.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("L'observation ne peut pas être vide."),
          ),
        );
      }
      return;
    }

    final nouveauCommentaire = Commentaire(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      texte: texteNouvelleObservation,
      date: DateTime.now(),
      auteurId: FirebaseAuth.instance.currentUser!.uid,
      auteurNomPrenom: widget.currentUserNomPrenom,
      roleAuteur: widget.roleDisplay,
    );

    final List<Commentaire> commentairesActuels =
        List<Commentaire>.from(transfert.commentairesNonRealisation ?? []);
    commentairesActuels.add(nouveauCommentaire);

    final transfertMiseAJour = transfert.copyWith(
      commentairesNonRealisation: commentairesActuels,
      estValidee: false,
      dateValidation: null,
      clearCommentaireValidation: true,
      idAuteurValidation: null,
      estNonRealiseeEffectivement: true,
    );

    await _updateTransfertDB(transfertMiseAJour);
    _obsNonRealiseeControllers[transfert.id]?.clear();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Observation de non-réalisation ajoutée."),
        ),
      );
    }
  }

  Future<void> _enregistrerObservationValidation(
    Transfert transfert,
    String texteObservation,
  ) async {
    if (!transfert.estValidee ||
        transfert.idAuteurValidation !=
            FirebaseAuth.instance.currentUser?.uid) {
      if (mounted &&
          transfert.idAuteurValidation !=
              FirebaseAuth.instance.currentUser?.uid &&
          transfert.estValidee) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Vous ne pouvez modifier que vos propres observations de validation.",
            ),
          ),
        );
      }
      return;
    }

    final String texteCommentaireActuelSeul =
        transfert.commentaireValidation?.split('\n-').first.trim() ?? "";

    if (texteObservation == texteCommentaireActuelSeul) return;

    String commentaireFinalAvecAuteur = "";
    if (texteObservation.isNotEmpty) {
      commentaireFinalAvecAuteur =
          "$texteObservation\n- ${widget.currentUserNomPrenom} (${widget.roleDisplay}) le ${_formatDateSimple(DateTime.now(), showTime: true)}";
    }

    final transfertMiseAJour = transfert.copyWith(
      commentaireValidation: commentaireFinalAvecAuteur.isNotEmpty
          ? commentaireFinalAvecAuteur
          : null,
      clearCommentaireValidation: commentaireFinalAvecAuteur.isEmpty,
    );

    await _updateTransfertDB(transfertMiseAJour);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _obsValidationControllers.containsKey(transfert.id)) {
        _obsValidationControllers[transfert.id]!.text = texteObservation;
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            texteObservation.isNotEmpty
                ? "Observation de validation mise à jour."
                : "Observation de validation supprimée.",
          ),
        ),
      );
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

  Widget _buildBlocHeader(
    String title, {
    Color headerColor = Colors.purple,
  }) {
    // Si c'est une MaterialColor on utilise les shades, sinon on joue sur l'opacité
    final Color bgColor = headerColor is MaterialColor
        ? headerColor.shade100
        : headerColor.withOpacity(0.15);
    final Color textColor =
        headerColor is MaterialColor ? headerColor.shade900 : headerColor;
    final Color dateColor = headerColor is MaterialColor
        ? headerColor.shade700
        : headerColor.withOpacity(0.7);

    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: textColor,
              ),
            ),
          ),
          Text(
            _formatDateSimple(DateTime.now(), showTime: false),
            style: TextStyle(fontSize: 14, color: dateColor),
          ),
        ],
      ),
    );
  }

  Widget _buildTransfertsList(List<Transfert> transferts) {
    if (_selectedTranche == null) {
      return const Center(child: Text("Veuillez sélectionner une tranche."));
    }

    if (transferts.isEmpty) {
      return const Center(
        child: Text("Aucun transfert actif pour cette tranche."),
      );
    }

    for (final t in transferts) {
      _obsNonRealiseeControllers.putIfAbsent(
        t.id,
        () => TextEditingController(),
      );

      _obsValidationControllers.putIfAbsent(
        t.id,
        () => TextEditingController(
          text: t.commentaireValidation?.split('\n-').first.trim() ?? "",
        ),
      );
    }

    final bool peutAgirSurTransfert =
        (widget.userRoles.contains(roleAdminString) ||
                widget.userRoles.contains(roleChefDeChantierString) ||
                widget.userRoles.contains(roleChefEquipeString) ||
                widget.userRoles.contains(roleIntervenantString)) &&
            FirebaseAuth.instance.currentUser != null;

    final bool peutModifierTransfert =
        (widget.userRoles.contains(roleAdminString) ||
                widget.userRoles.contains(roleChefDeChantierString)) &&
            FirebaseAuth.instance.currentUser != null;

    final bool peutSupprimerTransfertNonValidee =
        (widget.userRoles.contains(roleAdminString) ||
                widget.userRoles.contains(roleChefDeChantierString)) &&
            FirebaseAuth.instance.currentUser != null;

    return RepaintBoundary(
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: transferts.length,
        itemBuilder: (context, index) {
          final t = transferts[index];

          // SEULE LA TRANCHE D'ORIGINE PEUT VALIDER (Mode lecture seule pour le portefeuille)
          final bool peutValider =
              peutAgirSurTransfert && (t.tranche == _selectedTranche);

          return TransfertItemWidget(
            transfert: t,
            currentTranche: _selectedTranche!,
            peutAgirSurTransfert: peutValider,
            peutModifierTransfert:
                peutModifierTransfert && (t.tranche == _selectedTranche),
            peutSupprimerTransfertNonValidee:
                peutSupprimerTransfertNonValidee &&
                    (t.tranche == _selectedTranche),
            obsNonRealiseeController: _obsNonRealiseeControllers[t.id]!,
            obsValidationController: _obsValidationControllers[t.id]!,
            onValidation: _presenterValidationTransfert,
            onModification: _presenterModificationTransfert,
            onSuppression: _confirmerSuppressionTransfert,
            onEnregistrerObsNonRealisation:
                _enregistrerObservationNonRealisation,
            onEnregistrerObsValidation: _enregistrerObservationValidation,
            formatDate: _formatDateSimple,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedTranche == null) {
      return const Scaffold(
        body: Center(child: Text("Aucune tranche sélectionnée.")),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_transfert_nouveau',
        onPressed: _presenterAjoutTransfert,
        backgroundColor: const Color(0xFF102A43),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nouveau'),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildBlocHeader(
              "Transferts - $_selectedTranche",
              headerColor: const Color(0xFF102A43),
            ),
            _TransfertsStreamBuilder(
              selectedTranche: _selectedTranche!,
              getTransfertsStream: getTransfertsStream,
              buildTransfertsList: _buildTransfertsList,
              cache: _transfertsCache,
            ),
          ],
        ),
      ),
    );
  }
}

class TransfertItemWidget extends StatefulWidget {
  final Transfert transfert;
  final String currentTranche;
  final bool peutAgirSurTransfert;
  final bool peutModifierTransfert;
  final bool peutSupprimerTransfertNonValidee;
  final TextEditingController obsNonRealiseeController;
  final TextEditingController obsValidationController;
  final Function(Transfert, bool) onValidation;
  final Function(Transfert) onModification;
  final Function(Transfert) onSuppression;
  final Function(Transfert, String) onEnregistrerObsNonRealisation;
  final Function(Transfert, String) onEnregistrerObsValidation;
  final String Function(DateTime?, {bool showTime}) formatDate;

  const TransfertItemWidget({
    super.key,
    required this.transfert,
    required this.currentTranche,
    required this.peutAgirSurTransfert,
    required this.peutModifierTransfert,
    required this.peutSupprimerTransfertNonValidee,
    required this.obsNonRealiseeController,
    required this.obsValidationController,
    required this.onValidation,
    required this.onModification,
    required this.onSuppression,
    required this.onEnregistrerObsNonRealisation,
    required this.onEnregistrerObsValidation,
    required this.formatDate,
  });

  @override
  State<TransfertItemWidget> createState() => _TransfertItemWidgetState();
}

class _TransfertItemWidgetState extends State<TransfertItemWidget>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = widget.transfert;

    return Card(
      key: ValueKey(t.id),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: t.estValidee ? Colors.green.shade50 : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color:
              t.estValidee ? Colors.green.shade100 : Colors.blueGrey.shade100,
        ),
      ),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: widget.peutAgirSurTransfert
                      ? Checkbox(
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          value: t.estValidee,
                          onChanged: (val) {
                            if (val != null) {
                              widget.onValidation(t, val);
                            }
                          },
                        )
                      : Icon(
                          t.estValidee
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: t.estValidee ? Colors.green : Colors.grey,
                          size: 20,
                        ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        runSpacing: 6,
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF2FF),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              t.estValidee ? 'Validé' : 'À traiter',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: t.estValidee
                                    ? Colors.green.shade800
                                    : const Color(0xFF0B4F8C),
                              ),
                            ),
                          ),
                          if (t.lieuDepart != null && t.lieuDepart!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: Colors.blue.shade100),
                              ),
                              child: Text(
                                t.lieuArrivee != null &&
                                        t.lieuArrivee!.isNotEmpty
                                    ? "${t.lieuDepart} → ${t.lieuArrivee}"
                                    : t.lieuDepart!,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blue.shade800,
                                ),
                              ),
                            ),
                          if (t.tranche != widget.currentTranche)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(999),
                                border:
                                    Border.all(color: Colors.amber.shade200),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.source_outlined,
                                      size: 14, color: Colors.amber.shade900),
                                  const SizedBox(width: 4),
                                  Text(
                                    "Origine: ${t.tranche}",
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.amber.shade900,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (t.tranchesVisibles != null &&
                              t.tranchesVisibles!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.purple.shade50,
                                borderRadius: BorderRadius.circular(999),
                                border:
                                    Border.all(color: Colors.purple.shade100),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.account_balance_wallet_outlined,
                                      size: 14, color: Colors.purple.shade800),
                                  const SizedBox(width: 4),
                                  // Flexible permet au texte de se réduire si l'écran est trop petit
                                  Flexible(
                                    child: Text(
                                      "Portefeuille: ${t.tranchesVisibles!.join(', ')}",
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.purple.shade800,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t.contenu,
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          color: t.estValidee
                              ? Colors.grey.shade700
                              : const Color(0xFF102A43),
                          decoration:
                              t.estValidee ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Créé par ${t.auteurNomPrenomCreation} (${t.roleAuteurCreation}) le ${widget.formatDate(t.dateEmission, showTime: true)}",
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blueGrey.shade600,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      if (t.heureDepart != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          "Planifié : ${widget.formatDate(t.heureDepart, showTime: true)}",
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      if (t.heureDepartReel != null ||
                          t.heureArriveeReel != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          "Réel : départ ${t.heureDepartReel != null ? widget.formatDate(t.heureDepartReel, showTime: true) : 'N/A'} - arrivée ${t.heureArriveeReel != null ? widget.formatDate(t.heureArriveeReel, showTime: true) : 'N/A'}",
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.teal.shade700,
                          ),
                        ),
                      ],
                      if (t.estValidee) ...[
                        const SizedBox(height: 4),
                        Text(
                          "Validé par ${t.nomPrenomValidation ?? 'Inconnu'} le ${widget.formatDate(t.dateValidation, showTime: true)}",
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.peutModifierTransfert && !t.estValidee)
                      IconButton(
                        icon: const Icon(
                          Icons.edit,
                          size: 18,
                          color: Colors.blue,
                        ),
                        tooltip: "Modifier",
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        onPressed: () => widget.onModification(t),
                      ),
                    if (widget.peutSupprimerTransfertNonValidee &&
                        !t.estValidee)
                      IconButton(
                        icon: const Icon(
                          Icons.delete,
                          size: 18,
                          color: Colors.red,
                        ),
                        tooltip: "Supprimer",
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        onPressed: () => widget.onSuppression(t),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (!t.estValidee && widget.peutAgirSurTransfert)
              _buildChampObservation(
                context: context,
                controller: widget.obsNonRealiseeController,
                label: "Observation (si non réalisée)",
                hint: "Raison de la non réalisation...",
                onSave: (texte) {
                  widget.onEnregistrerObsNonRealisation(t, texte);
                },
                backgroundColor: Colors.orange.shade50,
                iconColor: Colors.orange.shade800,
              ),
            if (t.commentairesNonRealisation != null &&
                t.commentairesNonRealisation!.isNotEmpty)
              _buildChampObservationDeroulant(
                context: context,
                commentaires: t.commentairesNonRealisation!,
                label: "Observations précédentes",
                backgroundColor: Colors.orange.shade100,
                iconColor: Colors.orange.shade800,
              ),
            if (t.estValidee && widget.peutAgirSurTransfert)
              _buildChampObservation(
                context: context,
                controller: widget.obsValidationController,
                label: "Observation après validation",
                hint: "Ajouter un commentaire...",
                onSave: (texte) {
                  widget.onEnregistrerObsValidation(t, texte);
                },
                backgroundColor: Colors.green.shade50,
                iconColor: Colors.green.shade800,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChampObservation({
    required BuildContext context,
    required TextEditingController controller,
    required String label,
    required String hint,
    required Function(String) onSave,
    Color backgroundColor = Colors.white,
    Color iconColor = Colors.grey,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            maxLines: null,
            minLines: 1,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
              filled: true,
              fillColor: backgroundColor,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade400),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Theme.of(context).primaryColor,
                  width: 1.4,
                ),
              ),
              suffixIconConstraints:
                  const BoxConstraints(minHeight: 32, minWidth: 32),
              suffixIcon: IconButton(
                icon: Icon(
                  Icons.save_alt_outlined,
                  color: iconColor,
                  size: 19,
                ),
                tooltip: "Enregistrer l'observation",
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  onSave(controller.text.trim());
                  FocusScope.of(context).unfocus();
                },
              ),
            ),
            onSubmitted: (text) {
              onSave(text.trim());
            },
          ),
        ],
      ),
    );
  }

  Widget _buildChampObservationDeroulant({
    required BuildContext context,
    required List<Commentaire> commentaires,
    required String label,
    Color backgroundColor = Colors.white,
    Color iconColor = Colors.grey,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: iconColor,
          ),
        ),
        children: commentaires.map((comment) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comment.texte,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "Par ${comment.auteurNomPrenom} le ${DateFormat('dd/MM/yyyy HH:mm').format(comment.date)}",
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _TransfertsStreamBuilder extends StatefulWidget {
  final String selectedTranche;
  final Stream<List<Transfert>> Function() getTransfertsStream;
  final Widget Function(List<Transfert>) buildTransfertsList;
  final _TransfertsCache cache;

  const _TransfertsStreamBuilder({
    required this.selectedTranche,
    required this.getTransfertsStream,
    required this.buildTransfertsList,
    required this.cache,
  });

  @override
  State<_TransfertsStreamBuilder> createState() =>
      _TransfertsStreamBuilderState();
}

class _TransfertsStreamBuilderState extends State<_TransfertsStreamBuilder> {
  late Stream<List<Transfert>> _filteredStream;

  @override
  void initState() {
    super.initState();
    _filteredStream = widget.getTransfertsStream().where((newList) {
      return widget.cache.hasChanged(newList);
    });
  }

  @override
  void didUpdateWidget(covariant _TransfertsStreamBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTranche != widget.selectedTranche) {
      widget.cache.clear();
      _filteredStream = widget.getTransfertsStream().where((newList) {
        return widget.cache.hasChanged(newList);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Transfert>>(
      stream: _filteredStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Erreur: ${snapshot.error}'));
        }

        final tousLesTransferts = snapshot.data ?? [];
        final transfertsActives = tousLesTransferts
            .where((transfert) => !transfert.estValidee)
            .toList();
        if (transfertsActives.isEmpty) {
          return const Center(
            child: Text("Aucun transfert actif pour cette tranche."),
          );
        }
        return widget.buildTransfertsList(transfertsActives);
      },
    );
  }
}
