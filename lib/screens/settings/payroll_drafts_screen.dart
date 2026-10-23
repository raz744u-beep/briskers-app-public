import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/payroll_payment_contract.dart';
import '../../services/payroll_owner_session.dart';
import '../../services/local_payroll_check_proof_service.dart';
import '../../services/local_payroll_draft_store.dart';
import '../../services/local_payroll_method_store.dart';
import 'payroll_methods_screen.dart';

/// Owner-only, local-only preparation of payroll payments.
/// NO financial transactions, payroll posting or server sync occurs here.
class PayrollDraftsScreen extends StatefulWidget {
  const PayrollDraftsScreen({
    super.key,
    required this.businessId,
    required this.isOwner,
    required this.employees,
    this.ownerSession,
    this.draftStore,
    this.methodStore,
    this.proofService,
  });

  final String businessId;
  final bool isOwner;
  final List<Map<String, dynamic>> employees;
  final PayrollOwnerSession? ownerSession;
  final LocalPayrollDraftStore? draftStore;
  final LocalPayrollMethodStore? methodStore;
  final LocalPayrollCheckProofService? proofService;

  @override
  State<PayrollDraftsScreen> createState() => _PayrollDraftsScreenState();
}

class _PayrollDraftsScreenState extends State<PayrollDraftsScreen> {
  late final LocalPayrollDraftStore _drafts;
  late final LocalPayrollCheckProofService _proofs;
  late final PayrollOwnerSession _session;
  Route<dynamic>? _dialog;
  bool _proofIntact = false;
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  late final LocalPayrollMethodStore _catalog;
  List<PayrollPaymentMethod> _methods = [];
  Map<String, String> _defaults = {};

  List<PayrollPaymentDraft> _saved = const [];
  String? _employeeId;
  String? _methodId;
  DateTime _paymentDate = DateTime.now();
  String? _operationId;
  PayrollPaymentDraft? _editing;
  XFile? _selectedCheck;
  bool _busy = false;
  bool _loading = true;
  String? _message;

  String? get _ownerId => _session.ownerUserId;
  bool get _authorized =>
      _session.allows(businessId: widget.businessId, isOwner: widget.isOwner);

  void _invalidate() {
    final dialog = _dialog;
    _dialog = null;
    if (dialog?.navigator != null) dialog!.navigator!.removeRoute(dialog);
    if (!mounted) return;
    setState(() {
      _saved = [];
      _methods = [];
      _defaults = {};
      _employeeId = null;
      _methodId = null;
      _operationId = null;
      _editing = null;
      _selectedCheck = null;
      _proofIntact = false;
      _amount.clear();
      _reference.clear();
      _busy = false;
      _loading = false;
      _message = 'Owner session changed. Reopen payroll after signing in.';
    });
  }

  @override
  void didUpdateWidget(covariant PayrollDraftsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId || !widget.isOwner) {
      _session.invalidate();
    }
  }

  PayrollPaymentMethod? get _selectedMethod =>
      PayrollPaymentMethodChoice.resolve(
        businessId: widget.businessId,
        methods: _methods,
        paymentOverrideId: _methodId,
      );

  Future<void> _configureMethods() async {
    if (!_authorized || _busy) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PayrollMethodsScreen(
          businessId: widget.businessId,
          isOwner: widget.isOwner,
          employees: widget.employees,
        ),
      ),
    );
    if (mounted) await _load();
  }

  String get _weekStart {
    final day = DateTime(
      _paymentDate.year,
      _paymentDate.month,
      _paymentDate.day,
    );
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
    _drafts = widget.draftStore ?? LocalPayrollDraftStore();
    _catalog = widget.methodStore ?? LocalPayrollMethodStore();
    _proofs =
        widget.proofService ?? LocalPayrollCheckProofService(drafts: _drafts);
    _session =
        widget.ownerSession ??
        PayrollOwnerSession(
          businessId: widget.businessId,
          isOwner: widget.isOwner,
        );
    _session.addListener(_invalidate);
    _load();
  }

  @override
  void dispose() {
    _session.removeListener(_invalidate);
    if (widget.ownerSession == null) _session.dispose();
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_authorized) {
      if (mounted && _authorized) {
        setState(() {
          _loading = false;
          _message = 'Owner sign-in required.';
        });
      }
      return;
    }
    try {
      final rows = await _drafts.load(
        isOwner: true,
        businessId: widget.businessId,
        ownerUserId: _ownerId!,
      );
      if (!mounted || !_authorized) return;
      final methods = await _catalog.load(
        isOwner: widget.isOwner,
        businessId: widget.businessId,
        ownerUserId: _ownerId!,
      );
      if (!mounted || !_authorized) return;
      final defaults = await _catalog.defaults(
        isOwner: widget.isOwner,
        businessId: widget.businessId,
        ownerUserId: _ownerId!,
      );
      if (!mounted || !_authorized) return;
      setState(() {
        _methods = methods;
        _defaults = defaults;
        _saved = rows;
        _loading = false;
        _message = null;
      });
    } catch (error) {
      if (mounted && _authorized) {
        setState(() {
          _loading = false;
          _message = error.toString();
        });
      }
    }
  }

  void _startNew() {
    if (!_authorized || _busy) return;
    setState(() {
      _editing = null;
      _proofIntact = false;
      _operationId = LocalPayrollMethodStore.newIdentity();
      _employeeId = null;
      _methodId = null;
      _paymentDate = DateTime.now();
      _selectedCheck = null;
      _amount.clear();
      _reference.clear();
      _message = null;
    });
  }

  Future<void> _openDraft(PayrollPaymentDraft draft) async {
    if (!_authorized || _busy) return;
    setState(() => _busy = true);
    var intact = false;
    try {
      intact = await _proofs.isProofIntact(
        isOwner: widget.isOwner,
        ownerUserId: _ownerId!,
        draft: draft,
      );
    } catch (_) {
      /* Unreadable proof must not be presented as valid. */
    }
    if (!mounted || !_authorized) return;
    setState(() {
      _busy = false;
      _proofIntact = intact;
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
    final method = _selectedMethod;
    final id = _employeeId;
    final op = _operationId;
    final raw = _amount.text.trim();
    final value = double.tryParse(raw);
    if (method == null ||
        id == null ||
        id.isEmpty ||
        !widget.employees.any((e) => e['id']?.toString() == id) ||
        op == null ||
        op.isEmpty ||
        value == null ||
        !value.isFinite ||
        value <= 0 ||
        !RegExp(r'^\d{1,8}(?:\.\d{1,2})?$').hasMatch(raw)) {
      setState(
        () => _message =
            'Choose an employee, an enabled method and a valid amount.',
      );
      return null;
    }
    final cents = (value * 100).round();
    final previous = _editing;
    final reference = _reference.text.trim().isEmpty
        ? null
        : _reference.text.trim();
    final retainProof =
        previous != null &&
        _proofIntact &&
        _selectedCheck == null &&
        previous.proofMatchesTerms(
          businessId: widget.businessId,
          employeeId: id,
          operationId: op,
          methodId: method.id,
          amountCents: cents,
          paymentDate: _paymentDate,
          payrollWeekKey: _weekStart,
          sourceAccountId: previous.sourceAccountId,
          reference: reference,
        );
    return PayrollPaymentDraft(
      businessId: widget.businessId,
      employeeId: id,
      operationId: op,
      methodId: method.id,
      methodLabelSnapshot: previous?.methodId == method.id
          ? previous!.methodLabelSnapshot
          : method.label,
      amountCents: cents,
      paymentDate: _paymentDate,
      payrollWeekKey: _weekStart,
      sourceAccountId: previous?.sourceAccountId,
      reference: reference,
      checkProofAttachmentId: retainProof
          ? previous.checkProofAttachmentId
          : null,
      checkProofDurablyStored: retainProof && previous.checkProofDurablyStored,
      checkProofSizeBytes: retainProof ? previous.checkProofSizeBytes : null,
      checkProofSha256: retainProof ? previous.checkProofSha256 : null,
    );
  }

  Future<void> _saveDraft() async {
    if (!_authorized || _busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final editing = _editing;
      if (editing != null && _selectedCheck == null) {
        _proofIntact = await _proofs.isProofIntact(
          isOwner: widget.isOwner,
          ownerUserId: _ownerId!,
          draft: editing,
        );
      }
      if (!mounted || !_authorized) return;
      final draft = _draftFromForm();
      if (draft == null) return;
      if (_selectedMethod?.requiresCheckPhoto == true &&
          _selectedCheck != null) {
        await _proofs.stageForDraft(
          isOwner: true,
          ownerUserId: _ownerId!,
          draft: draft,
          method: _selectedMethod!,
          selectedPhoto: _selectedCheck!,
          isContextCurrent: () => mounted && _authorized,
        );
      } else {
        await _drafts.save(
          isOwner: true,
          ownerUserId: _ownerId!,
          draft: draft,
          isContextCurrent: () => mounted && _authorized,
        );
      }
      if (!mounted || !_authorized) return;
      setState(() {
        _editing = null;
        _operationId = null;
        _selectedCheck = null;
        _message = 'Saved locally as a draft. No payment was made.';
      });
      await _load();
      if (mounted && _authorized) {
        setState(() {
          _message = 'Saved locally as a draft. No payment was made.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = 'Draft not saved: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choosePhoto(ImageSource source) async {
    if (!_authorized || _busy) return;
    try {
      final chosen = await ImagePicker().pickImage(source: source);
      if (!mounted || !_authorized || chosen == null) return;
      setState(() {
        _selectedCheck = chosen;
        _message =
            'Photo selected. Save draft to keep it securely on this device.';
      });
    } catch (error) {
      if (mounted && _authorized) {
        setState(() => _message = 'Photo could not be selected: $error');
      }
    }
  }

  Future<void> _discard(PayrollPaymentDraft draft) async {
    if (!_authorized || _busy) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) {
        _dialog = ModalRoute.of(context);
        return AlertDialog(
          title: const Text('Discard unpaid draft?'),
          content: const Text(
            'This only discards the local draft. No posted payment or accounting record is touched.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard draft'),
            ),
          ],
        );
      },
    );
    _dialog = null;
    if (accepted != true || !mounted || !_authorized) return;
    setState(() => _busy = true);
    try {
      await _drafts.discard(
        isOwner: true,
        businessId: widget.businessId,
        ownerUserId: _ownerId!,
        operationId: draft.operationId,
        isContextCurrent: () => mounted && _authorized,
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
    final employeeKnown =
        _employeeId == null ||
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
                    child: Row(
                      children: [
                        Icon(Icons.lock_outline),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Draft only — NOT PAID. Nothing here creates an expense, sends a payment or syncs payroll.',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _configureMethods,
                  icon: const Icon(Icons.tune),
                  label: const Text('Payment methods & employee defaults'),
                ),
                if (_message != null)
                  Padding(
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
                  Text(
                    'Prepare unpaid draft',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: ValueKey('employee-$_employeeId'),
                    initialValue: employeeKnown ? _employeeId : null,
                    decoration: const InputDecoration(
                      labelText: 'Employee',
                      border: OutlineInputBorder(),
                    ),
                    items: staff
                        .map(
                          (e) => DropdownMenuItem<String>(
                            value: e['id'].toString(),
                            child: Text(e['name']?.toString() ?? 'Employee'),
                          ),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                            _employeeId = v;
                            _methodId = _defaults[v];
                            _selectedCheck = null;
                          }),
                  ),
                  if (!employeeKnown)
                    const Padding(
                      padding: EdgeInsets.only(top: 5),
                      child: Text(
                        'This employee is not in the loaded roster. Saving is disabled.',
                      ),
                    ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey('method-$_methodId'),
                    initialValue: _selectedMethod?.id,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Payment method (draft choice)',
                      border: OutlineInputBorder(),
                    ),
                    items: _methods
                        .where((m) => m.enabled)
                        .map(
                          (m) => DropdownMenuItem(
                            value: m.id,
                            child: Text(m.label),
                          ),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (v) {
                            if (v != null) {
                              setState(() {
                                _methodId = v;
                                _selectedCheck = null;
                              });
                            }
                          },
                  ),
                  if (_selectedMethod == null)
                    const Text(
                      'Choose a method. Unavailable or older draft choices are never inferred.',
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _amount,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Amount (USD)',
                      prefixText: '\$ ',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            final chosen = await showDatePicker(
                              context: context,
                              initialDate: _paymentDate,
                              firstDate: DateTime(2015),
                              lastDate: DateTime(2100),
                            );
                            if (chosen != null && mounted) {
                              setState(() => _paymentDate = chosen);
                            }
                          },
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(
                      'Payment date: ${DateFormat('MMM d, yyyy').format(_paymentDate)}',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('Payroll week starts $_weekStart'),
                  const Text(
                    'Category: Payroll. Source cash/bank account must be verified separately before posting becomes available.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _reference,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Check/reference (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_selectedMethod?.requiresCheckPhoto == true) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Check photo is required before future payment posting.',
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _choosePhoto(ImageSource.camera),
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Take photo'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _choosePhoto(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Choose photo'),
                        ),
                      ],
                    ),
                    if (_selectedCheck != null)
                      Text('Selected: ${_selectedCheck!.name}'),
                    if (_selectedCheck == null &&
                        _editing?.checkProofDurablyStored == true)
                      Text(
                        _proofIntact
                            ? 'Saved photo verified. Changing payment details requires choosing the photo again.'
                            : 'Saved photo is unavailable or damaged. Choose a readable photo again.',
                      ),
                  ],
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: _busy || !employeeKnown ? null : _saveDraft,
                    child: const Text('Save local draft — NOT PAID'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _operationId = null;
                            _editing = null;
                            _selectedCheck = null;
                          }),
                    child: const Text('Cancel editing'),
                  ),
                ],
                const Divider(height: 36),
                Text(
                  'Saved local drafts',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
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
                      subtitle: Text(
                        '${d.methodLabelSnapshot.trim().isEmpty ? 'Unknown / Not recorded' : d.methodLabelSnapshot} · ${DateFormat('MMM d, yyyy').format(d.paymentDate.toLocal())}\nNOT PAID · Local only',
                      ),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
                        ],
                      ),
                      onTap: _busy ? null : () => _openDraft(d),
                    ),
                  ),
              ],
            ),
    );
  }
}
