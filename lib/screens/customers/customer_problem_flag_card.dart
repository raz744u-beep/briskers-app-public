import 'package:flutter/material.dart';

/// Collapsed by default so a flagged customer's full reason doesn't crowd
/// vehicle and notes sections. The same edit callback handles both controls.
class CustomerProblemFlagCard extends StatelessWidget {
  const CustomerProblemFlagCard({
    super.key,
    required this.customerId,
    required this.flagged,
    required this.note,
    required this.canEdit,
    required this.onEdit,
  });

  final String customerId;
  final bool flagged;
  final String note;
  final bool canEdit;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        key: PageStorageKey<String>('customer-problem-flag-$customerId'),
        initiallyExpanded: false,
        leading: Icon(
          flagged ? Icons.flag : Icons.outlined_flag,
          color: flagged ? Colors.red : null,
        ),
        title: const Text(
          'Problem customer',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        children: [
          CheckboxListTile(
            title: const Text(
              'Show a red flag beside this customer throughout Briskers.',
            ),
            value: flagged,
            onChanged: canEdit ? (_) => onEdit() : null,
          ),
          if (flagged)
            ListTile(
              title: const Text('Flag reason / note'),
              subtitle: Text(
                note.trim().isEmpty ? 'Tap to add a reason' : note,
              ),
              trailing: canEdit ? const Icon(Icons.edit_outlined) : null,
              onTap: canEdit ? onEdit : null,
            ),
        ],
      ),
    );
  }
}
