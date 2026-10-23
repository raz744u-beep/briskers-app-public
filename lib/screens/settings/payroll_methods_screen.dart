import 'package:flutter/material.dart';

import '../../core/payroll_payment_contract.dart';
import '../../services/payroll_owner_session.dart';
import '../../services/local_payroll_method_store.dart';

class PayrollMethodsScreen extends StatefulWidget {
  const PayrollMethodsScreen({
    super.key,
    required this.businessId,
    required this.isOwner,
    required this.employees,
  });
  final String businessId;
  final bool isOwner;
  final List<Map<String, dynamic>> employees;

  @override
  State<PayrollMethodsScreen> createState() => _PayrollMethodsScreenState();
}

class _PayrollMethodsScreenState extends State<PayrollMethodsScreen> {
  final _store = LocalPayrollMethodStore();
  List<PayrollPaymentMethod> _methods = [];
  Map<String, String> _defaults = {};
  bool _busy = true;
  String? _error;
  late final PayrollOwnerSession _session;
  Route<dynamic>? _dialog;
  String? get _owner => _session.ownerUserId;
  bool get _allowed =>
      _session.allows(businessId: widget.businessId, isOwner: widget.isOwner);

  void _invalidate() {
    final dialog = _dialog;
    _dialog = null;
    if (dialog?.navigator != null) dialog!.navigator!.removeRoute(dialog);
    if (mounted) {
      setState(() {
        _methods = [];
        _defaults = {};
        _busy = false;
        _error = 'Owner session changed. Reopen payroll after signing in.';
      });
    }
  }

  @override
  void didUpdateWidget(covariant PayrollMethodsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId || !widget.isOwner) {
      _session.invalidate();
    }
  }

  @override
  void dispose() {
    _session.removeListener(_invalidate);
    _session.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _session = PayrollOwnerSession(
      businessId: widget.businessId,
      isOwner: widget.isOwner,
    );
    _session.addListener(_invalidate);
    _initialLoad();
  }

  Future<void> _initialLoad() async {
    try {
      await _reload();
    } catch (_) {
      if (mounted && _allowed) {
        setState(() {
          _busy = false;
          _error = 'Could not load local payment methods. Reopen to try again.';
        });
      }
    }
  }

  Future<void> _reload() async {
    if (!_allowed) return;
    final methods = await _store.load(
      isOwner: widget.isOwner,
      businessId: widget.businessId,
      ownerUserId: _owner!,
    );
    if (!mounted || !_allowed) return;
    final defaults = await _store.defaults(
      isOwner: widget.isOwner,
      businessId: widget.businessId,
      ownerUserId: _owner!,
    );
    if (mounted && _allowed) {
      setState(() {
        _methods = methods;
        _defaults = defaults;
        _busy = false;
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (!_allowed || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _reload();
    } catch (_) {
      if (mounted && _allowed) {
        setState(() => _error = 'Could not save. Reload and try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([PayrollPaymentMethod? method]) async {
    if (!_allowed || _busy) return;
    var label = method?.label ?? '';
    var kind = method?.kind ?? PayrollPaymentMethodKind.custom;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) {
        _dialog = ModalRoute.of(context);
        return StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(
              method == null ? 'Add payment method' : 'Rename payment method',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: label,
                  onChanged: (value) => label = value,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                if (method == null)
                  DropdownButtonFormField<PayrollPaymentMethodKind>(
                    initialValue: kind,
                    decoration: const InputDecoration(
                      labelText: 'Type (cannot change later)',
                    ),
                    items: PayrollPaymentMethodKind.values
                        .map(
                          (k) =>
                              DropdownMenuItem(value: k, child: Text(k.name)),
                        )
                        .toList(),
                    onChanged: (v) => update(() => kind = v ?? kind),
                  ),
                const Text(
                  'Check methods always require a photo, even after renaming.',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
    _dialog = null;
    if (accepted != true || !mounted || !_allowed) return;
    await _run(
      () => method == null
          ? _store.add(
              isOwner: widget.isOwner,
              businessId: widget.businessId,
              ownerUserId: _owner!,
              label: label,
              kind: kind,
            )
          : _store.update(
              isOwner: widget.isOwner,
              ownerUserId: _owner!,
              method: method,
              label: label,
              enabled: method.enabled,
            ),
    );
  }

  Future<void> _move(int index, int direction) => _run(() async {
    final ids = _methods.map((m) => m.id).toList();
    final id = ids.removeAt(index);
    ids.insert(index + direction, id);
    await _store.reorder(
      isOwner: widget.isOwner,
      businessId: widget.businessId,
      ownerUserId: _owner!,
      ids: ids,
    );
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Payroll payment methods')),
    body: !_allowed
        ? const Center(child: Text('Owner sign-in required.'))
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Saved on this device for unpaid drafts. Payroll posting is not available.',
              ),
              if (_error != null) Text(_error!),
              if (_busy) const LinearProgressIndicator(),
              for (var i = 0; i < _methods.length; i++)
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        title: Text(_methods[i].label),
                        subtitle: Text(
                          '${_methods[i].kind.name} · ${_methods[i].enabled ? "Enabled" : "Disabled"}',
                        ),
                        onTap: _busy ? null : () => _edit(_methods[i]),
                        trailing: Switch(
                          value: _methods[i].enabled,
                          onChanged: _busy
                              ? null
                              : (v) => _run(
                                  () => _store.update(
                                    isOwner: widget.isOwner,
                                    ownerUserId: _owner!,
                                    method: _methods[i],
                                    label: _methods[i].label,
                                    enabled: v,
                                  ),
                                ),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: 'Move up',
                            onPressed: _busy || i == 0
                                ? null
                                : () => _move(i, -1),
                            icon: const Icon(Icons.arrow_upward),
                          ),
                          IconButton(
                            tooltip: 'Move down',
                            onPressed: _busy || i == _methods.length - 1
                                ? null
                                : () => _move(i, 1),
                            icon: const Icon(Icons.arrow_downward),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _edit(),
                icon: const Icon(Icons.add),
                label: const Text('Add method'),
              ),
              const Divider(),
              Text(
                'Employee defaults',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Text(
                'Used for new drafts only. Each payment can override this choice. Disabled defaults require a new choice.',
              ),
              for (final employee in widget.employees.where(
                (e) => e['id']?.toString().isNotEmpty == true,
              ))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(
                      '${employee['id']}-${_defaults[employee['id']]}-${_methods.map((m) => m.version).join(',')}',
                    ),
                    initialValue:
                        _methods.any(
                          (m) => m.enabled && m.id == _defaults[employee['id']],
                        )
                        ? _defaults[employee['id']]
                        : '',
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: employee['name']?.toString() ?? 'Employee',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('No available default'),
                      ),
                      ..._methods
                          .where((m) => m.enabled)
                          .map(
                            (m) => DropdownMenuItem(
                              value: m.id,
                              child: Text(m.label),
                            ),
                          ),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) => _run(
                            () => _store.setDefault(
                              isOwner: widget.isOwner,
                              businessId: widget.businessId,
                              ownerUserId: _owner!,
                              employeeId: employee['id'].toString(),
                              methodId: v == '' ? null : v,
                            ),
                          ),
                  ),
                ),
            ],
          ),
  );
}
