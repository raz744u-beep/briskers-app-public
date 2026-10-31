import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';

import '../../core/connection_mode.dart';

import '../../local/local_database_provider.dart';

/// Read-only Owner diagnostic. No remote calls and no outbox mutations.
/// A subsequent recovery action requires independent verified server proof.
class LocalRecoveryReviewScreen extends StatefulWidget {
  const LocalRecoveryReviewScreen({
    super.key, required this.businessId, required this.isOwner,
  });
  final String businessId;
  final bool isOwner;

  @override
  State<LocalRecoveryReviewScreen> createState() =>
      _LocalRecoveryReviewScreenState();
}

class _LocalRecoveryReviewScreenState extends State<LocalRecoveryReviewScreen> {
  bool _checking = false;
  String? _error;
  Map<String, int>? _counts;

  Future<void> _check() async {
    if (!widget.isOwner || _checking) return;
    setState(() { _checking = true; _error = null; });
    try {
      final rows = await localDatabase.customSelect(
        '''SELECT entity_type,COUNT(*) AS total FROM sync_outbox
        WHERE business_id=? AND state IN ('pending','inflight','conflict')
        AND entity_type IN ('customer_create','vehicle_create',
          'document_draft_create','invoice_payment_received')
        GROUP BY entity_type''',
        variables: [Variable<String>(widget.businessId)],
      ).get();
      if (!mounted) return;
      setState(() => _counts = {
        for (final row in rows)
          row.read<String>('entity_type'): row.read<int>('total'),
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Local recovery verification is unavailable.');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isOwner) {
      return Scaffold(
        appBar: AppBar(title: const Text('Recovery review')),
        body: const Center(child: Text('Owner permission required.')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Offline recovery review')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Read-only local check',
          style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text('Checks queued record counts on this device. It does '
          'not connect to the server, synchronize, alter invoices, or '
          'remove payments. Counts are not proof that a payment exists '
          'on the server.'),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _checking ? null : _check,
          icon: const Icon(Icons.fact_check_outlined),
          label: Text(_checking ? 'Checking locally...' : 'Check local records'),
        ),
        if (_error != null) Text(_error!),
        if (_counts != null) ...[
          const SizedBox(height: 16),
          for (final entry in const [
            ('customer_create', 'Customers'),
            ('vehicle_create', 'Vehicles'),
            ('document_draft_create', 'Invoices / estimates'),
            ('invoice_payment_received', 'Recorded payments'),
          ])
            ListTile(title: Text(entry.$2),
              trailing: Text('${_counts![entry.$1] ?? 0}')),
        ],
        const SizedBox(height: 16),
        AnimatedBuilder(
          animation: BriskersConnectionModeController.instance,
          builder: (context, _) => Text(
            BriskersConnectionModeController.instance.forceOffline
                ? 'Force Offline is enabled. No server verification or payment acknowledgment will run.'
                : 'Auto mode is active. This review remains read-only and does not trigger synchronization.',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Recovery acknowledgment remains disabled until '
          'authoritative invoice and payment identities can be verified, '
          'and the full local transaction is tested.'),
      ]),
    );
  }
}
