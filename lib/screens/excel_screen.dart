// lib/screens/excel_screen.dart

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';

import '../model/consigne.dart';
import '../model/transfert.dart';
import '../model/info_chantier.dart';
import '../model/commentaire.dart';

class ExcelScreen extends StatefulWidget {
  final List<dynamic>
      archives; // Changé en dynamic pour accepter Consigne et Transfert
  final String selectedTranche;
  final String interfaceType;

  const ExcelScreen({
    super.key,
    required this.archives,
    required this.selectedTranche,
    this.interfaceType = 'consignes',
  });

  @override
  State<ExcelScreen> createState() => _ExcelScreenState();
}

class _ExcelScreenState extends State<ExcelScreen> {
  bool _isExporting = false;

  String _formatDateForExcel(DateTime? date) {
    if (date == null) return '';
    return "${date.day.toString().padLeft(2, '0')}/"
        "${date.month.toString().padLeft(2, '0')}/"
        "${date.year} "
        "${date.hour.toString().padLeft(2, '0')}:"
        "${date.minute.toString().padLeft(2, '0')}";
  }

  String _extractTotalFromDosimetrie(String? dosimetrieInfo) {
    if (dosimetrieInfo == null || !dosimetrieInfo.contains('Total:')) {
      return '';
    }
    final totalPart = dosimetrieInfo.split('Total:').last.trim();
    return totalPart.split(' mSv').first.trim();
  }

  Future<void> _showExportDialog() async {
    final prefix = widget.interfaceType == 'amcr' ? 'AMCR_' : '';
    final fileNameController = TextEditingController(
      text:
          '${prefix}Export_Archives_${widget.selectedTranche}_${DateTime.now().toIso8601String().substring(0, 10)}',
    );
    final sheetNameController =
        TextEditingController(text: widget.selectedTranche);

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Configurer l\'export Excel'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: fileNameController,
                decoration: const InputDecoration(
                    labelText: 'Nom du fichier (sans .xlsx)'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: sheetNameController,
                decoration:
                    const InputDecoration(labelText: 'Nom de la feuille'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop({
                  'fileName': fileNameController.text,
                  'sheetName': sheetNameController.text,
                });
              },
              child: const Text('Exporter'),
            ),
          ],
        );
      },
    );

    if (result != null && result['fileName']!.isNotEmpty) {
      await _exportToExcel(
          fileName: result['fileName']!, sheetName: result['sheetName']!);
    }
  }

  Future<void> _exportToExcel(
      {required String fileName, required String sheetName}) async {
    setState(() => _isExporting = true);

    try {
      final excel = Excel.createExcel();
      excel.rename(excel.getDefaultSheet()!, sheetName);
      final Sheet sheet = excel[sheetName];

      CellStyle headerStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#FFC0C0C0'),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );

      // En-têtes complets pour Consignes et Transferts
      final headers = [
        'Type',
        'Catégorie / Enjeu',
        'Contenu / Description',
        'Date émission',
        'Auteur Création',
        'Rôle Auteur',
        'Lieu Départ',
        'Lieu Arrivée',
        'Date/Heure Planifiée',
        'Heure Départ Réel',
        'Heure Arrivée Réel',
        'Validé / Lu par',
        'Date Validation / Lecture',
        'Observation / Lecteurs détaillés',
        'Dosimétrie (Détail)',
        'Total Dosimétrie (mSv)',
        'Commentaires Non-réalisation'
      ];

      for (var i = 0; i < headers.length; i++) {
        var cell =
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = TextCellValue(headers[i]);
        cell.cellStyle = headerStyle;
        sheet.setColumnAutoFit(i);
      }

      for (int i = 0; i < widget.archives.length; i++) {
        final item = widget.archives[i];
        final rowIndex = i + 1;

        String type = '';
        String categorie = '';
        String contenu = '';
        String dateEmission = '';
        String auteurCreation = '';
        String roleAuteur = '';
        String lieuDepart = '';
        String lieuArrivee = '';
        String planification = '';
        String heureDepReel = '';
        String heureArrReel = '';
        String validePar = '';
        String dateVal = '';
        String obsVal = '';
        String dosiDetail = '';
        String dosiTotal = '';
        String commsNonReal = '';

        List<Commentaire>? comments;

        if (item is Consigne) {
          type = item.categorie == "Ajout Manuel"
              ? 'Consigne (Manuelle)'
              : 'Consigne';
          categorie = [item.categorie, item.enjeu]
              .where((s) => s != null && s.isNotEmpty)
              .join(' / ');
          contenu = item.contenu;
          dateEmission = _formatDateForExcel(item.dateEmission);
          auteurCreation = item.auteurNomPrenomCreation;
          roleAuteur = item.roleAuteurCreation;
          validePar = item.nomPrenomValidation ?? '';
          dateVal = _formatDateForExcel(item.dateValidation);

          // Détail des observations de validation
          obsVal = item.commentaireValidation ?? '';

          dosiDetail = item.dosimetrieInfo ?? '';
          dosiTotal = _extractTotalFromDosimetrie(item.dosimetrieInfo);
          comments = item.commentairesNonRealisation;
        } else if (item is Transfert) {
          type = 'Transfert';
          categorie = 'Logistique';
          // Description enrichie du transfert (Contenu + Trajet)
          contenu =
              "${item.contenu} (De: ${item.lieuDepart ?? '?'} Vers: ${item.lieuArrivee ?? '?'})";
          dateEmission = _formatDateForExcel(item.dateEmission);
          auteurCreation = item.auteurNomPrenomCreation;
          roleAuteur = item.roleAuteurCreation;
          lieuDepart = item.lieuDepart ?? '';
          lieuArrivee = item.lieuArrivee ?? '';
          planification = _formatDateForExcel(item.heureDepart);
          heureDepReel = _formatDateForExcel(item.heureDepartReel);
          heureArrReel = _formatDateForExcel(item.heureArriveeReel);
          validePar = item.nomPrenomValidation ?? '';
          dateVal = _formatDateForExcel(item.dateValidation);
          obsVal = item.commentaireValidation ?? '';
          dosiDetail = item.dosimetrieInfo ?? '';
          dosiTotal = _extractTotalFromDosimetrie(item.dosimetrieInfo);
          comments = item.commentairesNonRealisation;
        } else if (item is InfoChantier) {
          type = 'Information';
          categorie = 'Communication';
          contenu = item.contenu; // Description complète de l'information
          dateEmission = _formatDateForExcel(item.dateEmission);
          auteurCreation = item.auteurNomPrenomCreation;
          roleAuteur = item.roleAuteurCreation;
          validePar = "${item.lectures.length} lecture(s)";
          // Suivi détaillé des lectures
          obsVal = item.lectures
              .map((l) =>
                  "${l.userNomPrenom} (${_formatDateForExcel(l.dateLecture)})")
              .join(' | ');
        }

        commsNonReal = comments
                ?.map((c) =>
                    "${c.texte} (par ${c.auteurNomPrenom} le ${_formatDateForExcel(c.date)})")
                .join(' \n ') ??
            '';

        final rowData = [
          type,
          categorie,
          contenu,
          dateEmission,
          auteurCreation,
          roleAuteur,
          lieuDepart,
          lieuArrivee,
          planification,
          heureDepReel,
          heureArrReel,
          validePar,
          dateVal,
          obsVal,
          dosiDetail,
          dosiTotal,
          commsNonReal
        ];

        for (var j = 0; j < rowData.length; j++) {
          sheet
              .cell(CellIndex.indexByColumnRow(
                  columnIndex: j, rowIndex: rowIndex))
              .value = TextCellValue(rowData[j].toString());
        }
      }

      final fileBytes = await excel.encode();
      if (fileBytes == null) throw Exception("Erreur génération Excel");

      await FileSaver.instance.saveFile(
        name: '$fileName.xlsx',
        bytes: Uint8List.fromList(fileBytes),
        mimeType: MimeType.microsoftExcel,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Export réussi : $fileName.xlsx')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Erreur export : $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text("Export Excel Complet"),
          backgroundColor: Colors.green[800]),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Nombre d'éléments à exporter : ${widget.archives.length}"),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: _isExporting
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Icon(Icons.download),
              label: Text(_isExporting
                  ? 'Export en cours...'
                  : 'Générer Excel complet'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  foregroundColor: Colors.white),
              onPressed: _isExporting ? null : _showExportDialog,
            ),
          ],
        ),
      ),
    );
  }
}
