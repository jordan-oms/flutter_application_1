import 'package:flutter/material.dart';

class TrancheSelector extends StatelessWidget {
  final List<String> tranches;
  final Function(String) onSelected;

  const TrancheSelector({
    super.key,
    required this.tranches,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.menu),
      onSelected: (value) {
        onSelected(value);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("⚠️ Attention tu es sur $value")),
        );
      },
      itemBuilder: (context) => tranches
          .map((t) => PopupMenuItem<String>(value: t, child: Text(t)))
          .toList(),
    );
  }
}
