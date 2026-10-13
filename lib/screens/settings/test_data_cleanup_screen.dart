import 'package:flutter/material.dart';

import '../../services/offline_document_draft_service.dart';
import '../../services/test_job_cleanup_policy.dart';
import '../../services/test_job_cleanup_service.dart';

/// Never treats cached lists or a test-looking number as deletion authority.
/// Both entering this screen and every operation require verified Owner access.
class TestDataCleanupScreen extends StatefulWidget {
  const TestDataCleanupScreen({
    super.key, required this.businessId, required this.roleCode,
    this.cleanupService,
  });
  final String businessId;
  final String roleCode;
  final TestJobCleanupService? cleanupService;

  @override
  State<TestDataCleanupScreen> createState() => _TestDataCleanupScreenState();
}

class _TestDataCleanupScreenState extends State<TestDataCleanupScreen> {
  late final _cleanup = widget.cleanupService ?? TestJobCleanupService();
  late final _drafts = OfflineDocumentDraftService();
  List<Map<String, dynamic>> _jobs = [];
  List<Map<String, dynamic>> _localDrafts = [];
  TestJobCleanupPlan? _plan;
  String _query = '';
  String? _error;
  String? _success;
  bool _working = false;
  bool _authorized = false;

  @override
  void initState() {
    super.initState();
    if (widget.roleCode == 'owner') _refresh();
  }

  @override
  void didUpdateWidget(covariant TestDataCleanupScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId ||
        oldWidget.roleCode != widget.roleCode) {
      _authorized = false;
      _plan = null;
      _jobs = [];
      _localDrafts = [];
      if (widget.roleCode == 'owner' && !_working) _refresh();
    }
  }

  String _message(Object error) {
    final text = error.toString();
    if (text.contains('PGRST202') && text.contains('test_job_cleanup')) {
      return 'The server cleanup feature is not installed yet. '
          'Deletion remains locked.';
    }
    return text;
  }

  Future<void> _refresh() async {
    if (_working || widget.roleCode != 'owner') return;
    final businessId = widget.businessId;
    setState(() { _working = true; _error = null; _plan = null; });
    try {
      final drafts = await _cleanup.pendingLocalDocuments(
        businessId, roleCode: widget.roleCode,
      );
      // Cached Owner routes may inspect local pending work while the phone
      // remains offline. Destructive controls still need fresh server auth.
      if (mounted && widget.businessId == businessId && widget.roleCode == 'owner') {
        setState(() => _localDrafts = drafts);
      }
      final jobs = await _cleanup.jobs(businessId, roleCode: widget.roleCode);
      if (mounted && widget.businessId == businessId && widget.roleCode == 'owner') {
        setState(() { _authorized = true; _jobs = jobs; });
      }
    } catch (error) {
      if (mounted) setState(() { _authorized = false; _error = _message(error); });
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _preview(Map<String, dynamic> job) async {
    if (_working || !_authorized || widget.roleCode != 'owner') return;
    final businessId = widget.businessId;
    setState(() { _working = true; _error = null; _success = null; _plan = null; });
    try {
      final plan = await _cleanup.preview(businessId, job['id'].toString(),
        roleCode: widget.roleCode);
      if (mounted && widget.businessId == businessId && widget.roleCode == 'owner') {
        setState(() => _plan = plan);
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _delete(TestJobCleanupPlan plan) async {
    if (_working || !_authorized || !plan.canDelete ||
        widget.roleCode != 'owner' || plan.businessId != widget.businessId) {
      return;
    }
    final confirmation = await showDialog<String>(
      context: context,
      builder: (_) => _CleanupConfirmationDialog(plan: plan),
    );
    if (confirmation == null || !mounted || widget.roleCode != 'owner' ||
        plan.businessId != widget.businessId || _working) {
      return;
    }
    setState(() { _working = true; _error = null; _success = null; _plan = null; });
    var succeeded = false;
    try {
      final receipt = await _cleanup.execute(plan,
        roleCode: widget.roleCode, confirmation: confirmation);
      succeeded = true;
      if (mounted) {
        setState(() => _success =
          'Deleted test ${plan.jobNumber} and ${plan.documents.length} documents. '
          'Audit: ${receipt.auditId}'
          '${receipt.cacheWarning == null ? '' : '\n${receipt.cacheWarning}'}');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '${_message(error)}\n'
            'The preview has been cleared. Refresh before trying again.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
    if (mounted && succeeded) await _refresh();
  }

  Future<void> _cancelLocal(Map<String, dynamic> row) async {
    if (_working || !_authorized || widget.roleCode != 'owner') return;
    final businessId = widget.businessId;
    final kind = row['kind'] == 'estimate' ? 'estimate' : 'invoice';
    final accepted = await showDialog<bool>(context: context, builder: (ctx) =>
      AlertDialog(
        title: Text('Cancel never-uploaded $kind?'),
        content: Text('Remove this local test $kind and any unshared temporary '
            'Job?\n\n${row['customer']}\n${row['id']}\n\n'
            'Attempted uploads, uncertain references and payments are protected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: Text('Cancel $kind')),
        ],
      ),
    );
    if (accepted != true || !mounted || _working || widget.roleCode != 'owner' ||
        widget.businessId != businessId) {
      return;
    }
    setState(() { _working = true; _error = null; _plan = null; });
    try {
      await _cleanup.verifyOwner(businessId, widget.roleCode);
      if (kind == 'estimate') {
        await _drafts.cancelNeverSyncedStandaloneEstimate(businessId, row['id'] as String);
      } else {
        await _drafts.cancelNeverSyncedQuickInvoice(businessId, row['id'] as String);
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
    if (mounted && _error == null) await _refresh();
  }

  Widget _previewCard(TestJobCleanupPlan plan) => Card(
    margin: const EdgeInsets.all(12),
    child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PREVIEW · ${plan.jobNumber}', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        SelectableText('Job ID: ${plan.jobId}'),
        Text('${plan.documents.length} linked documents; customers and vehicles are kept.'),
        for (final document in plan.documents) ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('${document['kind']} ${document['number'] ?? '(unnumbered)'}'),
          subtitle: Text('ID: ${document['id']}\n'
              '${document['status']} · Total: ${document['total']}'),
          isThreeLine: true,
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('Reference checks (${plan.dependencies.length} tables)'),
          children: [
            for (final entry in plan.dependencies.entries)
              ListTile(dense: true, title: Text(entry.key),
                trailing: Text('${entry.value}')),
          ],
        ),
        const SizedBox(height: 8),
        if (!plan.canDelete) ...[
          const Text('LOCKED', style: TextStyle(fontWeight: FontWeight.bold)),
          for (final reason in plan.blockedReasons) Text('• $reason'),
        ] else ...[
          const Text('Safety checks passed for this preview. Explicit test '
              'confirmation is still required. The server checks again atomically.'),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _working ? null : () => _delete(plan),
            icon: const Icon(Icons.delete_forever),
            label: const Text('Confirm test cleanup…'),
          ),
        ],
      ],
    )),
  );

  @override
  Widget build(BuildContext context) {
    if (widget.roleCode != 'owner') {
      return Scaffold(
        appBar: AppBar(title: const Text('Delete test jobs')),
        body: const Center(child: Text('Owner access required.')),
      );
    }
    final matches = _jobs.where((job) => _query.isEmpty ||
      '${job['job_number']} ${job['customer_name']} ${job['title']} ${job['id']}'
          .toLowerCase().contains(_query)).toList();
    final visible = matches.take(50);
    return Scaffold(
      appBar: AppBar(title: const Text('Delete test jobs'), actions: [
        IconButton(onPressed: _working ? null : _refresh,
          tooltip: 'Refresh', icon: const Icon(Icons.refresh)),
      ]),
      body: RefreshIndicator(onRefresh: _refresh, child: ListView(children: [
        if (_working) const LinearProgressIndicator(),
        const ListTile(
          title: Text('Owner-only PREVIEW and guarded cleanup'),
          subtitle: Text('Preview one Job at a time. Nothing is selected automatically. '
              'Payment, external reference, unknown sync and service history checks '
              'must pass. Deletion remains locked until all devices have the safe '
              'cleanup update.\n\nProtected real records: J7, J11, J12; invoices '
              '6331, 6332, 6334; estimate 1997.'),
        ),
        if (_error != null) ListTile(leading: const Icon(Icons.warning_amber),
          title: Text(_error!)),
        if (_success != null) ListTile(leading: const Icon(Icons.check_circle_outline),
          title: Text(_success!)),
        if (_plan != null) _previewCard(_plan!),
        if (_authorized) ...[
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: TextField(
            onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
            decoration: const InputDecoration(labelText: 'Find a Job to preview',
              prefixIcon: Icon(Icons.search)),
          )),
          if (_jobs.isEmpty) const ListTile(title: Text('No server Jobs found')),
          if (matches.length > 50) ListTile(title: Text(
            'Showing 50 of ${matches.length} Jobs. Search to find an older Job.')),
          for (final job in visible) ListTile(
            title: Text('${job['job_number'] ?? 'Job'} · ${job['customer_name'] ?? ''}'),
            subtitle: Text('${job['title'] ?? ''}\n${job['id']}'),
            isThreeLine: true,
            trailing: OutlinedButton(onPressed: _working ? null : () => _preview(job),
              child: const Text('Preview')),
          ),
        ],
        if (_localDrafts.isNotEmpty) ...[
            const Divider(),
            const ListTile(title: Text('Pending local documents · read-only preview'),
              subtitle: Text('Available while offline. Cancellation requires a fresh '
                  'online Owner check and never-uploaded document safety checks.')),
            for (final row in _localDrafts) ListTile(
              title: Text('${row['customer']} · ${row['kind']}'),
              subtitle: Text('${row['id']}\nTotal: ${row['total']} · ${row['sync_state']} · Queued: ${row['queued']}'),
              isThreeLine: true,
              trailing: IconButton(
                tooltip: 'Cancel local document after safety checks',
                onPressed: _working || !_authorized || row['local'] != true
                    ? null : () => _cancelLocal(row),
                icon: const Icon(Icons.delete_outline)),
            ),
        ],
      ])),
    );
  }
}


class _CleanupConfirmationDialog extends StatefulWidget {
  const _CleanupConfirmationDialog({required this.plan});
  final TestJobCleanupPlan plan;
  @override
  State<_CleanupConfirmationDialog> createState() => _CleanupConfirmationDialogState();
}

class _CleanupConfirmationDialogState extends State<_CleanupConfirmationDialog> {
  final _controller = TextEditingController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    return AlertDialog(
      title: Text('Permanently delete test ${plan.jobNumber}?'),
      content: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Delete this Job and all ${plan.documents.length} linked '
              'documents listed in the preview. This cannot be undone. '
              'Customers and vehicles are kept.\n\n'
              'Only continue if you have verified these are test records '
              'and every device is updated and synchronized.\n\n'
              'Type ${plan.confirmationText} to confirm:'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Exact confirmation'),
          ),
        ],
      )),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Keep')),
        FilledButton(
          onPressed: _controller.text == plan.confirmationText
              ? () => Navigator.pop(context, _controller.text) : null,
          child: const Text('Delete test records'),
        ),
      ],
    );
  }
}
