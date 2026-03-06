// lib/screens/excel_screen.dart

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';

import '../model/consigne.dart';

class ExcelScreen extends StatefulWidget {
  final List<Consigne> archives;
  final String selectedTranche;

  const ExcelScreen({
    super.key,
    required this.archives,
    required this.selectedTranche,
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

  // --- NOUVELLE FONCTION POUR EXTRAIRE LE TOTAL ---
  String _extractTotalFromDosimetrie(String? dosimetrieInfo) {
    if (dosimetrieInfo == null || !dosimetrieInfo.contains('Total:')) {
      return '';
    }
    // Trouve la partie "Total: X,XXX mSv."
    final totalPart = dosimetrieInfo.split('Total:').last.trim();
    // Garde seulement le nombre (enlève " mSv.")
    return totalPart.split(' mSv').first.trim();
  }

  // --- FIN DE LA NOUVELLE FONCTION ---

  Future<void> _showExportDialog() async {
    final fileNameController = TextEditingController(
      text:
          'Export_Archives_${widget.selectedTranche}_${DateTime.now().toIso8601String().substring(0, 10)}',
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
                  labelText: 'Nom du fichier (sans .xlsx)',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: sheetNameController,
                decoration: const InputDecoration(
                  labelText: 'Nom de la feuille',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
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
        fileName: result['fileName']!,
        sheetName: result['sheetName']!,
      );
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

      // --- 1. AJOUT DE LA COLONNE "TOTAL" DANS LES EN-TÊTES ---
      final headers = [
        'Contenu de la consigne',
        'Date d\'émission',
        'Auteur',
        'Rôle de l\'auteur',
        'Catégorie',
        'Enjeu',
        'Est Prioritaire',
        'Date de Validation',
        'Commentaire de Validation',
        'Détail Dosimétrie', // Renommé pour plus de clarté
        'Total Dosimétrie (mSv)', // La nouvelle colonne
        'Historique des observations'
      ];

      for (var i = 0; i < headers.length; i++) {
        var cell =
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = TextCellValue(headers[i]);
        cell.cellStyle = headerStyle;
        sheet.setColumnAutoFit(i);
      }

      for (int i = 0; i < widget.archives.length; i++) {
        final consigne = widget.archives[i];
        final rowIndex = i + 1;
        String historiqueObs = consigne.commentairesNonRealisation
                ?.map((c) =>
                    "${c.texte} (par ${c.auteurNomPrenom} le ${_formatDateForExcel(c.date)})")
                .join('\n') ??
            '';

        // --- 2. AJOUT DES DONNÉES SÉPARÉES DANS LA LIGNE ---
        final rowData = [
          consigne.contenu,
          _formatDateForExcel(consigne.dateEmission),
          consigne.auteurNomPrenomCreation,
          consigne.roleAuteurCreation,
          consigne.categorie ?? '',
          consigne.enjeu ?? '',
          consigne.estPrioritaire ? 'Oui' : 'Non',
          _formatDateForExcel(consigne.dateValidation),
          consigne.commentaireValidation ?? '',
          consigne.dosimetrieInfo ?? '',
          // Le détail complet
          _extractTotalFromDosimetrie(consigne.dosimetrieInfo),
          // Le total extrait
          historiqueObs,
        ];

        for (var j = 0; j < rowData.length; j++) {
          sheet
                  .cell(CellIndex.indexByColumnRow(
                      columnIndex: j, rowIndex: rowIndex))
                  .value =
              TextCellValue(
                  rowData[j].toString()); // .toString() pour plus de sécurité
        }
      }

      final fileBytes = await excel.encode();

      if (fileBytes == null) {
        throw Exception("Erreur lors de la génération du fichier Excel");
      }

      await FileSaver.instance.saveFile(
        name: '$fileName.xlsx',
        bytes: Uint8List.fromList(fileBytes),
        mimeType: MimeType.microsoftExcel,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export de "$fileName.xlsx" lancé.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur lors de l'export : $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Export Excel"),
        backgroundColor: Colors.green[800],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Nombre d'archives à exporter: ${widget.archives.length}"),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: _isExporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
              label: Text(
                  _isExporting ? 'Export en cours...' : 'Exporter vers Excel'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
              ),
              onPressed: _isExporting ? null : _showExportDialog,
            ),
          ],
        ),
      ),
    );
  }
}
