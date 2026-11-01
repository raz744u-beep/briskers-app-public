import 'package:flutter/material.dart';
import '../services/test_payroll_credit_repository.dart';
import 'test_payroll_task_selector.dart';

/// Reads only explicit TEST work credits; never production job planned hours.
class TestLocalPayrollTaskList extends StatefulWidget {
  const TestLocalPayrollTaskList({
    super.key, required this.businessId, required this.employeeId,
    required this.isOwner, this.repository,
  });
  final String businessId;
  final String employeeId;
  final bool isOwner;
  final TestPayrollCreditRepository? repository;

  @override
  State<TestLocalPayrollTaskList> createState() =>
      _TestLocalPayrollTaskListState();
}

class _TestLocalPayrollTaskListState extends State<TestLocalPayrollTaskList> {
  late Future<List<dynamic>> _credits;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TestLocalPayrollTaskList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId ||
        oldWidget.employeeId != widget.employeeId ||
        oldWidget.isOwner != widget.isOwner ||
        oldWidget.repository != widget.repository) {
      _load();
    }
  }

  void _load() {
    _credits = (widget.repository ?? TestPayrollCreditRepository())
        .completedUnpaid(
          businessId: widget.businessId, employeeId: widget.employeeId,
        );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _credits,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text('TEST task credits unavailable.');
        }
        if (!snapshot.hasData) {
          return const Text('Loading local TEST task credits...');
        }
        return TestPayrollTaskSelector(
          employeeId: widget.employeeId,
          isOwner: widget.isOwner,
          allocations: snapshot.data!.cast(),
        );
      },
    );
  }
}
