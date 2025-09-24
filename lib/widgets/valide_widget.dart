import 'package:flutter/material.dart';

class ValideWidget extends StatelessWidget {
  // 1. Ajout d'un constructeur const avec super.key (résout les 2 premiers messages)
  const ValideWidget({super.key});

  @override
  Widget build(BuildContext context) {
    // 2. Ajout de 'const' aux widgets internes (résout le 3ème message)
    return const Center( // Ajout de 'const'
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 'const' pour la liste est déjà bien
          Icon(Icons.check_circle_outline, size: 32, color: Colors.green),
          // Icon est implicitement const ici
          SizedBox(height: 8),
          // SizedBox(height: ...) est const
          Text(
            'Validé',
            // Pour que Text soit const, TextStyle doit l'être.
            // TextStyle(fontWeight: FontWeight.bold, fontSize: 16) est const
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          Text(
            'Consignes validées',
            // TextStyle(fontSize: 12, color: Colors.grey) est const
            style: TextStyle(fontSize: 12, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}