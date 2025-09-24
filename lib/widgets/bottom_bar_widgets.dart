import 'package:flutter/material.dart';
import '../widgets/infos_widget.dart';
import '../widgets/valide_widget.dart';

class BottomBarWidgets extends StatelessWidget {
  const BottomBarWidgets({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 220,
      child: Row(
        children: [
          Expanded(
            child: InfosWidget(),
          ),
          // ✅ Utilisation d'un code couleur ARGB constant
          VerticalDivider(
            width: 1,
            color: Color(0xFFE0E0E0), // équivalent à Colors.grey.shade300
          ),
          Expanded(
            child: ValideWidget(),
          ),
        ],
      ),
    );
  }
}
