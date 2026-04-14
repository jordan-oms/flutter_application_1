// lib/screens/dosimetrie_dialog.dart

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../model/consigne.dart';

// Formatter décimal avec virgule, nombre de décimales et valeur max
class DecimalMaskFormatter extends TextInputFormatter {
  final int decimalPlaces;
  final int maxIntegerValue;

  DecimalMaskFormatter({
    this.decimalPlaces = 3,
    this.maxIntegerValue = 9,
  });

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.isNotEmpty) {
      final double valueAsNumber =
          (double.tryParse(digits) ?? 0.0) / (pow(10, decimalPlaces));
      if (valueAsNumber >= (maxIntegerValue + 1)) {
        return oldValue;
      }
    }

    // Suppression des zéros en tête
    while (digits.length > 1 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }

    String newText;

    if (digits.length > decimalPlaces) {
      final int integerPartLength = digits.length - decimalPlaces;
      final String integerPart = digits.substring(0, integerPartLength);
      final String decimalPart = digits.substring(integerPartLength);
      newText = '$integerPart,$decimalPart';
    } else {
      newText = '0,${digits.padLeft(decimalPlaces, '0')}';
    }

    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}

// Widget de saisie d'une ligne de dosimétrie (dose seule)
class _DosimetrieSaisieItem extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onRemove;

  const _DosimetrieSaisieItem({
    required this.controller,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            textAlign: TextAlign.right,
            keyboardType: TextInputType.number,
            inputFormatters: [
              DecimalMaskFormatter(decimalPlaces: 3, maxIntegerValue: 9),
            ],
            decoration: const InputDecoration(
              labelText: 'Dose (mSv)',
              hintText: '0,000',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
          onPressed: onRemove,
        ),
      ],
    );
  }
}

// Dialogue principal
class DosimetrieDialog extends StatefulWidget {
  final Consigne consigneAValider;
  final String commentaireInitial;
  final String currentUserUid;
  final Function(Consigne) onUpdateConsigne;

  const DosimetrieDialog({
    super.key,
    required this.consigneAValider,
    required this.commentaireInitial,
    required this.currentUserUid,
    required this.onUpdateConsigne,
  });

  @override
  State<DosimetrieDialog> createState() => _DosimetrieDialogState();
}

class _DosimetrieDialogState extends State<DosimetrieDialog> {
  // Liste simple de contrôleurs
  final List<TextEditingController> _doseControllers = [];
  double _totalDose = 0.0;
  final NumberFormat _formatter = NumberFormat("0.000", "fr_FR");

  @override
  void initState() {
    super.initState();
    _ajouterNouvelleSaisie();
  }

  @override
  void dispose() {
    for (final controller in _doseControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _ajouterNouvelleSaisie() {
    final newController = TextEditingController(text: '0,000');
    newController.addListener(_calculerTotal);
    setState(() {
      _doseControllers.add(newController);
    });
    _calculerTotal();
  }

  void _supprimerSaisie(int index) {
    if (_doseControllers.length <= 1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Vous ne pouvez pas supprimer la dernière ligne."),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    _doseControllers[index].dispose();
    setState(() {
      _doseControllers.removeAt(index);
      _calculerTotal();
    });
  }

  void _calculerTotal() {
    double total = 0.0;
    for (final controller in _doseControllers) {
      final textValue = controller.text.replaceAll(',', '.');
      final dose = double.tryParse(textValue) ?? 0.0;
      total += dose;
    }
    setState(() {
      _totalDose = total;
    });
  }

  void _enregistrerDosimetrie() {
    if (_totalDose == 0.0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text("Veuillez saisir au moins une valeur de dose non nulle."),
          ),
        );
      }
      return;
    }

    final List<String> dosesSaisies =
        _doseControllers.map((c) => c.text.trim()).toList();

    final String infosDosimetrie =
        "Dosimétrie : ${dosesSaisies.join(' mSv + ')} mSv. "
        "Total: ${_formatter.format(_totalDose)} mSv.";

    final Consigne consigneFinale = widget.consigneAValider.copyWith(
      estValidee: true,
      dateValidation: DateTime.now(),
      idAuteurValidation: widget.currentUserUid,
      estNonRealiseeEffectivement: false,
      commentaireValidation: widget.commentaireInitial,
      clearCommentaireValidation: widget.commentaireInitial.isEmpty,
      dosimetrieInfo: infosDosimetrie,
    );

    widget.onUpdateConsigne(consigneFinale);

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Étape Finale : Dosimétrie'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListView.builder(
              shrinkWrap: true,
              itemCount: _doseControllers.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: _DosimetrieSaisieItem(
                    controller: _doseControllers[index],
                    onRemove: () => _supprimerSaisie(index),
                  ),
                );
              },
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text("Ajouter une dosimétrie"),
              onPressed: _ajouterNouvelleSaisie,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(40),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "TOTAL DE DOSE :",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  "${_formatter.format(_totalDose)} mSv",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: <Widget>[
        ElevatedButton(
          onPressed: _enregistrerDosimetrie,
          child: const Text('ENREGISTRER LA DOSIMÉTRIE'),
        ),
      ],
    );
  }
}
