import 'package:flutter/material.dart';
import '../core/shop_payroll_preview.dart';

/// Isolated task-credit selector. This widget never posts payroll.
class TestPayrollTaskSelector extends StatefulWidget {
  const TestPayrollTaskSelector({
    super.key,
    required this.employeeId,
    required this.allocations,
    required this.isOwner,
  });

  final String employeeId;
  final List<ShopPayrollAllocation> allocations;
  final bool isOwner;

  @override
  State<TestPayrollTaskSelector> createState() => _TestPayrollTaskSelectorState();
}

class _TestPayrollTaskSelectorState extends State<TestPayrollTaskSelector> {
  final Set<String> _selected = {};

  @override
  void didUpdateWidget(covariant TestPayrollTaskSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.employeeId != widget.employeeId ||
        oldWidget.allocations != widget.allocations ||
        oldWidget.isOwner != widget.isOwner) {
      _selected.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final eligible = widget.allocations.where((a) =>
        widget.isOwner && a.employeeId == widget.employeeId &&
        a.completed && !a.alreadyPaid).toList(growable: false);
    final uniqueIds = <String>{};
    final usable = eligible.where((a) =>
        a.id.trim().isNotEmpty && uniqueIds.add(a.id)).toList(growable: false);
    final selected = usable.where((a) => _selected.contains(a.id)).toList();
    final gross = ShopPayrollPreview.grossCents(
      owner: widget.isOwner,
      employeeId: widget.employeeId,
      selected: selected,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('TEST work selection — no payment will be recorded'),
        for (final credit in usable)
          CheckboxListTile(
            value: _selected.contains(credit.id),
            title: Text(credit.id),
            subtitle: Text(
              '${(credit.hoursHundredths / 100).toStringAsFixed(2)} hrs',
            ),
            onChanged: widget.isOwner
                ? (value) => setState(() {
                    if (value == true) {
                      _selected.add(credit.id);
                    } else {
                      _selected.remove(credit.id);
                    }
                  })
                : null,
          ),
        Text('Selected gross: \$${(gross / 100).toStringAsFixed(2)}'),
      ],
    );
  }
}
