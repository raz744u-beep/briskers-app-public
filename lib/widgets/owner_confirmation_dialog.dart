import 'package:flutter/material.dart';

class OwnerConfirmationDialog extends StatelessWidget {
  const OwnerConfirmationDialog({
    super.key,
    required this.title,
    required this.sections,
    required this.confirm,
    this.destructive = false,
    this.canConfirm=true,
    this.cancelLabel='Cancel',
  });
  final String title, confirm;
  final List<Widget> sections;
  final bool destructive,canConfirm;
  final String cancelLabel;
  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? const Color(0xFFB91C1C)
        : const Color(0xFF087D4B);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 580,
          maxHeight:
              MediaQuery.sizeOf(context).height -
              MediaQuery.viewInsetsOf(context).bottom -
              80,
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Icon(
                      destructive
                          ? Icons.warning_amber_rounded
                          : Icons.verified_outlined,
                      color: color,
                      size: 30,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: sections,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(cancelLabel),
                    ),
                    if(canConfirm)FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: color),
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(confirm),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
