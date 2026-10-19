import 'package:flutter/material.dart';

/// A local editor for a labor task's mechanic allocations.
///
/// This widget does NOT persist payroll, invoice lines, or customer prices.
/// Callers must validate and save the returned draft via the role-gated,
/// offline-aware task repository once that storage contract is available.
class LaborAssignmentDraft {
  const LaborAssignmentDraft({
    required this.employeeId,
    required this.nickname,
    required this.payrollHours,
  });
  final String employeeId;
  final String nickname;
  final double payrollHours;
}

class LaborAssignmentDraftSheet extends StatefulWidget {
  const LaborAssignmentDraftSheet({
    super.key,
    required this.description,
    required this.billedHours,
    required this.employees,
    required this.initial,
  });

  final String description;
  final double billedHours;
  final List<({String id, String nickname})> employees;
  final List<LaborAssignmentDraft> initial;

  @override
  State<LaborAssignmentDraftSheet> createState() =>
      _LaborAssignmentDraftSheetState();
}

class _LaborAssignmentDraftSheetState extends State<LaborAssignmentDraftSheet> {
  late final List<String?> _ids;
  late final List<TextEditingController> _hours;

  @override
  void initState() {
    super.initState();
    final rows = widget.initial.isEmpty
        ? [const LaborAssignmentDraft(employeeId: '', nickname: '', payrollHours: 0)]
        : widget.initial;
    _ids = rows.map((r) => r.employeeId.isEmpty ? null : r.employeeId).toList();
    _hours = rows.map((r) => TextEditingController(text: r.payrollHours.toString())).toList();
  }

  @override
  void dispose() {
    for (final controller in _hours) {
      controller.dispose();
    }
    super.dispose();
  }

  void _add() => setState(() {
    _ids.add(null);
    _hours.add(TextEditingController(text: '0'));
  });

  void _remove(int index) {
    final controller = _hours.removeAt(index);
    _ids.removeAt(index);
    setState(() {});
    controller.dispose();
  }

  void _save() {
    final used = <String>{};
    final result = <LaborAssignmentDraft>[];
    for (var i = 0; i < _ids.length; i++) {
      final id = _ids[i];
      final hours = double.tryParse(_hours[i].text.trim());
      if (id == null || hours == null || !hours.isFinite || hours < 0 || !used.add(id)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Choose unique mechanics and valid nonnegative hours.')),
        );
        return;
      }
      final employee = widget.employees.where((e) => e.id == id).first;
      result.add(LaborAssignmentDraft(
        employeeId: id, nickname: employee.nickname, payrollHours: hours,
      ));
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16, right: 16, top: 18,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Assign labor', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(widget.description, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text('Customer billed: ${widget.billedHours.toStringAsFixed(1)} hours (unchanged)'),
              const Divider(height: 24),
              for (var i = 0; i < _ids.length; i++) ...[
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('mechanic-$i'),
                        initialValue: _ids[i],
                        decoration: const InputDecoration(labelText: 'Mechanic'),
                        items: widget.employees.map((e) =>
                          DropdownMenuItem(value: e.id, child: Text(e.nickname))).toList(),
                        onChanged: (v) => setState(() => _ids[i] = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _hours[i],
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Pay hrs'),
                      ),
                    ),
                    if (_ids.length > 1)
                      IconButton(
                        tooltip: 'Remove mechanic',
                        onPressed: () => _remove(i),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              OutlinedButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Add another mechanic'),
              ),
              const SizedBox(height: 12),
              Text('Internal only. Nothing here appears on the customer invoice.',
                style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.check),
                label: const Text('Use assignment'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
