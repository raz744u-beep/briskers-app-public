import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';

import '../../core/connection_mode.dart';
import '../../services/owner_recovery_finalizer.dart';

import '../../local/local_database_provider.dart';

/// Owner recovery review with an explicit authenticated read-only lookup.
/// Finalization is local, atomic, and never sends a business-data upload.
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
  String? _result;

  Future<void> _reconcile() async {
    if (!widget.isOwner || _checking) return;
    setState(() { _checking=true; _error=null; _result=null; _counts=null; });
    try {
      final rows=await localDatabase.customSelect(
        "SELECT entity_id FROM sync_outbox WHERE business_id=? AND entity_type='document_draft_create' AND state IN ('conflict','reconciled') AND last_error='Owner assigned authoritative local number; sync disabled'",
        variables:[Variable<String>(widget.businessId)]).get();
      if (rows.length!=1) throw StateError('Exactly one held recovery invoice is required.');
      await OwnerRecoveryFinalizer().reconcile(isOwner:widget.isOwner,
        businessId:widget.businessId,localInvoiceId:rows.single.read<String>('entity_id'));
      if (mounted) setState(()=>_result='Recovery reconciled and saved on this device. Original operations remain preserved and cannot upload again. Force Offline is still enabled. Return to the invoice list to check the invoice, then select Auto to resume normal sync.');
    } catch (e) {
      if (mounted) setState(()=>_error='Recovery was not completed. Keep Force Offline enabled. $e');
    } finally {
      if (mounted) setState(()=>_checking=false);
    }
  }

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
                ? 'Force Offline is enabled. Only the explicit read-only recovery lookup can connect.'
                : 'Auto mode is active. This review remains read-only and does not trigger synchronization.',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Verify and reconcile reads the existing server identities using your Owner session, preserves the original records, and commits the local match. It never uploads an invoice or payment.'),
        FilledButton.icon(onPressed:_checking ? null : _reconcile,
          icon:const Icon(Icons.verified_user_outlined),
          label:const Text('Verify and reconcile existing records')),
        if (_result!=null) Text(_result!),
      ]),
    );
  }
}
