import 'package:flutter/material.dart';
import '../model/consigne.dart';

class ConsigneList extends StatelessWidget {
  final List<Consigne> consignes;
  final void Function(String) onValider;
  final void Function(String) onNonRealisee;

  const ConsigneList({
    super.key, // Modifié ici
    required this.consignes,
    required this.onValider,
    required this.onNonRealisee,
  }); // Plus besoin de `: super(key: key)` ici

  @override
  Widget build(BuildContext context) {
    // ... le reste de votre code build reste inchangé
    return Column(
      children: consignes.map((c) {
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          child: ListTile(
            title: Text(c.contenu),
            subtitle: Text("Émis le ${c.dateEmission}"),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.check, color: Colors.green),
                  tooltip: 'Valider',
                  onPressed: () => onValider(c.id),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red),
                  tooltip: 'Non réalisée',
                  onPressed: () => onNonRealisee(c.id),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}