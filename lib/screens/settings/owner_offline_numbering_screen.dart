import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';

import '../../core/connection_mode.dart';
import '../../local/local_database_provider.dart';
import '../../services/local_owner_invoice_numbering.dart';
import '../../services/local_document_number_suggestions.dart';

/// Owner-only local correction of existing invoice and linked Job numbers.
/// No network calls, new documents, or payments.
class OwnerOfflineNumberingScreen extends StatefulWidget {
  const OwnerOfflineNumberingScreen({
    super.key,
    required this.businessId,
    required this.isOwner,
  });
  final String businessId;
  final bool isOwner;

  @override
  State<OwnerOfflineNumberingScreen> createState() =>
      _OwnerOfflineNumberingScreenState();
}

class _OwnerOfflineNumberingScreenState extends State<OwnerOfflineNumberingScreen> {
  final _invoiceNumber = TextEditingController();
  final _jobNumber = TextEditingController();
  bool _loading = false;
  String? _selectedInvoice;
  String? _selectedJob;
  String? _message;
  String? _lastInvoice;
  String? _lastJob;
  String? _suggestedInvoice;
  String? _suggestedJob;
  List<Map<String, dynamic>> _choices = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _invoiceNumber.dispose();
    _jobNumber.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!widget.isOwner) return;
    setState(() => _loading = true);
    try {
      final rows = await localDatabase.customSelect(
        '''SELECT d.id,d.job_id,d.document_number,d.total,
                  j.job_number, j.customer_name,j.vehicle_label
           FROM local_documents d JOIN local_jobs j
             ON j.business_id=d.business_id AND j.id=d.job_id
           WHERE d.business_id=? AND d.kind='invoice'
             AND d.sync_state='pending' AND j.sync_state='pending'
           ORDER BY d.created_at DESC LIMIT 30''',
        variables:[Variable<String>(widget.businessId)],
      ).get();
      final suggestions = await LocalDocumentNumberSuggestions()
          .suggest(widget.businessId);
      if (!mounted) return;
      setState(() {
        _lastInvoice = suggestions.latestInvoice;
        _lastJob = suggestions.latestJob;
        _suggestedInvoice = suggestions.invoice;
        _suggestedJob = suggestions.job;
        _choices = rows.map((r) => Map<String, dynamic>.from(r.data)).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Unable to inspect local invoices. No changes were made.';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (!widget.isOwner || _loading || _selectedInvoice == null ||
        _selectedJob == null || !BriskersConnectionModeController.instance.forceOffline) {
      setState(() => _message = 'Keep Force Offline enabled and select an invoice.');
      return;
    }
    final invoice = _invoiceNumber.text.trim();
    final job = _jobNumber.text.trim();
    if (invoice.isEmpty || job.isEmpty) {
      setState(() => _message = 'Enter both numbers.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Assign numbers locally?'),
        content: Text('Invoice #$invoice and Job $job will be saved on this phone. '
          'The original invoice and payment will not be deleted or uploaded. '
          'Their pending upload operations will be held for later review.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Save locally')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() { _loading = true; _message = null; });
    try {
      await LocalOwnerInvoiceNumbering().assign(
        isOwner: widget.isOwner,
        businessId: widget.businessId,
        invoiceId: _selectedInvoice!,
        jobId: _selectedJob!,
        invoiceNumber: invoice,
        jobNumber: job,
      );
      if (!mounted) return;
      setState(() => _message = 'Saved on this phone. Sync remains disabled.');
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Nothing changed: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Owner offline numbering')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Assign invoice and Job numbers without Supabase. '
        'Only existing local records can be changed.'),
      const SizedBox(height: 12),
      if (!widget.isOwner)
        const Text('Owner authorization required.')
      else ...[
        if (!BriskersConnectionModeController.instance.forceOffline)
          const Text('Enable Force Offline before assigning numbers.'),
        Text('Highest local invoice: ${_lastInvoice ?? 'Not available'} · '
          'Suggested: ${_suggestedInvoice ?? 'Enter manually'}'),
        Text('Highest local Job: ${_lastJob ?? 'Not available'} · '
          'Suggested: ${_suggestedJob ?? 'Enter manually'}'),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey(_selectedInvoice),
          initialValue: _selectedInvoice,
          decoration: const InputDecoration(labelText: 'Existing local invoice'),
          items: _choices.map((item) => DropdownMenuItem<String>(
            value:item['id']?.toString(),
            child: Text('${item['customer_name'] ?? 'Customer'} · '
              '${item['vehicle_label'] ?? 'Vehicle'} · '
              '${item['total'] ?? ''}',overflow:TextOverflow.ellipsis),
          )).toList(),
          onChanged: _loading ? null : (id) {
            final match = _choices.where((c)=>c['id']==id).firstOrNull;
            setState(() {
              _selectedInvoice=id;
              _selectedJob=match?['job_id']?.toString();
              final existingInvoice=match?['document_number']?.toString() ?? '';
              final existingJob=match?['job_number']?.toString() ?? '';
              _invoiceNumber.text=existingInvoice.trim().isNotEmpty
                  ? existingInvoice : (_suggestedInvoice ?? '');
              _jobNumber.text=existingJob.trim().isNotEmpty &&
                  !existingJob.toUpperCase().startsWith('TEMP-')
                  ? existingJob : (_suggestedJob ?? '');
            });
          },
        ),
        const SizedBox(height: 10),
        TextField(controller:_invoiceNumber,
          decoration: const InputDecoration(labelText:'Invoice number')),
        const SizedBox(height: 10),
        TextField(controller:_jobNumber,
          decoration: const InputDecoration(labelText:'Job number')),
        const SizedBox(height: 14),
        FilledButton(onPressed: _loading ? null : _save,
          child: Text(_loading ? 'Saving locally...' : 'Check conflicts and save')),
      ],
      if (_message != null) Padding(
        padding: const EdgeInsets.only(top:12),
        child: Text(_message!),
      ),
    ]),
  );
}
