import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/payroll_payment_contract.dart';
import '../../services/local_job_access_history.dart';
import '../../services/local_payroll_check_proof_service.dart';
import '../../services/local_payroll_draft_store.dart';

/// Owner-only, local-only preparation of payroll payments.
/// NO financial transactions, payroll posting or server sync occurs here.
class PayrollDraftsScreen extends StatefulWidget {
  const PayrollDraftsScreen({
    super.key,
    required this.businessId,
    required this.isOwner,
    required this.employees,
  });

  final String businessId;
  final bool isOwner;
  final List<Map<String, dynamic>> employees;

  @override
  State<PayrollDraftsScreen> createState() => _PayrollDraftsScreenState();
}

class _PayrollDraftsScreenState extends State<PayrollDraftsScreen> {
  final _drafts = LocalPayrollDraftStore();
  final _proofs = LocalPayrollCheckProofService();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _rng = Random.secure();

  List<PayrollPaymentDraft> _saved = const [];
  String? _employeeId;
  String _methodId = 'draft-cash';
  DateTime _paymentDate = DateTime.now();
  String? _operationId;
  PayrollPaymentDraft? _editing;
  XFile? _selectedCheck;
  bool _busy = false;
  bool _loading = true;
  String? _message;

  String? get _ownerId => LocalJobAccessHistory.currentUserId;
  bool get _authorized => widget.isOwner && _ownerId != null;

  PayrollPaymentMethod _method(String id) {
    final names = <String, (String, PayrollPaymentMethodKind)>{
      'draft-cash': ('Cash', PayrollPaymentMethodKind.cash),
      'draft-check': ('Check', PayrollPaymentMethodKind.check),
      'draft-zelle': ('Zelle', PayrollPaymentMethodKind.zelle),
      'draft-ach': ('ACH / Bank Transfer', PayrollPaymentMethodKind.ach),
    };
    final choice = names[id] ?? names['draft-cash']!;
    return PayrollPaymentMethod(
      id: id, businessId: widget.businessId,
      label: choice.$1, kind: choice.$2,
      enabled: true, sortOrder: 0, version: 1,
    );
  }

  String get _weekStart {
    final day = DateTime(_paymentDate.year, _paymentDate.month, _paymentDate.day);
    final start = day.subtract(Duration(days: day.weekday - DateTime.monday));
    return DateFormat('yyyy-MM-dd').format(start);
  }

  String _employeeName(String id) {
    for (final e in widget.employees) {
      if (e['id']?.toString() == id) return e['name']?.toString() ?? 'Employee';
    }
    return 'Employee (historical ID)';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_authorized) {
      if (mounted) setState(() { _loading = false; _message = 'Owner sign-in required.'; });
      return;
    }
    try {
      final rows = await _drafts.load(
        isOwner: true, businessId: widget.businessId, ownerUserId: _ownerId!,
      );
      if (!mounted) return;
      setState(() {
        _saved = rows;
        _loading = false;
        _message = null;
      });
    } catch (error) {
      if (mounted) setState(() { _loading = false; _message = error.toString(); });
    }
  }

  void _startNew() {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    final suffix = _rng.nextInt(1 << 32).toRadixString(16);
    setState(() {
      _editing = null;
      _operationId = 'local-payroll-$now-$suffix';
      _employeeId = null;
      _methodId = 'draft-cash';
      _paymentDate = DateTime.now();
      _selectedCheck = null;
      _amount.clear();
      _reference.clear();
      _message = null;
    });
  }

  void _openDraft(PayrollPaymentDraft draft) {
    setState(() {
      _editing = draft;
      _operationId = draft.operationId;
      _employeeId = draft.employeeId;
      _methodId = draft.methodId;
      _paymentDate = draft.paymentDate.toLocal();
      _selectedCheck = null;
      _amount.text = (draft.amountCents / 100).toStringAsFixed(2);
      _reference.text = draft.reference ?? '';
      _message = null;
    });
  }

  PayrollPaymentDraft? _draftFromForm() {
    final id = _employeeId;
    final op = _operationId;
    final raw = _amount.text.trim();
    final value = double.tryParse(raw);
    if (id == null || id.isEmpty || op == null || op.isEmpty ||
        value == null || !value.isFinite || value <= 0 ||
        !RegExp(r'^\\d{1,8}(?:\\.\\d{1,2})?$').hasMatch(raw)) {
      setState(() => _message = 'Choose an employee and enter a valid amount.');
      return null;
    }
    final cents = (value * 100).round();
    final previous = _editing;
    final retainProof = previous != null &&
        previous.methodId == _methodId && _selectedCheck == null;
    return PayrollPaymentDraft(
      businessId: widget.businessId,
      employeeId: id,
      operationId: op,
      methodId: _methodId,
      methodLabelSnapshot: _method(_methodId).label,
      amountCents: cents,
      paymentDate: _paymentDate,
      payrollWeekKey: _weekStart,
      reference: _reference.text.trim().isEmpty ? null : _reference.text.trim(),
      checkProofAttachmentId: retainProof ? previous.checkProofAttachmentId : null,
      checkProofDurablyStored: retainProof && previous.checkProofDurablyStored,
      checkProofSizeBytes: retainProof ? previous.checkProofSizeBytes : null,
      checkProofSha256: retainProof ? previous.checkProofSha256 : null,
    );
  }

  Future<void> _saveDraft() async {
    if (!_authorized || _busy) return;
    final draft = _draftFromForm();
    if (draft == null) return;
    setState(() { _busy = true; _message = null; });
    try {
      if (_methodId == 'draft-check' && _selectedCheck != null) {
        await _proofs.stageForDraft(
          isOwner: true, ownerUserId: _ownerId!, draft: draft,
          method: _method(_methodId), selectedPhoto: _selectedCheck!,
        );
      } else {
        await _drafts.save(
          isOwner: true, ownerUserId: _ownerId!, draft: draft,
        );
      }
      if (!mounted) return;
      setState(() {
        _editing = null;
        _operationId = null;
        _selectedCheck = null;
        _message = 'Saved locally as a draft. No payment was made.';
      });
      await _load();
      if (mounted) setState(() {
        _message = 'Saved locally as a draft. No payment was made.';
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'Draft not saved: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choosePhoto(ImageSource source) async {
    try {
      final chosen = await ImagePicker().pickImage(source: source);
      if (!mounted || chosen == null) return;
      setState(() {
        _selectedCheck = chosen;
        _message = 'Photo selected. Save draft to keep it securely on this device.';
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'Photo could not be selected: $error');
    }
  }

  Future<void> _discard(PayrollPaymentDraft draft) async {
    if (!_authorized || _busy) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard unpaid draft?'),
        content: const Text('This only discards the local draft. No posted payment or accounting record is touched.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard draft')),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _drafts.discard(
        isOwner: true, businessId: widget.businessId,
        ownerUserId: _ownerId!, operationId: draft.operationId,
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final staff = widget.employees
        .where((e) => e['id']?.toString().isNotEmpty == true)
        .toList();
    final employeeKnown = _employeeId == null ||
        staff.any((e) => e['id']?.toString() == _employeeId);
    return Scaffold(
      appBar: AppBar(title: const Text('Payroll Drafts')),
      body: !_authorized
          ? const Center(child: Text('Owner sign-in required.'))
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Row(children: [
                      Icon(Icons.lock_outline),
                      SizedBox(width: 10),
                      Expanded(child: Text(
                        'Draft only — NOT PAID. Nothing here creates an expense, sends a payment or syncs payroll.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      )),
                    ]),
                  ),
                ),
                if (_message != null) Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(_message!),
                ),
                if (_operationId == null)
                  FilledButton.icon(
                    onPressed: _busy ? null : _startNew,
                    icon: const Icon(Icons.add),
                    label: const Text('New payroll draft'),
                  )
                else ...[
                  const SizedBox(height: 8),
                  Text('Prepare unpaid draft', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: ValueKey('employee-$_employeeId'),
                    initialValue: employeeKnown ? _employeeId : null,
                    decoration: const InputDecoration(
                      labelText: 'Employee', border: OutlineInputBorder(),
                    ),
                    items: staff.map((e) => DropdownMenuItem<String>(
                      value: e['id'].toString(),
                      child: Text(e['name']?.toString() ?? 'Employee'),
                    )).toList(),
                    onChanged: _busy ? null : (v) => setState(() => _employeeId = v),
                  ),
                  if (!employeeKnown) const Padding(
                    padding: EdgeInsets.all(top: 5),
                    child: Text('This employee is not in the loaded roster. Saving is disabled.'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey('method-$_methodId'),
                    initialValue: _methodId,
                    decoration: const InputDecoration(
                      labelText: 'Payment method (draft choice)',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'draft-cash', child: Text('Cash')),
                      DropdownMenuItem(value: 'draft-check', child: Text('Check')),
                      DropdownMenuItem(value: 'draft-zelle', child: Text('Zelle')),
                      DropdownMenuItem(value: 'draft-ach', child: Text('ACH / Bank Transfer')),
                    ],
                    onChanged: _busy ? null : (v) {
                      if (v != null) setState(() { _methodId = v; _selectedCheck = null; });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _amount,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Amount (USD)', prefixText: '\$ ',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () async {
                      final chosen = await showDatePicker(
                        context: context,
                        initialDate: _paymentDate,
                        firstDate: DateTime(2015),
                        lastDate: DateTime(2100),
                      );
                      if (chosen != null && mounted) setState(() => _paymentDate = chosen);
                    },
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text('Payment date: ${DateFormat('MMM d, yyyy').format(_paymentDate)}'),
                  ),
                  const SizedBox(height: 6),
                  Text('Payroll week starts $_weekStart'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _reference,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Check/reference (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_methodId == 'draft-check') ...[
                    const SizedBox(height: 12),
                    const Text('Check photo is required before future payment posting.'),
                    Wrap(spacing: 8, children: [
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _choosePhoto(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('Take photo'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _choosePhoto(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Choose photo'),
                      ),
                    ]),
                    if (_selectedCheck != null)
                      Text('Selected: ${_selectedCheck!.name}'),
                    if (_selectedCheck == null && _editing?.checkProofDurablyStored == true)
                      const Text('Existing saved proof retained if the method is unchanged.'),
                  ],
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: _busy || !employeeKnown ? null : _saveDraft,
                    child: const Text('Save local draft — NOT PAID'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => setState(() { _operationId = null; _editing = null; _selectedCheck = null; }),
                    child: const Text('Cancel editing'),
                  ),
                ],
                const Divider(height: 36),
                Text('Saved local drafts', style: Theme.of(context).textTheme.titleMedium),
                if (_saved.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text('No unpaid drafts on this device.'),
                  ),
                for (final d in _saved)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.edit_note_outlined),
                      title: Text(_employeeName(d.employeeId)),
                      subtitle: Text('${d.methodLabelSnapshot} · ${DateFormat('MMM d, yyyy').format(d.paymentDate.toLocal())}\nNOT PAID · Local only'),
                      isThreeLine: true,
                      trailing: Wrap(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          tooltip: 'Edit unpaid draft',
                          onPressed: _busy ? null : () => _openDraft(d),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Discard unpaid draft',
                          onPressed: _busy ? null : () => _discard(d),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ]),
                      onTap: _busy ? null : () => _openDraft(d),
                    ),
                  ),
              ],
            ),
    );
  }
}
