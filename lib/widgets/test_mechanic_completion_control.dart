import 'package:flutter/material.dart';
import '../services/test_mechanic_completion_bridge.dart';

/// TEST-only completion control for an existing synthetic work allocation.
/// No real task, job, payment, or payroll state is modified.
class TestMechanicCompletionControl extends StatefulWidget {
  const TestMechanicCompletionControl({
    super.key,
    required this.businessId,
    required this.employeeId,
    required this.allocationId,
    this.bridge,
  });

  final String businessId;
  final String employeeId;
  final String allocationId;
  final TestMechanicCompletionBridge? bridge;

  @override
  State<TestMechanicCompletionControl> createState() =>
      _TestMechanicCompletionControlState();
}

class _TestMechanicCompletionControlState
    extends State<TestMechanicCompletionControl> {
  bool _busy = false;
  String? _message;

  Future<void> _finish() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final updated = await (widget.bridge ?? TestMechanicCompletionBridge())
          .completeSyntheticWork(
        businessId: widget.businessId,
        employeeId: widget.employeeId,
        allocationId: widget.allocationId,
      );
      if (!mounted) return;
      setState(() => _message = updated
          ? 'TEST mechanic portion marked Done.'
          : 'No eligible unfinished TEST allocation found.');
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Unable to complete TEST allocation.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton(
          onPressed: _busy ? null : _finish,
          child: Text(_busy ? 'Saving local TEST completion...' :
              'Mark TEST mechanic portion Done'),
        ),
        if (_message != null) Text(_message!),
      ],
    );
  }
}
