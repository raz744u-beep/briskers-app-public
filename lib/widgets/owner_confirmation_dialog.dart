import 'package:flutter/material.dart';

import 'briskers_dialog.dart';

class OwnerConfirmationDialog extends StatelessWidget {
  const OwnerConfirmationDialog({
    super.key,
    required this.title,
    required this.sections,
    required this.confirm,
    this.destructive = false,
    this.canConfirm = true,
    this.cancelLabel = 'Cancel',
  });

  final String title, confirm;
  final List<Widget> sections;
  final bool destructive, canConfirm;
  final String cancelLabel;

  @override
  Widget build(BuildContext context) => BriskersDialog(
    title: title,
    icon: destructive ? Icons.warning_amber_rounded : Icons.verified_outlined,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: sections,
    ),
    actions: [
      OutlinedButton(
        style: BriskersDialog.cancelStyle,
        onPressed: () => Navigator.pop(context, false),
        child: Text(cancelLabel),
      ),
      if (canConfirm)
        FilledButton(
          style: BriskersDialog.confirmStyle(destructive: destructive),
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirm),
        ),
    ],
  );
}
