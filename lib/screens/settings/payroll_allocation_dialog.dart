import 'package:flutter/material.dart';
import '../../core/payroll_payment_contract.dart';

/// Selects only confirmed earned labor; never creates Tasks or changes earnings.
class PayrollAllocationDialog extends StatefulWidget {
  const PayrollAllocationDialog({
    super.key,
    required this.labor,
    required this.selected,
  });
  final List<Map<String, dynamic>> labor;
  final List<PayrollLaborAllocation> selected;
  @override
  State<PayrollAllocationDialog> createState() =>
      _PayrollAllocationDialogState();
}

class _PayrollAllocationDialogState extends State<PayrollAllocationDialog> {
  final _form = GlobalKey<FormState>();
  final _amounts = <String, String>{};
  @override
  void initState() {
    super.initState();
    for (final a in widget.selected) {
      _amounts[a.laborId] = (a.amountCents / 100).toStringAsFixed(2);
    }
  }

  int? _cents(String value) {
    if (value.trim().isEmpty) return 0;
    if (!RegExp(r'^\d{1,8}(?:\.\d{1,2})?$').hasMatch(value.trim())) return null;
    return (double.parse(value.trim()) * 100).round();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Allocate to earned labor'),
    content: SizedBox(
      width: 460,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Optional. Enter partial or full amounts. Any remainder is an unallocated advance or extra payment. Server validation checks the latest earned balance before posting.',
              ),
              if (widget.selected.any(
                (a) => !widget.labor.any((l) => l['labor_id'] == a.laborId),
              ))
                const Text(
                  'Some saved labor is no longer available. Applying removes unavailable links; Cancel preserves the draft.',
                ),
              if (widget.labor.isEmpty)
                const Text(
                  'No eligible earned labor with a cached Job label for this employee. Refresh Jobs before choosing labor.',
                ),
              for (final row in widget.labor)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: TextFormField(
                    key: ValueKey(row['labor_id']),
                    initialValue: _amounts[row['labor_id']] ?? '',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText:
                          'Job ${row['job_label'] ?? 'Not cached'} • ${row['earned_on']} • ${row['paid_hours'] ?? ''} hours',
                      helperText:
                          'Available: ${((row['available_cents'] as int) / 100).toStringAsFixed(2)}',
                    ),
                    onChanged: (v) => _amounts[row['labor_id'] as String] = v,
                    validator: (v) {
                      final n = _cents(v ?? '');
                      return n == null || n > (row['available_cents'] as int)
                          ? 'Enter an amount up to the available balance.'
                          : null;
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!_form.currentState!.validate()) return;
          Navigator.pop(context, [
            for (final row in widget.labor)
              if ((_cents(_amounts[row['labor_id']] ?? '') ?? 0) > 0)
                PayrollLaborAllocation(
                  laborId: row['labor_id'] as String,
                  amountCents: _cents(_amounts[row['labor_id']]!)!,
                ),
          ]);
        },
        child: const Text('Apply allocations'),
      ),
    ],
  );
}
