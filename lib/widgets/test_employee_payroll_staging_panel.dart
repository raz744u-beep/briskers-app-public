import 'package:flutter/material.dart';
import '../services/test_payroll_staging_repository.dart';

/// TEST-only preview. Intentionally has no payment or finalization buttons.
class TestEmployeePayrollStagingPanel extends StatefulWidget {
  const TestEmployeePayrollStagingPanel({
    super.key,
    required this.businessId,
    required this.employeeId,
    this.repository,
  });

  final String businessId;
  final String employeeId;
  final TestPayrollStagingRepository? repository;

  @override
  State<TestEmployeePayrollStagingPanel> createState() =>
      _TestEmployeePayrollStagingPanelState();
}

class _TestEmployeePayrollStagingPanelState
    extends State<TestEmployeePayrollStagingPanel> {
  late Future<List<Map<String, Object?>>> _staged;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant TestEmployeePayrollStagingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId ||
        oldWidget.employeeId != widget.employeeId ||
        oldWidget.repository != widget.repository) {
      _refresh();
    }
  }

  void _refresh() {
    _staged = (widget.repository ?? TestPayrollStagingRepository())
        .stagedForEmployee(
          businessId: widget.businessId,
          employeeId: widget.employeeId,
        );
  }

  String _money(Object? cents) {
    final amount = cents is int ? cents : 0;
    return '\$${(amount / 100).toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, Object?>>>(
      future: _staged,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text('Unable to read TEST payroll staging.');
        }
        if (!snapshot.hasData) {
          return const Text('Loading local TEST payroll preview...');
        }
        final rows = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('TEST payroll proposals — not paid',
                style: TextStyle(fontWeight: FontWeight.bold)),
            if (rows.isEmpty)
              const Text('No staged payroll proposals')
            else
              for (final item in rows)
                ListTile(
                  title: Text('Staged • ${_money(item['net_cents'])} net'),
                  subtitle: Text(
                    'Gross ${_money(item['gross_cents'])} · '
                    'Repayment ${_money(item['repayment_cents'])} · '
                    '${item['method'] ?? ''}',
                  ),
                ),
          ],
        );
      },
    );
  }
}
