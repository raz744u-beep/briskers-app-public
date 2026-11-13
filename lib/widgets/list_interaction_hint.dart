import 'package:flutter/material.dart';

class ListInteractionHint extends StatelessWidget {
  const ListInteractionHint({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 6),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        'Tap to open · Long press for options',
        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
      ),
    ),
  );
}
