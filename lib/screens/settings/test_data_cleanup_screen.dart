import 'package:drift/drift.dart';
import 'package:flutter/material.dart';

import '../../local/local_database_provider.dart';
import '../../services/local_document_detail_cache.dart';
import '../../services/offline_document_draft_service.dart';

/// Owner-only review. Only never-uploaded quick invoices can be canceled;
/// all other records remain visible for manual reconciliation.
class TestDataCleanupScreen extends StatefulWidget {
  const TestDataCleanupScreen({super.key, required this.businessId});
  final String businessId;

  @override
  State<TestDataCleanupScreen> createState() => _TestDataCleanupScreenState();
}

class _TestDataCleanupScreenState extends State<TestDataCleanupScreen> {
  final _drafts = OfflineDocumentDraftService();
  final _cache = const LocalDocumentDetailCache();
  List<Map<String, dynamic>> _records = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await localDatabase.customSelect(
        """SELECT d.id,d.kind,d.job_id,d.document_number,d.total,d.sync_state,
                  d.created_at,
                  (SELECT COUNT(*) FROM sync_outbox o
                   WHERE o.business_id=d.business_id AND o.entity_id=d.id
                     AND o.entity_type='invoice_payment_received')
                    AS queued_payments
           FROM local_documents d
           WHERE d.business_id=? AND d.sync_state='pending'
           ORDER BY d.created_at DESC LIMIT 100""",
        variables: [Variable<String>(widget.businessId)],
      ).get();
      final result = <Map<String, dynamic>>[];
      for (final row in rows) {
        final id = row.read<String>('id');
        final snapshot = await _cache.load(widget.businessId, id);
        result.add({
          'id': id, 'kind': row.read<String>('kind'),
          'job_id': row.readNullable<String>('job_id'),
          'total': row.read<double>('total'),
          'queued': row.read<int>('queued_payments'),
          'customer': snapshot?['customer_name']?.toString() ?? 'Unknown customer',
          'job_number': snapshot?['job_number']?.toString() ?? '',
          'local': id.startsWith('local-invoice-'),
        });
      }
      if (mounted) setState(() => _records = result);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancel(Map<String, dynamic> row) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(row['kind'] == 'estimate' ? 'Cancel local estimate?' : 'Cancel local test invoice?'),
        content: Text(
          'Remove only this never-uploaded document and any unshared '
          'temporary job?\n\n${row['customer']}\n${row['id']}\n\n'
          'The app will refuse if synchronization or payment status is uncertain.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel invoice')),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      if (row['kind'] == 'estimate') {
        await _drafts.cancelNeverSyncedStandaloneEstimate(
          widget.businessId, row['id'] as String);
      } else {
        await _drafts.cancelNeverSyncedQuickInvoice(
          widget.businessId, row['id'] as String);
      }
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Test Data Cleanup')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(children: [
              const ListTile(
                title: Text('Local pending documents — review only'),
                subtitle: Text(
                  'Only never-uploaded standalone estimates and quick invoices '
                  'without pending payments or shared jobs can be canceled here. Other jobs, '
                  'and server records are deliberately protected. '
                  'Keep J7, invoice 6331 and estimate 1997.',
                ),
              ),
              if (_error != null) ListTile(
                leading: const Icon(Icons.warning_amber, color: Colors.red),
                title: Text(_error!),
              ),
              if (_records.isEmpty)
                const ListTile(title: Text('No pending local documents found')),
              ..._records.map((row) {
                final safe = (row['local'] == true ||
                    (row['kind'] == 'estimate' &&
                     (row['id'] as String).startsWith('local-estimate-'))) &&
                    row['queued'] == 0;
                return ListTile(
                  title: Text("${row['customer']} · ${row['kind']}"),
                  subtitle: Text(
                    "${row['job_number']} · ${row['id']}\n"
                    "Total: ${row['total']} · Queued payments: ${row['queued']}",
                  ),
                  isThreeLine: true,
                  trailing: safe
                      ? IconButton(
                          tooltip: 'Cancel after safety checks',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _cancel(row),
                        )
                      : const Icon(Icons.lock_outline),
                );
              }),
            ]),
          ),
  );
}
