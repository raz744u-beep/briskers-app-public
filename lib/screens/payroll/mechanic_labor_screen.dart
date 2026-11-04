import 'package:flutter/material.dart';

import '../../core/supabase_config.dart';
import '../../local/local_database_provider.dart';
import '../../services/briskers_api.dart';
import '../../services/local_payroll_repository.dart';

class MechanicLaborScreen extends StatefulWidget {
  const MechanicLaborScreen({
    super.key, required this.businessId, required this.jobId,
  });

  final String businessId;
  final String jobId;

  @override
  State<MechanicLaborScreen> createState() => _MechanicLaborScreenState();
}

class _MechanicLaborScreenState extends State<MechanicLaborScreen> {
  late final _repository = LocalPayrollRepository(
    localDatabase, business: widget.businessId, owner: false,
  );
  List<Map<String, dynamic>> _rows = [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh({Map<String, dynamic>? update, int? minutes}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _rows = [];
    });
    try {
      final session = supabase.auth.currentSession;
      if (session == null) throw StateError('Sign in as the assigned mechanic.');
      void assertSession() {
        if (supabase.auth.currentSession?.accessToken != session.accessToken) {
          throw StateError('Your session changed. Refresh to continue.');
        }
      }
      final employee = await const BriskersApi()
          .myPayrollAssignment(widget.businessId, widget.jobId);
      assertSession();
      if (employee == null) throw StateError('No active mechanic assignment.');
      if (update != null && minutes != null) {
        await _repository.updateMechanicWork(
          job: widget.jobId,
          employee: employee,
          id: update['id'] as String,
          state: update['state'] == 'Open' ? 'In Progress' : 'Done',
          minutes: minutes,
          date: DateTime.now().toIso8601String().substring(0, 10),
          expectedRevision: update['revision'] as int,
          assertSession: assertSession,
        );
      }
      final rows = await _repository.mechanicWork(
        job: widget.jobId, employee: employee, assertSession: assertSession,
      );
      if (mounted) setState(() => _rows = rows);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _complete(Map<String, dynamic> row) async {
    int? minutes;
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete my labor'),
        content: TextField(
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Actual minutes'),
          onChanged: (value) => minutes = int.tryParse(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final entered = minutes;
              if (entered != null && entered > 0) {
                Navigator.pop(context, entered);
              }
            },
            child: const Text('Complete'),
          ),
        ],
      ),
    );
    if (value != null && mounted) await _refresh(update: row, minutes: value);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('My labor tasks'),
      actions: [
        IconButton(
          tooltip: 'Refresh labor tasks',
          onPressed: _busy ? null : () => _refresh(),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        if (!_busy && _error == null && _rows.isEmpty)
          const Text('No labor tasks are saved for your assignment on this device.'),
        for (final row in _rows)
          ListTile(
            title: Text(row['description'].toString()),
            subtitle: Text(row['state'].toString()),
            trailing: row['state'] == 'Done' ? null : TextButton(
              onPressed: _busy ? null : () async {
                if (row['state'] == 'Open') {
                  await _refresh(update: row, minutes: row['actual_minutes'] as int);
                } else {
                  await _complete(row);
                }
              },
              child: Text(row['state'] == 'Open' ? 'Start' : 'Complete'),
            ),
          ),
      ],
    ),
  );
}
