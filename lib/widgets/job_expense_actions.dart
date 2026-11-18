import 'package:flutter/material.dart';
import '../core/briskers_colors.dart';

class JobExpenseActions extends StatelessWidget {
  const JobExpenseActions({
    super.key, required this.onAdd, required this.onQuick,
    this.busy = false,
  });
  final VoidCallback onAdd, onQuick;
  final bool busy;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Wrap(spacing: 8, runSpacing: 8, children: [
      FilledButton.icon(
        key: const Key('add-job-expense'),
        style: FilledButton.styleFrom(backgroundColor: BriskersColors.confirm),
        onPressed: busy ? null : onAdd,
        icon: const Icon(Icons.add),
        label: const Text('Add Expense'),
      ),
      OutlinedButton.icon(
        key: const Key('quick-job-expense'),
        onPressed: busy ? null : onQuick,
        icon: const Icon(Icons.bolt),
        label: const Text('Quick Expense'),
      ),
    ]),
  );
}
