import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/payroll_payment_contract.dart';
import '../../services/payroll_owner_session.dart';
import '../../services/local_financial_cache.dart';
import '../../services/local_job_repository.dart';
import '../../services/local_payroll_outbox.dart';
import '../../services/payroll_authoritative_sync.dart';
import '../../services/payroll_posting_gateway.dart';
import '../../local/local_database_provider.dart';
import '../../services/local_payroll_check_proof_service.dart';
import '../../services/local_payroll_draft_store.dart';
import '../../services/local_payroll_method_store.dart';
import 'payroll_methods_screen.dart';
import 'payroll_receipts_screen.dart';
import 'payroll_allocation_dialog.dart';

/// Local-first payment preparation for Owner or server-authorized office.
/// Production posting remains disabled until separate backend approval.
class PayrollDraftsScreen extends StatefulWidget {
  const PayrollDraftsScreen({
    super.key,
    required this.businessId,
    required this.isOwner,
    this.isAuthorizedOffice = false,
    required this.employees,
    this.ownerSession,
    this.draftStore,
    this.methodStore,
    this.proofService,
    this.loadSourceAccounts,
    this.authoritativeSync,
    this.authoritativeGateway,
    this.outbox,
    this.postingGateway,
  });

  final String businessId;
  final bool isOwner;
  final bool isAuthorizedOffice;

  final List<Map<String, dynamic>> employees;
  final PayrollOwnerSession? ownerSession;
  final LocalPayrollDraftStore? draftStore;
  final LocalPayrollMethodStore? methodStore;
  final LocalPayrollCheckProofService? proofService;
  final PayrollAuthoritativeSync? authoritativeSync;
  final PayrollAuthoritativeGateway? authoritativeGateway;
  final LocalPayrollOutbox? outbox;
  final PayrollPostingGateway? postingGateway;
  final Future<List<Map<String, dynamic>>> Function()? loadSourceAccounts;

  @override
  State<PayrollDraftsScreen> createState() => _PayrollDraftsScreenState();
}

class _PayrollDraftsScreenState extends State<PayrollDraftsScreen> {
  late final LocalPayrollDraftStore _drafts;
  late final LocalPayrollCheckProofService _proofs;
  late final PayrollOwnerSession _session;
  Route<dynamic>? _dialog;
  bool _proofIntact = false;
  bool _hasServerCatalog = false;
  late final LocalPayrollOutbox _outbox;
  late final PayrollPostingGateway _postingGateway;
  Set<String> _frozenOperations = {};
  bool get _canManage => widget.isOwner || widget.isAuthorizedOffice;
  DateTime? _payrollPeriod;
  List<PayrollLaborAllocation> _allocations = [];
  List<Map<String, dynamic>> _eligibleLabor = [];
  bool get _postingApproved =>
      _postingGateway is PayrollPostingActivation &&
      (_postingGateway as PayrollPostingActivation).canQueueOffline;
  PayrollAuthoritativeSync? _remote;
  late final PayrollAuthoritativeGateway _remoteGateway;
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  late final LocalPayrollMethodStore _catalog;
  List<PayrollPaymentMethod> _methods = [];
  Map<String, String> _defaults = {};

  List<PayrollPaymentDraft> _saved = const [];
  String? _employeeId;
  String? _methodId;
  String? _sourceAccountId;
  List<Map<String, dynamic>> _accounts = [];
  DateTime _paymentDate = DateTime.now();
  String? _operationId;
  PayrollPaymentDraft? _editing;
  XFile? _selectedCheck;
  bool _busy = false;
  bool _loading = true;
  String? _message;

  String? get _ownerId => _session.ownerUserId;
  bool get _authorized =>
      _session.allows(businessId: widget.businessId, isOwner: _canManage);

  void _invalidate() {
    final dialog = _dialog;
    _dialog = null;
    if (dialog?.navigator != null) dialog!.navigator!.removeRoute(dialog);
    if (!mounted) return;
    setState(() {
      _saved = [];
      _hasServerCatalog = false;
      _frozenOperations = {};
      _payrollPeriod = null;
      _allocations = [];
      _accounts = [];
      _sourceAccountId = null;
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
    if (oldWidget.businessId != widget.businessId || !_canManage) {
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
        builder: (_) => _hasServerCatalog
            ? PayrollReceiptsScreen(
                businessId: widget.businessId,
                isOwner: _canManage,
                employees: widget.employees,
                synchronizer: _remote,
                gateway: _remoteGateway,
                outbox: _outbox,
                postingGateway: _postingGateway,
              )
            : PayrollMethodsScreen(
                businessId: widget.businessId,
                isOwner: _canManage,
                employees: widget.employees,
              ),
      ),
    );
    if (mounted) await _load();
  }

  String get _weekStart {
    final selected = _payrollPeriod ?? _paymentDate;
    final day = DateTime(selected.year, selected.month, selected.day);
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
        PayrollOwnerSession(businessId: widget.businessId, isOwner: _canManage);
    _remote = widget.authoritativeSync;
    _remoteGateway =
        widget.authoritativeGateway ??
        PayrollPostingGatewayV1(
          businessId: widget.businessId,
          isContextCurrent: () => _authorized,
          readProofBytes: (p) => _proofs.readFrozenProofBytes(
            isOwner: _canManage,
            ownerUserId: _ownerId!,
            businessId: widget.businessId,
            operationId: p['operation_id'] as String,
            digest: p['proof_sha256'] as String,
            byteSize: p['proof_size'] as int,
          ),
        );
    _postingGateway =
        widget.postingGateway ??
        (_remoteGateway is PayrollPostingGateway
            ? _remoteGateway as PayrollPostingGateway
            : PayrollPostingGatewayV1(
                businessId: widget.businessId,
                isContextCurrent: () => _authorized,
                readProofBytes: (_) async =>
                    throw StateError('Posting unavailable.'),
              ));
    _outbox =
        widget.outbox ??
        LocalPayrollOutbox(
          database: localDatabase,
          businessId: widget.businessId,
          ownerUserId: _ownerId ?? '',
          isContextCurrent: () => mounted && _authorized,
          verifyLocalProof: (d) => _proofs.isProofIntact(
            isOwner: _canManage,
            ownerUserId: _ownerId!,
            draft: d,
          ),
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

  Future<Map<String, dynamic>?> _confirmedCatalog() async {
    var supported = false;
    try {
      supported = await _remoteGateway.supportsReviewedPayrollV1(
        widget.businessId,
      );
    } catch (_) {
      supported = true;
    }
    if (!mounted || !_authorized) return null;
    if (!supported && _remote == null) return null;
    _remote ??= PayrollAuthoritativeSync(
      database: localDatabase,
      businessId: widget.businessId,
      ownerUserId: _ownerId!,
      isContextCurrent: () => _authorized,
    );
    try {
      if (supported) await _remote!.synchronize(_remoteGateway);
    } catch (_) {
      /* Keep confirmed cache offline. */
    }
    if (!mounted || !_authorized) return null;
    return _remote!.catalog();
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
        isOwner: _canManage,
        businessId: widget.businessId,
        ownerUserId: _ownerId!,
      );
      if (!mounted || !_authorized) return;
      final defaults = await _catalog.defaults(
        isOwner: _canManage,
        businessId: widget.businessId,
        ownerUserId: _ownerId!,
      );
      if (!mounted || !_authorized) return;
      var accounts = <Map<String, dynamic>>[];
      try {
        final load = widget.loadSourceAccounts;
        accounts = load != null
            ? await load()
            : List<dynamic>.from(
                    (await LocalFinancialCache().loadOptions(
                          widget.businessId,
                        ))['accounts'] ??
                        const [],
                  )
                  .whereType<Map>()
                  .map((row) => Map<String, dynamic>.from(row))
                  .toList();
      } catch (_) {
        // A missing cache must not prevent opening an existing unpaid draft.
      }
      if (!mounted || !_authorized) return;
      final remote = await _confirmedCatalog();
      if (!mounted || !_authorized) return;
      var effectiveMethods = methods;
      var effectiveDefaults = defaults;
      final confirmed = remote?['confirmed'] == true;
      if (confirmed) {
        effectiveMethods = (remote!['methods'] as List)
            .map(
              (m) => PayrollPaymentMethod(
                id: m['client_key'] as String,
                businessId: widget.businessId,
                label: m['label'] as String,
                kind: PayrollPaymentMethodKind.values.byName(
                  m['kind'] as String,
                ),
                enabled: m['enabled'] as bool,
                sortOrder: m['sort_order'] as int,
                version: m['version'] as int,
              ),
            )
            .toList();
        final keys = {
          for (final m in remote['methods'] as List)
            m['id']: m['client_key'] as String,
        };
        effectiveDefaults = {
          for (final d in remote['employee_defaults'] as List)
            d['employee_id'] as String: keys[d['method_id']]!,
        };
      }
      final statuses = await _outbox.statuses();
      if (!mounted || !_authorized) return;
      final unique = <String, Map<String, dynamic>>{};
      for (final account in accounts) {
        final id = account['id']?.toString() ?? '';
        if (id.isNotEmpty &&
            account['active'] != false &&
            (account['business_id'] == null ||
                account['business_id'] == widget.businessId)) {
          unique[id] = account;
        }
      }
      setState(() {
        _accounts = unique.values.toList();
        _frozenOperations = statuses
            .map((r) => r['operation_id'] as String)
            .toSet();
        _hasServerCatalog = confirmed;
        _eligibleLabor = (remote?['eligible_labor'] as List? ?? [])
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
        _methods = effectiveMethods;
        _defaults = effectiveDefaults;
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
      _sourceAccountId = null;
      _operationId = LocalPayrollMethodStore.newIdentity();
      _employeeId = null;
      _methodId = null;
      _paymentDate = DateTime.now();
      _payrollPeriod = null;
      _allocations = [];
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
        isOwner: _canManage,
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
      _sourceAccountId = draft.sourceAccountId;
      _operationId = draft.operationId;
      _employeeId = draft.employeeId;
      _methodId = draft.methodId;
      _paymentDate = draft.paymentDate.toLocal();
      _payrollPeriod = DateTime.tryParse(draft.payrollWeekKey);
      _allocations = List.of(draft.laborAllocations);
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
    if (_allocations.fold<int>(0, (n, a) => n + a.amountCents) > cents) {
      setState(
        () => _message = 'Labor allocations cannot exceed the actual payment.',
      );
      return null;
    }
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
          laborAllocations: _allocations,
          sourceAccountId: _sourceAccountId,
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
      laborAllocations: _allocations,
      sourceAccountId: _sourceAccountId,
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
          isOwner: _canManage,
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

  Future<void> _editAllocations() async {
    if (!_authorized || _busy || _employeeId == null) return;
    final choices = <Map<String, dynamic>>[];
    final jobs = LocalJobRepository();
    for (final row in _eligibleLabor.where(
      (l) => l['employee_id'] == _employeeId,
    )) {
      String? label;
      try {
        label = await jobs.jobNumberForJob(
          widget.businessId,
          row['job_id'] as String,
        );
      } catch (_) {
        /* Unknown job labels require a cache refresh. */
      }
      if (!mounted || !_authorized) return;
      if (label != null) choices.add({...row, 'job_label': label});
    }
    final route = DialogRoute<List<PayrollLaborAllocation>>(
      context: context,
      builder: (_) =>
          PayrollAllocationDialog(labor: choices, selected: _allocations),
    );
    _dialog = route;
    final selected = await Navigator.of(context).push(route);
    _dialog = null;
    if (!mounted || !_authorized || selected == null) return;
    setState(() {
      _allocations = selected;
      _selectedCheck = null;
    });
  }

  Future<void> _confirmPayment(PayrollPaymentDraft draft) async {
    if (!_authorized || _busy || !_postingApproved || !_hasServerCatalog) {
      return;
    }
    final matches = _methods
        .where((m) => m.id == draft.methodId && m.enabled)
        .toList();
    if (matches.length != 1 ||
        !LocalPayrollOutbox.isUuid(draft.sourceAccountId ?? '') ||
        !_accounts.any((a) => a['id'] == draft.sourceAccountId)) {
      setState(
        () => _message =
            'Choose a confirmed payment method and a cached source account before submitting.',
      );
      return;
    }
    if (draft.laborAllocations.any(
      (a) => !_eligibleLabor.any(
        (l) =>
            l['labor_id'] == a.laborId &&
            l['employee_id'] == draft.employeeId &&
            (l['available_cents'] as int) >= a.amountCents,
      ),
    )) {
      setState(
        () => _message =
            'Review unavailable or changed labor allocations before submitting.',
      );
      return;
    }
    final method = matches.single;
    if (draft.validateForSubmission(method).isNotEmpty) {
      setState(
        () => _message =
            'Complete the payment details and save a valid Check photo first.',
      );
      return;
    }
    if (method.requiresCheckPhoto) {
      try {
        await _proofs.readFrozenProofBytes(
          isOwner: _canManage,
          ownerUserId: _ownerId!,
          businessId: widget.businessId,
          operationId: draft.operationId,
          digest: draft.checkProofSha256!,
          byteSize: draft.checkProofSizeBytes!,
        );
      } catch (_) {
        if (mounted && _authorized) {
          setState(
            () => _message =
                'Reselect and save a readable Check photo before submitting.',
          );
        }
        return;
      }
    }
    if (!mounted || !_authorized) return;
    final source =
        _accounts.firstWhere((a) => a['id'] == draft.sourceAccountId)['name'] ??
        'Source account';
    final route = DialogRoute<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm payroll payment'),
        content: Text(
          '${_employeeName(draft.employeeId)}\nUSD ${(draft.amountCents / 100).toStringAsFixed(2)} via ${method.label}\nFrom: $source\nPayment date: ${DateFormat('yyyy-MM-dd').format(draft.paymentDate)}\nPayroll week: ${draft.payrollWeekKey}\nLabor allocated: ${(draft.laborAllocations.fold<int>(0, (n, a) => n + a.amountCents) / 100).toStringAsFixed(2)} across ${draft.laborAllocations.length} earned rows\n\nThe payment stays NOT PAID until a server receipt is confirmed. Submitted details cannot be edited.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep draft'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm and queue'),
          ),
        ],
      ),
    );
    _dialog = route;
    final accepted = await Navigator.of(context).push(route);
    _dialog = null;
    if (!mounted || !_authorized || accepted != true) return;
    setState(() => _busy = true);
    final frozen = PayrollPaymentDraft(
      businessId: draft.businessId,
      employeeId: draft.employeeId,
      operationId: draft.operationId,
      methodId: method.id,
      methodLabelSnapshot: method.label,
      amountCents: draft.amountCents,
      paymentDate: draft.paymentDate,
      payrollWeekKey: draft.payrollWeekKey,
      laborAllocations: draft.laborAllocations,
      sourceAccountId: draft.sourceAccountId,
      reference: draft.reference,
      checkProofAttachmentId: draft.checkProofAttachmentId,
      checkProofDurablyStored: draft.checkProofDurablyStored,
      checkProofSizeBytes: draft.checkProofSizeBytes,
      checkProofSha256: draft.checkProofSha256,
    );
    var queued = false, posted = false;
    try {
      await _drafts.save(
        isOwner: _canManage,
        ownerUserId: _ownerId!,
        draft: frozen,
        isContextCurrent: () => mounted && _authorized,
      );
      await _outbox.enqueue(frozen, method);
      queued = true;
      if (!mounted || !_authorized) return;
      posted = await _outbox.syncOne(frozen.operationId, _postingGateway);
    } catch (_) {
      /* Preserve the frozen operation for an identical retry. */
    }
    if (!mounted || !_authorized) return;
    await _load();
    if (!mounted || !_authorized) return;
    final states = await _outbox.statuses();
    if (!mounted || !_authorized) return;
    final isVoid = states.any(
      (s) => s['operation_id'] == draft.operationId && s['state'] == 'void',
    );
    setState(() {
      _busy = false;
      _message = isVoid
          ? 'Payment void — NOT PAID.'
          : posted
          ? 'Payroll receipt confirmed.'
          : queued
          ? 'Payment queued — NOT PAID. Open receipts to retry when connected.'
          : 'Payment was not queued. Review its details and try again.';
    });
  }

  Future<void> _choosePhoto(ImageSource source) async {
    if (!_authorized || _busy) return;
    try {
      final chosen = await ImagePicker().pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 4000,
        maxHeight: 4000,
        requestFullMetadata: false,
      );
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
    final visibleDrafts = _saved
        .where((d) => !_frozenOperations.contains(d.operationId))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Payroll Drafts')),
      body: !_authorized
          ? const Center(child: Text('Owner sign-in required.'))
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_outline),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _postingApproved
                                ? 'Drafts remain NOT PAID until a server receipt confirms posting. Submitted details cannot be edited.'
                                : 'Draft only — NOT PAID. Nothing here creates an expense, sends a payment or syncs payroll.',
                            style: const TextStyle(fontWeight: FontWeight.w600),
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
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => PayrollReceiptsScreen(
                              businessId: widget.businessId,
                              isOwner: _canManage,
                              employees: widget.employees,
                              synchronizer: _remote,
                              gateway: _remoteGateway,
                              outbox: _outbox,
                              postingGateway: _postingGateway,
                            ),
                          ),
                        ),
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Confirmed payroll receipts'),
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
                            _allocations = [];
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
                    key: ValueKey('source-$_sourceAccountId'),
                    initialValue: _sourceAccountId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText:
                          'Source account (separate from payment method)',
                      border: OutlineInputBorder(),
                      helperText:
                          'Category: Payroll. Account choice does not post a payment.',
                    ),
                    items: [
                      if (_sourceAccountId != null &&
                          !_accounts.any(
                            (a) => a['id']?.toString() == _sourceAccountId,
                          ))
                        DropdownMenuItem(
                          value: _sourceAccountId,
                          child: const Text(
                            'Saved account — unavailable offline',
                          ),
                        ),
                      ..._accounts.map(
                        (a) => DropdownMenuItem(
                          value: a['id'].toString(),
                          child: Text(a['name']?.toString() ?? 'Account'),
                        ),
                      ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) => setState(() {
                            _sourceAccountId = value;
                            _selectedCheck = null;
                          }),
                  ),
                  if (_accounts.isEmpty)
                    const Text(
                      'No account choices cached. Open Financials online to refresh them; the unpaid draft can still be saved.',
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
                              builder: (context, child) {
                                _dialog = ModalRoute.of(context);
                                return child!;
                              },
                            );
                            _dialog = null;
                            if (chosen != null && mounted && _authorized) {
                              setState(() => _paymentDate = chosen);
                            }
                          },
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(
                      'Payment date: ${DateFormat('MMM d, yyyy').format(_paymentDate)}',
                    ),
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            final chosen = await showDatePicker(
                              context: context,
                              initialDate: _payrollPeriod ?? _paymentDate,
                              firstDate: DateTime(2015),
                              lastDate: DateTime(2100),
                              builder: (context, child) {
                                _dialog = ModalRoute.of(context);
                                return child!;
                              },
                            );
                            _dialog = null;
                            if (mounted && _authorized && chosen != null) {
                              setState(() => _payrollPeriod = chosen);
                            }
                          },
                    icon: const Icon(Icons.date_range),
                    label: Text('Payroll week starts $_weekStart'),
                  ),
                  const Text(
                    'Category: Payroll. Source account is verified before posting.',
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
                      'Check photo is required before a payment can be posted.',
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
                  OutlinedButton.icon(
                    onPressed: _busy || _employeeId == null
                        ? null
                        : _editAllocations,
                    icon: const Icon(Icons.link),
                    label: Text(
                      'Earned labor allocations (${_allocations.length})',
                    ),
                  ),
                  const Text(
                    'Unallocated amounts are advances or extra payments. Actual payment is recorded once.',
                  ),
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
                if (visibleDrafts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text('No unpaid drafts on this device.'),
                  ),
                for (final d in visibleDrafts)
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
                          if (_postingApproved &&
                              !_frozenOperations.contains(d.operationId))
                            IconButton(
                              tooltip: 'Confirm payroll payment',
                              onPressed: _busy
                                  ? null
                                  : () => _confirmPayment(d),
                              icon: const Icon(Icons.send_outlined),
                            ),
                          IconButton(
                            tooltip: 'Edit unpaid draft',
                            onPressed:
                                _busy ||
                                    _frozenOperations.contains(d.operationId)
                                ? null
                                : () => _openDraft(d),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: 'Discard unpaid draft',
                            onPressed:
                                _busy ||
                                    _frozenOperations.contains(d.operationId)
                                ? null
                                : () => _discard(d),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                      onTap: _busy || _frozenOperations.contains(d.operationId)
                          ? null
                          : () => _openDraft(d),
                    ),
                  ),
              ],
            ),
    );
  }
}
