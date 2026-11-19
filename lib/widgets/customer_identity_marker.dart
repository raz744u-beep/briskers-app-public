import 'package:flutter/material.dart';

/// Keeps the customer flag in the icon column, leaving the name's width intact.
class CustomerIdentityMarker extends StatelessWidget {
  const CustomerIdentityMarker({
    super.key,
    required this.icon,
    required this.flagged,
  });
  final Widget icon;
  final bool flagged;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      icon,
      if (flagged) ...[
        const SizedBox(height: 2),
        const Icon(
          Icons.flag,
          key: ValueKey('customer-identity-flag'),
          color: Colors.red,
          size: 19,
        ),
      ],
    ],
  );
}
