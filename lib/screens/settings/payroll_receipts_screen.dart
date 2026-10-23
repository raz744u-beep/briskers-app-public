import 'package:flutter/material.dart';

import '../../local/local_database_provider.dart';
import '../../services/local_payroll_method_store.dart';
import '../../services/local_payroll_outbox.dart';
import '../../services/local_payroll_check_proof_service.dart';
import '../../services/payroll_authoritative_sync.dart';
import '../../services/payroll_owner_session.dart';
import '../../services/payroll_posting_gateway.dart';

/// Reads only authoritative receipts. Drafts and queued payments are never
/// presented as paid. The production gateway remains deployment-gated off.
class PayrollReceiptsScreen extends StatefulWidget {
  const PayrollReceiptsScreen({
    super.key,
    required this.businessId,
    required this.isOwner,
    this.employees = const [],
    this.ownerSession,
    this.synchronizer,
    this.gateway,
    this.outbox,
    this.postingGateway,
  });
  final String businessId;
  final bool isOwner;
  final List<Map<String, dynamic>> employees;
  final PayrollOwnerSession? ownerSession;
  final PayrollAuthoritativeSync? synchronizer;
  final PayrollAuthoritativeGateway? gateway;
  final LocalPayrollOutbox? outbox;
  final PayrollPostingGateway? postingGateway;
  @override
  State<PayrollReceiptsScreen> createState() => _PayrollReceiptsScreenState();
}

class _PayrollReceiptsScreenState extends State<PayrollReceiptsScreen> {
  late final PayrollOwnerSession _session;
  late final PayrollAuthoritativeSync _sync;
  late final PayrollAuthoritativeGateway _gateway;
  late final LocalPayrollOutbox _outbox;
  PayrollPostingGateway? _posting;
  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _methods = [], _receipts = [], _defaults = [];
  bool _busy = true, _available = false;
  int _pending = 0;
  String? _message;
  Route<dynamic>? _dialog;
  bool get _canEdit => _available || _methods.isNotEmpty;
  bool get _allowed =>
      _session.allows(businessId: widget.businessId, isOwner: widget.isOwner);
  @override
  void initState() {
    super.initState();
    _session =
        widget.ownerSession ??
        PayrollOwnerSession(
          businessId: widget.businessId,
          isOwner: widget.isOwner,
        );
    _session.addListener(_invalidate);
    _sync =
        widget.synchronizer ??
        PayrollAuthoritativeSync(
          database: localDatabase,
          businessId: widget.businessId,
          ownerUserId: _session.ownerUserId ?? '',
          isContextCurrent: () => _allowed,
        );
    _gateway =
        widget.gateway ??
        PayrollPostingGatewayV1(
          businessId: widget.businessId,
          isContextCurrent: () => _allowed,
          readProofBytes: (p) =>
              LocalPayrollCheckProofService().readFrozenProofBytes(
                isOwner: widget.isOwner,
                ownerUserId: _session.ownerUserId!,
                businessId: widget.businessId,
                operationId: p['operation_id'] as String,
                digest: p['proof_sha256'] as String,
                byteSize: p['proof_size'] as int,
              ),
        );
    _posting =
        widget.postingGateway ??
        (_gateway is PayrollPostingGateway
            ? _gateway as PayrollPostingGateway
            : null);
    _outbox =
        widget.outbox ??
        LocalPayrollOutbox(
          database: localDatabase,
          businessId: widget.businessId,
          ownerUserId: _session.ownerUserId ?? '',
          isContextCurrent: () => _allowed,
          verifyLocalProof: (_) async => false,
        );
    _reload();
  }

  void _invalidate() {
    final dialog = _dialog;
    _dialog = null;
    if (dialog?.navigator != null) dialog!.navigator!.removeRoute(dialog);
    if (mounted) {
      setState(() {
        _methods = [];
        _payments = [];
        _receipts = [];
        _defaults = [];
        _pending = 0;
        _available = false;
        _busy = false;
        _message = null;
      });
    }
  }

  @override
  void didUpdateWidget(covariant PayrollReceiptsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId || !widget.isOwner) {
      _session.invalidate();
    }
  }

  @override
  void dispose() {
    _session.removeListener(_invalidate);
    if (widget.ownerSession == null) _session.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    if (!_allowed) return;
    try {
      final available = await _gateway.supportsReviewedPayrollV1(
        widget.businessId,
      );
      if (!mounted || !_allowed) return;
      if (available &&
          _posting is PayrollPostingActivation &&
          (_posting as PayrollPostingActivation).canQueueOffline) {
        for (final row in await _outbox.statuses()) {
          if (!mounted || !_allowed) return;
          if (row['state'] == 'queued') {
            try {
              await _outbox.syncOne(row['operation_id'] as String, _posting!);
            } catch (_) {
              /* Leave this operation NOT PAID and continue independent entries. */
            }
          }
        }
      }
      if (available) await _sync.synchronize(_gateway);
      if (!mounted || !_allowed) return;
      final catalog = await _sync.catalog();
      final receipts = await _sync.receipts(includePending: true);
      final payments = await _outbox.statuses();
      final pending = await _sync.pendingCount();
      if (!mounted || !_allowed) return;
      setState(() {
        _available = available;
        _methods = (catalog['methods'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _defaults = (catalog['employee_defaults'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _applyReceipts(receipts, payments);
        _pending = pending;
        _busy = false;
      });
    } catch (_) {
      // Preserve confirmed cache offline; never manufacture a successful sync.
      try {
        final catalog = await _sync.catalog();
        final receipts = await _sync.receipts(includePending: true);
        final payments = await _outbox.statuses();
        final pending = await _sync.pendingCount();
        if (!mounted || !_allowed) return;
        setState(() {
          _methods = (catalog['methods'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _defaults = (catalog['employee_defaults'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _applyReceipts(receipts, payments);
          _pending = pending;
          _busy = false;
          _message =
              'Could not sync. Confirmed receipts remain available offline; pending edits are not confirmed.';
        });
      } catch (_) {
        if (mounted && _allowed) {
          setState(() {
            _busy = false;
            _message = 'Could not load payroll receipts.';
          });
        }
      }
    }
  }

  void _applyReceipts(
    List<Map<String, dynamic>> receipts,
    List<Map<String, dynamic>> payments,
  ) {
    final known = receipts.map((r) => r['transaction_id']).toSet();
    _receipts = [
      ...receipts.where((r) => r['status'] != 'pending'),
      ...payments
          .where(
            (p) =>
                ['posted', 'void'].contains(p['state']) &&
                !known.contains(p['transaction_id']),
          )
          .map((p) => {...p, 'status': p['state'], 'currency_code': 'USD'}),
    ];
    _payments = payments
        .where(
          (p) =>
              p['state'] == 'queued' &&
              !receipts.any(
                (r) =>
                    r['operation_id'] == p['operation_id'] &&
                    r['amount_cents'] == p['amount_cents'] &&
                    r['employee_id'] == p['employee_id'] &&
                    ['posted', 'void'].contains(r['status']),
              ),
        )
        .toList();
  }

  Future<void> _queue(Map<String, dynamic> change) async {
    if (!_allowed || _busy || !_canEdit) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _sync.queueMutation({
        'operation_id': LocalPayrollMethodStore.newIdentity(),
        ...change,
      });
    } catch (_) {
      if (mounted && _allowed) {
        setState(() {
          _busy = false;
          _message = 'Could not save this pending change.';
        });
      }
      return;
    }
    if (mounted && _allowed) await _reload();
  }

  Future<void> _rename(Map<String, dynamic> method) async {
    if (!_allowed || _busy || !_canEdit) return;
    final controller = TextEditingController(text: method['label'] as String);
    final route = DialogRoute<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename payment method'),
        content: TextField(
          controller: controller,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Method name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) Navigator.pop(context, name);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    _dialog = route;
    final label = await Navigator.of(context).push(route);
    _dialog = null;
    controller.dispose();
    if (!mounted || !_allowed || label == null) return;
    await _queue({
      'action': 'edit',
      'method_id': method['id'],
      'expected_version': method['version'],
      'label': label,
      'enabled': method['enabled'],
      'sort_order': method['sort_order'],
    });
  }

  Future<void> _addMethod() async {
    if (!_allowed || _busy || !_canEdit) return;
    final name = TextEditingController();
    var kind = 'custom';
    final route = DialogRoute<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Add shop payment method'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Method name'),
              ),
              DropdownButtonFormField<String>(
                initialValue: kind,
                decoration: const InputDecoration(labelText: 'Method type'),
                items: const ['cash', 'check', 'zelle', 'ach', 'custom']
                    .map(
                      (k) => DropdownMenuItem(
                        value: k,
                        child: Text(
                          k == 'check'
                              ? 'Check — photo required'
                              : k.toUpperCase(),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) update(() => kind = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isNotEmpty) Navigator.pop(context, true);
              },
              child: const Text('Save pending method'),
            ),
          ],
        ),
      ),
    );
    _dialog = route;
    final accepted = await Navigator.of(context).push(route);
    _dialog = null;
    final label = name.text.trim();
    name.dispose();
    if (!mounted || !_allowed || accepted != true) return;
    await _queue({
      'action': 'register',
      'client_key': LocalPayrollMethodStore.newIdentity(),
      'label': label,
      'kind': kind,
    });
  }

  Future<void> _discardPending() async {
    if (!_allowed || _busy) return;
    final route = DialogRoute<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard pending settings edits?'),
        content: const Text(
          'Changes already accepted by the server remain. Confirmed settings will reload. This does not discard payments or drafts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep edits'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard pending edits'),
          ),
        ],
      ),
    );
    _dialog = route;
    final accepted = await Navigator.of(context).push(route);
    _dialog = null;
    if (!mounted || !_allowed || accepted != true) return;
    setState(() => _busy = true);
    try {
      await _sync.discardPendingEdits();
      if (mounted && _allowed) await _reload();
    } catch (_) {
      if (mounted && _allowed) setState(() => _busy = false);
    }
  }

  String _employeeName(dynamic id) {
    for (final e in widget.employees) {
      if (e['id'] == id) return e['name']?.toString() ?? 'Employee';
    }
    return id == null ? 'Employee not recorded' : 'Employee';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Payroll receipts'),
      actions: [
        IconButton(
          tooltip: 'Sync payroll',
          onPressed: _busy || !_allowed
              ? null
              : () {
                  setState(() => _busy = true);
                  _reload();
                },
          icon: const Icon(Icons.sync),
        ),
      ],
    ),
    body: !_allowed
        ? const Center(child: Text('Owner sign-in required.'))
        : _busy
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!_available)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Payroll posting is unavailable. Local drafts remain NOT PAID. Only confirmed server receipts appear here.',
                    ),
                  ),
                ),
              if (_message != null) Text(_message!),
              if (_pending > 0)
                Text('$_pending pending settings changes — not yet confirmed.'),
              if (_pending > 0)
                TextButton(
                  onPressed: _busy ? null : _discardPending,
                  child: const Text('Reload confirmed settings'),
                ),
              if (_payments.isNotEmpty) ...[
                Text(
                  'Queued payments — NOT PAID',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                ..._payments.map(
                  (p) => ListTile(
                    leading: const Icon(Icons.cloud_upload_outlined),
                    title: Text(
                      '${_employeeName(p['employee_id'])} • USD ${((p['amount_cents'] as int) / 100).toStringAsFixed(2)}',
                    ),
                    subtitle: Text(
                      '${p['method_label']} • Awaiting server receipt',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Text(
                'Confirmed receipts',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (_receipts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No confirmed payroll receipts cached.'),
                ),
              ..._receipts.map((r) {
                final label = r['method_label']?.toString().trim();
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.receipt_long),
                    title: Text(
                      '${_employeeName(r['employee_id'])} • ${r['currency_code'] ?? 'Amount'} ${((r['amount_cents'] as int) / 100).toStringAsFixed(2)}',
                    ),
                    subtitle: Text(
                      '${r['status'] == 'void' ? 'Void' : 'Posted'} • ${r['payment_date']}\nMethod: ${label == null || label.isEmpty ? 'Not recorded' : label}',
                    ),
                    isThreeLine: true,
                  ),
                );
              }),
              const SizedBox(height: 16),
              Text(
                'Confirmed shop payment methods',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (_canEdit)
                OutlinedButton.icon(
                  onPressed: _busy ? null : _addMethod,
                  icon: const Icon(Icons.add),
                  label: const Text('Add shop payment method'),
                ),
              ..._methods.map(
                (m) => ListTile(
                  title: Text(m['label'] as String),
                  subtitle: Text(
                    m['enabled'] == true
                        ? 'Enabled'
                        : 'Disabled — history retained',
                  ),
                  trailing: PopupMenuButton<String>(
                    enabled: _canEdit && !_busy,
                    onSelected: (action) {
                      if (action == 'rename') {
                        _rename(m);
                      } else if (action == 'up' || action == 'down') {
                        final index = _methods.indexOf(m);
                        final neighbor =
                            _methods[index + (action == 'up' ? -1 : 1)];
                        _queue({
                          'action': 'edit',
                          'method_id': m['id'],
                          'expected_version': m['version'],
                          'label': m['label'],
                          'enabled': m['enabled'],
                          'sort_order':
                              (neighbor['sort_order'] as int) +
                              (action == 'up' ? -1 : 1),
                        });
                      } else {
                        _queue({
                          'action': 'edit',
                          'method_id': m['id'],
                          'expected_version': m['version'],
                          'label': m['label'],
                          'enabled': m['enabled'] != true,
                          'sort_order': m['sort_order'],
                        });
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'rename',
                        child: Text('Rename'),
                      ),
                      if (_methods.indexOf(m) > 0)
                        const PopupMenuItem(
                          value: 'up',
                          child: Text('Move up'),
                        ),
                      if (_methods.indexOf(m) + 1 < _methods.length)
                        const PopupMenuItem(
                          value: 'down',
                          child: Text('Move down'),
                        ),
                      PopupMenuItem(
                        value: 'toggle',
                        child: Text(
                          m['enabled'] == true ? 'Disable' : 'Enable',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Employee defaults',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              ...widget.employees.map((employee) {
                String? current;
                for (final d in _defaults) {
                  if (d['employee_id'] == employee['id']) {
                    current = d['method_id']?.toString();
                  }
                }
                final choices = _methods
                    .where((m) => m['enabled'] == true)
                    .toList();
                if (!choices.any((m) => m['id'] == current)) current = null;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('server-default-${employee['id']}-$current'),
                    initialValue: current ?? '',
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: employee['name']?.toString() ?? 'Employee',
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: '',
                        child: Text('No default'),
                      ),
                      ...choices.map(
                        (m) => DropdownMenuItem(
                          value: m['id'] as String,
                          child: Text(m['label'] as String),
                        ),
                      ),
                    ],
                    onChanged: !_canEdit || _busy
                        ? null
                        : (method) => _queue({
                            'action': 'default',
                            'employee_id': employee['id'],
                            'method_id': method == '' ? null : method,
                          }),
                  ),
                );
              }),
            ],
          ),
  );
}
