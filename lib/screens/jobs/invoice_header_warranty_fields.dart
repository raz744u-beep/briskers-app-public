import 'package:flutter/material.dart';

/// Edit-invoice sheet presentation only. The toggle reveals optional
/// insurance/warranty reference fields; it does not change warranty approval,
/// processing fees, payment state, or the separate Warranty Job preference.
/// Existing reference values remain untouched when the section is hidden.
class InvoiceHeaderWarrantyFields extends StatefulWidget {
  const InvoiceHeaderWarrantyFields({
    super.key,
    required this.claimController,
    required this.authorizationController,
    this.initiallyExpanded = false,
  });

  final TextEditingController claimController;
  final TextEditingController authorizationController;
  final bool initiallyExpanded;

  @override
  State<InvoiceHeaderWarrantyFields> createState() =>
      _InvoiceHeaderWarrantyFieldsState();
}

class _InvoiceHeaderWarrantyFieldsState
    extends State<InvoiceHeaderWarrantyFields> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    // Existing references must be discoverable without user guessing that
    // they were saved in a collapsed section on an older invoice.
    _expanded = widget.initiallyExpanded ||
        widget.claimController.text.trim().isNotEmpty ||
        widget.authorizationController.text.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      CheckboxListTile(
        key: const ValueKey('invoice-header-warranty-checkbox'),
        value: _expanded,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        title: const Text('Warranty information'),
        subtitle: const Text('Show claim and authorization numbers'),
        onChanged: (checked) =>
            setState(() => _expanded = checked ?? false),
      ),
      if (_expanded) ...[
        TextField(
          key: const ValueKey('invoice-header-warranty-claim'),
          controller: widget.claimController,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Claim number',
            prefixIcon: Icon(Icons.assignment_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('invoice-header-warranty-authorization'),
          controller: widget.authorizationController,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Authorization number',
            prefixIcon: Icon(Icons.verified_outlined),
            border: OutlineInputBorder(),
          ),
        ),
      ],
    ],
  );
}
