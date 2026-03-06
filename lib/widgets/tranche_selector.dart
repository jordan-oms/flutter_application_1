// lib/widgets/tranche_selector.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TrancheSelector extends StatelessWidget {
  final List<String> tranches;
  final Function(String) onTrancheSelected;
  final String? favoriteTranche;
  final String userId;
  final List<String> userRoles;

  const TrancheSelector({
    super.key,
    required this.tranches,
    required this.onTrancheSelected,
    required this.userId,
    this.favoriteTranche,
    required this.userRoles,
  });

  Future<void> _setFavorite(String tranche, BuildContext context) async {
    // On ferme le menu avant d'afficher le SnackBar
    Navigator.of(context).pop();

    try {
      await FirebaseFirestore.instance
          .collection('utilisateurs')
          .doc(userId)
          .update({'favoriteTranche': tranche});

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("'$tranche' est maintenant votre tranche par défaut."),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur lors de la mise à jour du favori: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // --- MODIFICATION ICI ---
    // On autorise TOUS ceux qui arrivent sur ce widget à mettre en favori
    // (Puisque le mode lecture seule n'utilise pas ce widget, c'est parfait)
    const bool canSetFavorite = true;

    return PopupMenuButton<String>(
      icon: const Icon(Icons.layers_outlined),
      tooltip: "Sélectionner une tranche",
      onSelected: (value) {
        onTrancheSelected(value);
      },
      itemBuilder: (context) => tranches.map((t) {
        final isFavorite = t == favoriteTranche;
        return PopupMenuItem<String>(
          value: t,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                t,
                style: TextStyle(
                  fontWeight: isFavorite ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              // L'étoile est maintenant visible pour tous les utilisateurs connectés
              if (canSetFavorite)
                IconButton(
                  icon: Icon(
                    isFavorite ? Icons.star : Icons.star_border,
                    color: isFavorite ? Colors.amber : Colors.grey,
                  ),
                  tooltip: 'Définir comme tranche par défaut',
                  onPressed: () => _setFavorite(t, context),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
