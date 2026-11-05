import 'package:flutter/material.dart';

import '../../local/local_database_provider.dart';
import '../../services/device_owner_authorization.dart';
import '../../services/payroll_lan_enrollment.dart';
import '../../services/payroll_lan_identity.dart';
import '../../services/payroll_lan_workflow.dart';
import 'payroll_lan_controls.dart';

class MechanicLaborScreen extends StatefulWidget {
  const MechanicLaborScreen({
    super.key, required this.businessId, this.jobId,
  });

  final String businessId;
  final String? jobId;

  @override
  State<MechanicLaborScreen> createState() => _MechanicLaborScreenState();
}

class _MechanicLaborScreenState extends State<MechanicLaborScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _busy = false;
  String? _error;
  ({int unpaid, List<Map<String, dynamic>> receipts})? _report;

  String _actor() => DeviceOwnerAuthorization.instance.currentIdentity()?.actorId ??
      (throw StateError('Open your saved mechanic account first.'));

  Future<PayrollLanWorkflow> _workflow() async {
    final actor = _actor();
    final identity = await PayrollLanIdentity.load();
    final peer = await PayrollLanEnrollment(identity).mechanicPeer(widget.businessId, actor);
    if (peer == null) throw StateError('Ask the Owner to pair this mechanic device.');
    void assertLink() {
      if (!mounted || _actor() != actor) throw StateError('Mechanic account changed.');
    }
    assertLink();
    return PayrollLanWorkflow(
      database: localDatabase, identity: identity, peer: peer, assertLink: assertLink,
      onOwnerCertificate: (certificate) async {
        assertLink();
        await PayrollLanEnrollment(identity).acceptOwnerRoute(widget.businessId, actor, certificate);
        assertLink();
      },
    );
  }

  Future<void> _pair() async {
    try {
      final identity = await PayrollLanIdentity.load();
      if (!mounted) return;
      await showPayrollLanCode(context, 'Give this device ID to the Owner', identity.deviceId);
      if (!mounted) return;
      final owner = await payrollLanInput(context, 'Verify in person with the Owner', 'Owner device ID');
      if (!mounted || owner == null) return;
      final code = await payrollLanInput(context, 'Pair mechanic device', 'Private pairing code');
      if (!mounted || code == null) return;
      await PayrollLanEnrollment(identity).accept(
        code: code, business: widget.businessId,
        verifiedOwnerDevice: owner, actor: _actor(),
      );
      if (mounted) await _refresh();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _sync() async {
    try {
      final workflow = await _workflow();
      if (mounted) await showPayrollLanSync(context, workflow);
      if (mounted) await _refresh();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }


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
      _report = null;
    });
    try {
      final workflow = await _workflow();
      if (update != null && minutes != null) {
        await workflow.progress(
          job: update['job_id'] as String, id: update['id'] as String,
          state: update['state'] == 'Open' ? 'In Progress' : 'Done',
          minutes: minutes, date: DateTime.now().toIso8601String().substring(0, 10),
          revision: update['revision'] as int,
        );
      }
      final rows = await workflow.mechanicWork(widget.jobId);
      final report = await workflow.mechanicReport();
      if (mounted) {
        setState(() {
          _rows = rows;
          _report = report;
        });
      }
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

  String _money(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

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
        TextButton(onPressed: _busy ? null : _pair, child: const Text('Pair with Owner')),
        TextButton(onPressed: _busy ? null : _sync, child: const Text('Sync payroll over shop Wi-Fi')),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        if (!_busy && _error == null && _rows.isEmpty)
          const Text('No labor tasks are saved for your assignment on this device.'),
        if (_report case final report?) ...[
          ListTile(title: Text('Unpaid: ${_money(report.unpaid)}')),
          for (final receipt in report.receipts)
            ListTile(
              title: Text('Paid: ${_money(receipt['net'] as int)}'),
              subtitle: Text('${receipt['verified_date']} · ${receipt['method']}'),
            ),
        ],
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
