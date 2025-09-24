import 'package:flutter/material.dart';

class InfosWidget extends StatelessWidget {
  const InfosWidget({super.key}); // CORRIGÉ

  @override
  Widget build(BuildContext context) {
    return const Center( // On peut ajouter const ici car Column et ses enfants peuvent l'être
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [ // const ici est déjà bon
          Icon(Icons.info_outline, size: 32, color: Colors.blueGrey),
          SizedBox(height: 8),
          Text(
            'Infos',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          Text(
            'Ajoute ici tes infos',
            style: TextStyle(fontSize: 12, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}