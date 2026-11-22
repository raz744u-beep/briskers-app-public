import '../../widgets/amount_calculator_dialog.dart';
import '../../core/amount_calculator.dart';
import '../../core/briskers_colors.dart';
import 'payroll_expense_review.dart';
import 'payroll_review_widgets.dart';
import 'approved_tasks_ui.dart';
import 'approved_task_details.dart';
import '../../services/local_job_work_date.dart';
import 'dart:convert';
import '../../services/local_customer_repository.dart';
import '../jobs/job_customer_picker_screen.dart';
import 'general_task_editor.dart';
import '../../services/local_task_reminders.dart';
import '../../widgets/task_schedule_indicator.dart';
import '../../widgets/owner_confirmation_dialog.dart';
import 'service_task_editor.dart';
import '../../services/local_task_schedule.dart';import 'employee_work_review.dart';
import '../../core/work_status_colors.dart';
import '../../services/job_task_bulk_completion.dart';
import '../../services/local_document_detail_cache.dart';
import '../../services/local_invoice_task_store.dart';
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:drift/drift.dart' show Variable;
import '../../services/local_document_repository.dart';
import 'package:intl/intl.dart';


import '../../local/local_database_provider.dart';
import '../../local/briskers_local_database.dart';
import '../../services/payroll_owner_lan.dart';
import '../../services/device_owner_authorization.dart';
import '../../services/invoice_labor_work_summary.dart';
import '../../services/local_owner_authorization.dart';
import '../../services/local_payroll_repository.dart';
import '../../services/employee_nickname_store.dart';
import '../../services/local_task_assignment_store.dart';
import '../../services/offline_job_admin_service.dart';
import '../../services/payroll_lan_enrollment.dart';
import '../../services/payroll_lan_identity.dart';
import '../../services/payroll_owner_lease.dart';
import '../../services/payroll_owner_ledger.dart';
import 'owner_payroll_connection.dart';
import 'payroll_payment_correction.dart';
import 'payroll_ui_scope.dart';
import '../../services/payroll_lan_workflow.dart';
import '../jobs/job_detail_screen.dart';
import '../settings/employee_edit_screen.dart';
import '../jobs/job_document_screen.dart';
import 'payroll_history_panel.dart';
import 'historical_expense_review.dart';
import 'historical_invoice_labor_review.dart';
import '../../services/local_financial_cache.dart' as expenses;
import 'payroll_lan_controls.dart';
import 'weekly_labor_review_screen.dart';
import 'tasks_workspace.dart';
import 'job_scoped_tasks.dart';
import 'task_selection_dialog.dart';
import 'payroll_overview.dart';

enum _AdvanceSection { balance, paycheck, repayment, history }

class OwnerPayrollScreen extends StatefulWidget {
  const OwnerPayrollScreen({
    super.key,
    required this.businessId,
    this.jobId,
    this.invoiceId,
    this.focusLineId,
    this.invoiceLines = const [],
    this.jobInvoiceLabor = const {},
    this.reportsOnly = false,
    this.employeeId,
    this.employeeName,
    this.employeeLegalName,
    this.employeeRole,
    this.employeePayType,
    this.employeeHourlyCents,
    this.employeeActive = true,
    this.openEmployeeDetails,
    this.globalTasks = false,
    this.initialWeek,
    this.initialTab = 0,
    this.database,
    this.unlockOwner,
    this.ownerConnection,
    this.sharedBottomNavigationBar,
  });

  static const enabled = bool.fromEnvironment('BRISKERS_ENABLE_OWNER_PAYROLL');

  final bool reportsOnly;
  final Widget? sharedBottomNavigationBar;
  final String? employeeId;
  final String? employeeName;
  final String? employeeLegalName;
  final String? employeeRole;
  final String? employeePayType;
  final int? employeeHourlyCents;
  final bool employeeActive;
  final VoidCallback? openEmployeeDetails;
  final bool globalTasks;
  final DateTime? initialWeek;
  final int initialTab;
  // Optional integration-test dependencies; normal routes use the app services.
  final BriskersLocalDatabase? database;
  final Future<LocalOwnerGrant> Function(String)? unlockOwner;
  final PayrollOwnerLan? ownerConnection;
  final String businessId;
  final String? jobId;
  final String? invoiceId;
  final String? focusLineId;
  final List<Map<String, dynamic>> invoiceLines;
  final Map<String, List<Map<String, dynamic>>> jobInvoiceLabor;

  @override
  State<OwnerPayrollScreen> createState() => _OwnerPayrollScreenState();
}

class _OwnerPayrollScreenState extends State<OwnerPayrollScreen> with WidgetsBindingObserver {
  BriskersLocalDatabase get _db => widget.database ?? PayrollUiScope.of(context)?.database ?? localDatabase;
  LocalOwnerGrant? _grant;
  bool _viewAuthorized=false;
  bool _debugOwnerView=false;
  OwnerSessionIdentity? _viewIdentity;
  bool get _canView=>_viewAuthorized && (_debugOwnerView || _viewIdentity?.matches(
    DeviceOwnerAuthorization.instance.currentIdentity(),)==true);
  LocalPayrollRepository get _viewRepository => _taskEditRepository;
  // Editing a task status is not a payroll disbursement. Guard against
  // sign-out and business identity changes throughout the local operation.
  late final _taskEditRepository = LocalPayrollRepository(
    _db, business: widget.businessId, owner: true,
    assertOwnerGrant: () {
      if (!_canView) throw StateError('Sign in as Owner to edit tasks.');
    },
  );
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _work = [];
  // Display history can include pre-cutover work, but all new payroll
  // calculations must explicitly exclude archived historical allocations.
  List<Map<String,dynamic>> get _currentPayrollWork =>
      _work.where((row)=>row['archived_labor']!=1).toList();
  List<Map<String, dynamic>> _taskSources = [];
  Map<String,dynamic>? _workspaceJob;
  List<Map<String, dynamic>> _history = [];
  Map<String, VerifiedPayrollWeek>? _verifiedWeeks;
  List<Map<String, dynamic>> _overviewPayments = [];
  List<Map<String, dynamic>> _pendingPayments = [];
  bool _refreshingOwnerState = false;
  bool _loadingLocal = false;
  bool _hasLocalData = false;
  bool _reportsLoaded = false;
  bool _backfillActive=false,_backfillDone=false;
  int _checkedInvoices=0,_recoveredTasks=0,_unavailableInvoices=0;
  bool _authorizing = false;
  int _loadGeneration = 0;
  String _loadStage = 'saved payroll';
  Future<void>? _localRead;

  String? _employee;
  DateTime _week = DateTime.now();
  int? _advanceBalance;
  int _advanceWriteRevision = 0;
  List<Map<String, dynamic>> _repayments = [];
  List<Map<String, dynamic>> _generalTasks = [];

  int _draftRevision = 0;
  String? _carryReview;
  bool? _advanceExpanded;
  _AdvanceSection? _advanceSection;
  bool _confirmingBalance = false;
  String? _advanceError;
  int? _openingAdvance;
  List<Map<String, dynamic>> _advanceAdjustments = [];
  String? _balanceOperation;
  String? _repaymentOperation;
  bool _hasAdvanceHistory = false;
  final _balanceReason = TextEditingController();
  final _opening = TextEditingController();
  final _weeklyBasePreview = TextEditingController(text: '0.00');
  final _hourlySupplementPreview = TextEditingController(text: '0.00');
  final _approvedSupplementHours = TextEditingController(text: '0.00');
  final _weeklyAdjustmentPreview = TextEditingController(text: '0.00');
  bool _laborAdditionalToBase = false;
  bool _weeklyDefaultsLoaded = false;
  bool _settlingWeekly = false;
  final _repayment = TextEditingController();
  final _repaymentNote = TextEditingController();
  DateTime _repaymentDate = DateTime.now();
  String _repaymentMethod = 'Cash';
  static final _currency = NumberFormat.simpleCurrency(locale: 'en_US');
  String _money(int cents) => _currency.format(cents / 100);
  String _moneyNullable(int? cents) => cents == null ? '—' : _money(cents);
  String? _error;
  bool _busy = false;
  Timer? _lockCheck;
  final _historyUnlocked = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _week = widget.initialWeek ?? DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_){
      if(mounted)unawaited(_openSavedOwnerView());
    });
    // An Owner session, not a two-minute device unlock, governs Payroll.
    // Sign-out and account switching are checked by _canView / _assertOwner.
  }

  Future<LocalOwnerGrant> _signedInOwnerGrant() {
    // In widget tests, the explicit debug fixture supplies its simulated
    // saved Owner session. Release code always verifies the real signed-in
    // Owner identity and business role without a second OS challenge.
    if (kDebugMode && _debugOwnerView) {
      final simulatedSession =
          widget.unlockOwner ?? PayrollUiScope.of(context)?.unlock;
      if (simulatedSession != null) {
        return simulatedSession(widget.businessId);
      }
    }
    return DeviceOwnerAuthorization.instance.authority
        .authorizeSession(widget.businessId);
  }

  Future<void> _openSavedOwnerView() async {
    // Debug-only injected owner fixture never bypasses release identity checks.
    final debugOwner=kDebugMode && (PayrollUiScope.of(context)?.debugAllowOwnerView ?? false);
    final identity=DeviceOwnerAuthorization.instance.currentIdentity();
    final allowed=debugOwner || await DeviceOwnerAuthorization.instance.canViewSavedOwnerPayroll(widget.businessId,);
    if(!mounted)return;
    final same=debugOwner || identity?.matches(DeviceOwnerAuthorization.instance.currentIdentity(),)==true;
    setState((){
      _debugOwnerView=debugOwner;
      _viewAuthorized=allowed && same;
      _viewIdentity=_viewAuthorized?identity:null;
      if(!_viewAuthorized){
        _grant=null;_loadGeneration++;_hasLocalData=false;_reportsLoaded=false;
        _employees=[];_work=[];_taskSources=[];_history=[];_verifiedWeeks=null;_overviewPayments=[];
        _pendingPayments=[];_historyUnlocked.value=false;
        _error='Sign in to the saved Owner account to view payroll.';
      }else{_error=null;_historyUnlocked.value=true;}
    });
    if (_canView) {
      // Acquire session authority once for Owner-only financial operations.
      // No device prompt; do not block the normal view if local role checks
      // cannot issue the grant.
      try {
        final grant = await _signedInOwnerGrant();
        if (mounted && _canView) setState(() => _grant = grant);
      } catch (_) { /* Saved Owner view remains available. */ }
      if (_canView) await _load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _loadGeneration++;
    _lockCheck?.cancel();
    _historyUnlocked.dispose();
    _opening.dispose();
    _balanceReason.dispose();
    _weeklyBasePreview.dispose();
    _hourlySupplementPreview.dispose();
    _approvedSupplementHours.dispose();
    _weeklyAdjustmentPreview.dispose();
    _repayment.dispose();
    _repaymentNote.dispose();
    super.dispose();
  }

  bool get _jobMode => widget.jobId != null;
  void _assertOwner() {
    final grant = _grant;
    if (grant == null) throw StateError('Unlock Owner payroll first.');
    grant.assertValid(widget.businessId, grant.actorId);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Backgrounding Briskers is not signing out of the Owner account.
    if(state==AppLifecycleState.resumed)unawaited(_openSavedOwnerView());
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool verifyPayment = false,
    bool rethrowError = false,
    ValueChanged<Object>? onError,
  }) async {
    if (_busy) {
      if (rethrowError) throw StateError('Payroll is busy. Try again.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    var actionCompleted = false;
    try {
      if (!_canView) throw StateError('Sign in to Briskers as Owner.');
      var needsSessionGrant = _grant == null;
      if (!needsSessionGrant) {
        try { _assertOwner(); } on StateError { needsSessionGrant = true; }
      }
      if (needsSessionGrant) {
        // Actual payments still use the signed ledger lease and idempotency
        // checks, but never demand another biometric/PIN authentication.
        final grant = await _signedInOwnerGrant();
        if (!mounted || !_canView) return;
        grant.assertValid(widget.businessId, grant.actorId);
        setState(() { _grant = grant; });
      }
      _assertOwner();
      if (!mounted) return;
      await action();
      actionCompleted = true;
      if (mounted) {
        unawaited(_load());
        unawaited(_refreshLan());
      }
    } catch (error) {
      if (mounted) {
        if (onError == null) {
          setState(() => _error = error.toString());
        } else {
          onError(error);
        }
      }
      if (rethrowError && !actionCompleted) rethrow;
    } finally {
      if (mounted) { setState(() { _busy = false; _authorizing = false; });
      }
    }
  }

  Future<void> _runOwnerTaskEdit(Future<void> Function() action) async {
    if (_busy || !_canView) return;
    setState(() { _busy = true; _error = null; });
    try {
      await action();
      if (mounted && _canView) unawaited(_load());
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // The task save is authoritative. A device notification error must never
  // suppress the reload of a successfully saved completion or invite a retry.
  Future<void> _syncSavedGeneralReminders() async {
    try {
      await LocalTaskReminders().sync(widget.businessId,await _viewRepository.shopTasks());
    } catch (_) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Task saved locally. This device could not update reminders; check notification settings.')));
      }
    }
  }

  Future<void> _changeGeneralTaskStatus(String employee, int id, String status,) =>
      _runOwnerTaskEdit(() async {
      await _taskEditRepository.setShopTaskStatus(employee, id, status);
      await _syncSavedGeneralReminders();
    },);

  Future<void> _refreshLan() async {
    if (_refreshingOwnerState || _grant == null) return;
    _refreshingOwnerState = true;
    final grant = _grant!;
    try {
      final connection = widget.ownerConnection ?? PayrollUiScope.of(context)?.connection ??
          await OwnerPayrollConnections.open(context, widget.businessId, grant,)
              .timeout(const Duration(seconds: 8));
      await connection.refresh(grant).timeout(const Duration(seconds: 8));
      if (mounted && identical(grant, _grant) && !_loadingLocal) await _load();
    } catch (_) {
      // Optional LAN refresh never blocks reading the saved local ledger.
    } finally { _refreshingOwnerState = false; }
  }

  Future<void> _load() async {
    if(!_canView)return;
    if (_localRead != null) {
      if(mounted && !_loadingLocal) {setState(()=>_error='Saved payroll database is still busy. Navigation remains available; retry shortly.',);
      }
      return;
    }
    final generation = ++_loadGeneration;
    setState(() { _loadingLocal = true; _loadStage = 'saved payroll'; });
    final timer = Stopwatch()..start();
    final read = _readLocal(generation);
    _localRead = read;
    // Keep a stalled read single-flight even after the UI timeout.
    unawaited(read.then<void>((_) {}, onError: (Object _, StackTrace _) {})
      .whenComplete(() { if (identical(_localRead, read)) _localRead = null; }),);
    try {
      await read.timeout(const Duration(seconds: 8));
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        _loadGeneration++;
        setState(() => _error = error is TimeoutException
          ? 'Saved payroll is taking longer to load ($_loadStage). Navigation is available. Retry when the local database is ready.'
          : 'Could not load $_loadStage: $error',);
      }
    } finally {
      debugPrint('PAYROLL_LOCAL stage=$_loadStage elapsed_ms=${timer.elapsedMilliseconds}',);
      if (mounted) {
        setState(() => _loadingLocal = false);
        // Do not launch 1,179-invoice recovery every time Payroll opens.
      }
    }
  }

  Future<void> _backfillTasks() async {
    if(_backfillActive || !mounted || !_canView)return;
    setState(()=>_backfillActive=true);
    try{
      final more=await _viewRepository.backfillInvoiceTasks(job:widget.jobId,
        maxInvoices:25,resume:true,onProgress:(checked,recovered,unavailable){
          if(mounted && _canView){
            setState((){
              _checkedInvoices=checked;_recoveredTasks=recovered;
              _unavailableInvoices=unavailable;
            });
          }
        },);
      if(mounted && _canView){
        _backfillDone=!more;
        if(_localRead==null)await _load();
      }
    }catch(error){
      if(mounted && _canView) {setState(()=>_error='Recovery paused: $error');
      }
    }finally{if(mounted)setState(()=>_backfillActive=false);}
  }

  Future<void> _readLocal(int generation) async {

    if(!_canView)return;
    final repository = _viewRepository;
    final cachedRoster=await OfflineJobAdminService(database:_db,).cachedEmployees(widget.businessId);
    if (!mounted || generation != _loadGeneration) return;
    _loadStage = 'pending requests';
    final pendingPayments = await PayrollOwnerLedger(_db, widget.businessId,
      repository: repository,).pending();
    _loadStage = 'tasks'; // Invoice saves maintain task identities incrementally.
    final job = widget.jobId;
    if (job != null) {await repository.recoverJobAssignments(job);_workspaceJob=(await _db.customSelect('SELECT * FROM local_jobs WHERE business_id=? AND id=?',variables:[Variable(widget.businessId),Variable(job)]).get()).firstOrNull?.data;}
    final profileEmployee=widget.employeeId!=null && !widget.reportsOnly &&
        !widget.globalTasks && !_jobMode ? widget.employeeId : null;
    final hydrated=await _taskEditRepository.localCompensation(cachedRoster,
      grant:_grant,employee:profileEmployee,);
    _carryReview=await _taskEditRepository.applyNov12OilSeparatorCarry();
    await _taskEditRepository.applyOwnerNov13WorkDates();
    final persistedEmployees = job == null
        ? await repository.employees()
        : await repository.assignedEmployees(job);
    final roster = hydrated;
    final combined = {
      for (final row in roster) row['id']: row,
      for (final row in persistedEmployees)
        row['id'] ?? row['employee_id']: {...row, ...?roster.where((candidate) =>
          candidate['id'] == (row['id']??row['employee_id']),).firstOrNull,
          'id':row['id']??row['employee_id'],'rate':row['rate'],'base_enabled':row['base_enabled'],},
    }.values.toList();
    final employees=await EmployeeNicknameStore(database:_db,).decorate(widget.businessId,combined);
    final overview = !widget.globalTasks && !widget.reportsOnly &&
        widget.employeeId == null && !_jobMode;
    final employee = widget.globalTasks || overview ? null :
        widget.employeeId ?? _employee ?? (employees.firstOrNull?['id'] as String?);
    // Preserve historical allocations in read-only Tasks and Reports views.
    // Payroll payment eligibility is guarded separately in WeeklyLaborReview.
    final work = await repository.work(employee: _jobMode ? null : employee, job: job,);
    // Work needs only the selected employee's jobs, not the entire shop's
    // task catalog. Keep archived sources visible with the same protection.
    final sources = (await repository.tasks(jobs: profileEmployee==null?null:{
      for(final row in work) if(row['job_id'] is String) row['job_id'] as String,
    })).map((r) => <String,dynamic>{
      ...r,
      'archived_labor': r['source_kind']=='invoice' &&
          !LocalInvoiceTaskStore.currentPayrollDate(r['invoice_date']) ? 1 : 0,
    },).toList();
    if(!mounted||generation!=_loadGeneration)return;
    if(!_canView)return;
    setState((){_hasLocalData=true;_employees=employees;_employee=employee;_work=work;_taskSources=sources;});
    if (widget.employeeId != null && !widget.reportsOnly) {
      final weeks = await repository.verifiedPayrollWeeks(widget.employeeId!);
      if (!mounted || generation != _loadGeneration || !_canView) return;
      setState(() => _verifiedWeeks = weeks);
    }
    _loadStage = 'payment history';
    final history = employee == null || _jobMode
        ? <Map<String, dynamic>>[] : await repository.historyWithWork(employee);
    final allPayments = <Map<String, dynamic>>[];
    if (overview) {
      for (final row in employees) {
        final id = row['id'];
        if (id is String) { allPayments.addAll((await repository.historyWithWork(id)).where((row) => row['reversed_at'] == null));
        }
      }
    }
    final advanceWriteRevision = _advanceWriteRevision;
    final advance = employee == null || _jobMode ? null : await repository.advance(employee);
    final repayments = employee == null || widget.employeeId == null || widget.reportsOnly
        ? <Map<String, dynamic>>[] : await repository.repaymentHistory(employee);
    final adjustments = employee == null || _jobMode ? <Map<String, dynamic>>[] : await repository.advanceAdjustments(employee);
    final debtHistory = employee != null && !_jobMode && await repository.hasAdvanceHistory(employee);
    final opening = employee == null || widget.employeeId == null || widget.reportsOnly
        ? null : await repository.openingAdvance(employee);
    final weeklyDefaults = employee == null || widget.employeeId == null ||
        widget.reportsOnly || _weeklyDefaultsLoaded
        ? null : await repository.weeklyDefaults(employee);
    final generalTasks = (widget.globalTasks || _jobMode) ? await repository.shopTasks()
        : employee == null || widget.employeeId == null || widget.reportsOnly
            ? <Map<String, dynamic>>[] : await repository.shopTasks(employee);
    // Restores/cancels saved device reminders without requesting permission.
    try { await LocalTaskReminders().sync(widget.businessId,await repository.shopTasks()); } catch (_) { /* Task and payroll loading remain local and available. */ }
    if(!_canView)return;
    if (!mounted || generation != _loadGeneration) return;
    _historyUnlocked.value = true;
    setState(() {
      if(_error?.startsWith('Saved payroll is taking longer')==true || _error?.startsWith('Could not load ')==true) {_error=null;
      }
      _hasLocalData = true;
      _reportsLoaded = true;
      _employees = employees;
      _overviewPayments = allPayments;
      _pendingPayments = employee == null ? pendingPayments :
          pendingPayments.where((row) => row['employee_id'] == employee).toList();
      if (_employee != employee) _advanceExpanded = null;
      _employee = employee;
      _work = work;
      _taskSources = sources;
      _history = history;
      if (advanceWriteRevision == _advanceWriteRevision) {
        _advanceBalance = advance;
        _repayments = repayments;
        _openingAdvance = opening;
        _hasAdvanceHistory = debtHistory;
        _advanceAdjustments = adjustments;
      }
      _generalTasks = job == null ? generalTasks : generalTasks.where((row) => row['job_id'] == job).toList();
      if (!_weeklyDefaultsLoaded) {
        _weeklyDefaultsLoaded = true;
        String amount(String key) =>
            ((weeklyDefaults?[key] as int? ?? 0) / 100).toStringAsFixed(2);
        _weeklyBasePreview.text = amount('base_cents');
        _hourlySupplementPreview.text = amount('hourly_cents');
        _approvedSupplementHours.text = '0.00';
        _weeklyAdjustmentPreview.text = amount('adjustment_cents');
        _laborAdditionalToBase = weeklyDefaults?['add_labor'] == 1;
      }
    });
  }

  String _date(DateTime value) => value.toIso8601String().substring(0, 10);
  Future<PayrollLanWorkflow> _workflow(String employee, {PayrollOwnerProof? ownerProof,}) async {
    final identity = await PayrollLanIdentity.load();
    final enrollment = PayrollLanEnrollment(identity);
    final peer = await enrollment.ownerPeer(widget.businessId, employee);
    if (peer == null) throw StateError('Pair this employee device first.');
    _assertOwner();
    final workflow = PayrollLanWorkflow(
      database: _db, identity: identity, peer: peer,
      assertLink: _assertOwner, assertOwner: _assertOwner,
      assertWriter: () => enrollment.assertWriter(widget.businessId, _grant!),
      ownerProof: ownerProof,
    );
    await workflow.queueRecordedPayments();
    return workflow;
  }

  Future<void> _managePeer({required bool pair}) async {
    final employee = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(pair ? 'Pair employee device' : 'Sync with employee'),
        children: [
          for (final row in _employees)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, row[_jobMode ? 'employee_id' : 'id']),
              child: Text(_employeeLabel((row['id']??row['employee_id'])?.toString()),),
            ),
        ],
      ),
    );
    if (employee == null || !mounted) return;
    await _run(() async {
      if (!pair) {
        final workflow = await _workflow(employee);
        if (mounted) await showPayrollLanSync(context, workflow);
        return;
      }
      final device = await payrollLanInput(context, 'Pair employee device', 'Mechanic device ID',);
      if (device == null || !mounted) return;
      final enrollment = PayrollLanEnrollment(await PayrollLanIdentity.load());
      final code = await enrollment.invite(
        business: widget.businessId, employee: employee,
        mechanicDevice: device, grant: _grant!,
      );
      if (!mounted) return;
      await showPayrollLanCode(context, 'Private pairing code', code);
    }, verifyPayment: pair);
  }

  Future<void> _assign(String invoiceId, Map<String, dynamic> line, {String? jobId, bool enterHours = false}) async {
    final job = jobId ?? widget.jobId;
    if (job == null) return;
    var candidates = <Map<String, dynamic>>[];
    // Opening a picker is a read-only Owner action, not a payroll payment.
    // Keep the actual assignment transaction on its protected write path.
    if (!_canView) return;
    try {
      final roster=await OfflineJobAdminService(database:_db).cachedEmployees(widget.businessId);
      if (!mounted || !_canView) return;
      final known=await _viewRepository.employees();
      if (!mounted || !_canView) return;
      candidates={for(final r in roster) r['id']:{...r,'employee_id':r['id']},
        for(final r in known) r['id']:{...?roster.where((p)=>p['id']==r['id']).firstOrNull,...r,'employee_id':r['id']}}.values.toList();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return;
    }
    if (!mounted || !_canView) return;
    if (candidates.isEmpty) {
      setState(() => _error = 'Assign mechanics to this Job first.');
      return;
    }
    final employee = await showTaskSelection<Map<String, dynamic>>(
      context, title: 'Add mechanic to invoice labor', options: candidates,
      label: (employee) => _employeeLabel((employee['id'] ?? employee['employee_id'])?.toString()),
      description: (_) => '',
    );
    if (employee == null || !mounted) return;
    final employeeId = employee['employee_id'] as String;
    final name = (employee['name'] ?? employee['employee_name'] ?? employeeId).toString();
    // Allocating work is not setting wages. Zero is an unconfigured pay
    // basis, NOT an automatic rate; actual payment remains unavailable until
    // the Owner configures and reviews compensation in Employee Details.
    final rate = employee['rate'] as int? ?? 0;
    int? assignedMinutes;
    if (enterHours) {
      final value = await showTaskHours(context);
      final hours = double.tryParse(value ?? '');
      if (hours == null || !hours.isFinite || hours < 0 || hours > 10000 || !mounted) {
        return;
      }
      assignedMinutes = (hours * 60).round();
    }

    if (!_canView) return;
    // Detect the saved shop link before editing. A failed peer read must
    // never be silently interpreted as an unpaired, local-only device.
    bool paired;
    try {
      final identity = await PayrollLanIdentity.load();
      paired = await PayrollLanEnrollment(identity)
          .ownerPeer(widget.businessId, employeeId) != null;
      final document = await _db.customSelect(
        'SELECT document_date FROM local_documents WHERE business_id=? AND id=?',
        variables:[Variable(widget.businessId),Variable(invoiceId)],
      ).getSingleOrNull();
      // Historical recordkeeping must not enqueue a fresh work assignment.
      if (!LocalInvoiceTaskStore.currentPayrollDate(document?.data['document_date'])) {
        paired=false;
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return;
    }
    if (!mounted || !_canView) return;

    Future<void> assign({required bool pairedDevice}) async {
      final assignments = LocalTaskAssignmentStore(_db);
      Future<void> apply() async {
        if (!_canView) {
          throw StateError('Owner account changed during assignment.');
        }
        await assignments.linkEmployee(widget.businessId, job, employeeId, name);
        // Add/split MUST be additive, including when the first mechanic
        // inherited the assignment from Main Mechanic. Retiring inherited
        // allocations here silently replaced the original mechanic.
        // Explicit reassignment is a distinct Owner operation, never an
        // accidental consequence of adding a second person.
        if (!pairedDevice) {
          await _taskEditRepository.assignExistingService(
            job: job, invoice: invoiceId, line: line['id'] as String,
            employee: employeeId, name: name, rate: rate, minutes: assignedMinutes,
          );
        } else {
          await _taskEditRepository.assignExistingService(
            job: job, invoice: invoiceId, line: line['id'] as String,
            employee: employeeId, name: name, rate: rate, minutes: assignedMinutes,
          );
          final workflow = await _workflow(employeeId);
          await workflow.assign(
            job: job, invoice: invoiceId, line: line['id'] as String,
            description: (line['description'] ?? line['name'] ?? 'Invoice labor')
                .toString(),
            employeeName: name, rate: rate,
          );
        }
        final task = (await _taskEditRepository.tasks())
            .where((r) => r['invoice_id'] == invoiceId &&
                r['source_line_id'] == line['id']).single;
        await assignments.allocate(widget.businessId, task['id'] as String,
            employeeId, inherited: false);
        if (!_canView) {
          throw StateError('Owner account changed during assignment.');
        }
      }
      // Keep a local assignment atomic. The paired LAN workflow has its own
      // durable writer protocol and must not run inside a SQLite transaction.
      if (pairedDevice) {
        await apply();
      } else {
        await _db.transaction(apply);
      }
    }

    if (paired) {
      // A paired mechanic's LAN workflow retains the payment-grant protocol.
      await _run(() => assign(pairedDevice: true));
    } else {
      // Normal local invoice labor assignment is not a payroll payment.
      await _runOwnerTaskEdit(() => assign(pairedDevice: false));
    }
    if(mounted && _error==null && rate==0){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:Text('Labor assigned. Set the employee pay rate in Details before paying.'),
      ));
    }
  }

  Future<void> _markAllJobTasksDone() async {
    if(_busy || !_canView || widget.jobId==null) return;
    try {
      final service=JobTaskBulkCompletion(_taskEditRepository);
      final plan=await service.plan(widget.jobId!,DateTime.now());
      if(!mounted || !_canView) return;
      if(plan.count==0) { await _load(); return; }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => OwnerConfirmationDialog(
          title: 'Mark All Done?',
          confirm: 'Mark All Done',
          sections: [
            Text('Complete ${plan.count} ${plan.count == 1 ? 'task' : 'tasks'} for this job?'),
            const SizedBox(height: 8),
            const Text('Assignments and hours stay saved. Future reminders stay scheduled. '
                'Wages are paid separately in Payroll.'),
          ],
        ),
      );
      if(confirmed!=true || !mounted || !_canView) return;
      await _runOwnerTaskEdit(() async {
        final completed=await service.complete(plan,DateTime.now());
        if(mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:
          Text(completed==0?'These tasks are already Done.':'$completed ${completed==1?'task marked':'tasks marked'} Done.'))); }
      });
    } catch(error) { if(mounted) setState(()=>_error=error.toString()); }
  }

  Future<void> _recordTaskProgress(Map<String, dynamic> row,
      {bool markDone = false}) async {
    final next = markDone ? 'Done' :
        row['state'] == 'Open' ? 'In Progress' : 'Done';
    // Paid work is immutable. Start never turns assigned time into payable
    // time. Mark Done credits exactly the hours already assigned by the Owner.
    if (row['state'] == 'Done') return;
    if ((row['paid_minutes'] as int? ?? 0) > 0) {
      if (next == 'Done' && row['state'] == 'In Progress') {
        await _runOwnerTaskEdit(
          () => _taskEditRepository.finishPaidProgress(
            row['id'] as String,
            _date(DateTime.now()),
          ),
        );
      }
      return;
    }
    final assignedMinutes = row['estimated_minutes'] as int? ?? 0;
    if (next == 'Done' && assignedMinutes <= 0) {
      setState(() => _error =
        'Assign mechanic hours with the pencil before marking Done.');
      return;
    }
    final previousMinutes = row['recorded_actual_minutes'] as int? ??
        row['actual_minutes'] as int? ?? 0;
    final completedMinutes = next == 'Done' ? assignedMinutes : previousMinutes;
    // No redundant dialogs: the assigned estimate is the Owner-approved
    // time credit on completion. Recording payroll payment remains separate.
    await _runOwnerTaskEdit(() => _taskEditRepository.recordAllocatedTime(
      row['id'] as String, next, completedMinutes, completedMinutes,
      _date(DateTime.now()),
    ));
  }

  Widget _quickLaborActions(Map<String, dynamic> row, {bool markDone = true}) {
    final settled = row['owner_prior_paid'] == 1 || row['paid'] == 1 ||
        (row['paid_minutes'] as int? ?? 0) > 0;
    final editable = !settled && row['assignment_conflict'] != 1 &&
        row['source_active'] != 0;
    return Wrap(spacing: 8, runSpacing: 4, children: [
        TextButton.icon(
          onPressed: _busy ? null : () => _serviceEditor(row),
          icon: const Icon(Icons.edit_calendar_outlined),
          label: const Text('Edit Task'),
        ),
      if (markDone && editable && row['archived_labor'] != 1 && row['state'] != 'Done')
        FilledButton.icon(
          onPressed: _busy ? null : () => _recordTaskProgress(row, markDone: true),
          icon: const Icon(Icons.done, size: 18),
          style: FilledButton.styleFrom(backgroundColor: WorkStatusColors.done,),
          label: const Text('Mark Done'),
        ),
      if(editable && row['source_kind']!='invoice')
        TextButton.icon(onPressed:_busy?null:()=>_editEstimated(row),icon:const Icon(Icons.edit_outlined),label:const Text('Edit Assignment'),),
      if (editable)
        TextButton.icon(
          onPressed: _busy ? null : () => _confirmHistoricalPaid(row),
          icon: const Icon(Icons.verified_outlined, size: 18),
          label: const Text('Reconcile historical wages'),
        ),
      if (markDone && editable && row['archived_labor'] == 1)
        TextButton.icon(
          onPressed: _busy ? null : () => _reviewCarry(row),
          icon: const Icon(Icons.manage_search, size: 18),
          label: const Text('Review unpaid work'),
        ),
    ],);
  }

  Future<void> _editEstimated(Map<String,dynamic> row) => _serviceEditor(row);

  /// Owner-only historical settlement: a confirmation, never a new payment.
  Future<void> _confirmHistoricalPaid(Map<String,dynamic> row) async {
    if (!_canView || _busy) return;
    final mechanic=_employeeLabel(row['employee_id']?.toString());
    final ok=await showDialog<bool>(context:context,builder:(dialog)=> OwnerConfirmationDialog(
      title: 'Mark as Already Paid',
        confirm: 'Confirm historical payment',
        sections: [
          Text(
            '${row['job_number'] ?? 'Job'} · ${row['customer_name'] ?? ''}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text('${row['description'] ?? 'Labor'}'),
          Text(
            '$mechanic · ${((row['estimated_minutes'] as int? ?? row['actual_minutes'] as int? ?? 0) / 60).toStringAsFixed(2)} hours',
          ),
          const Divider(height: 24),const Text(
            'Confirm wages already paid before this labor entered the new payroll workflow.',
            style: TextStyle(fontWeight: FontWeight.w700),),
          const SizedBox(height: 12),const Text(
            '• Marks only this mechanic’s task portion Done and already paid.\n• Removes these hours from unpaid payroll.\n• Keeps the task, hours and historical payment records.\n• Does not create a payment or expense.\n• Does not change customer charges or close the job.',),
          const SizedBox(height: 16),
      ],
    ),);
    if (ok != true || !mounted || !_canView) return;
    await _runOwnerTaskEdit(()=>
      _taskEditRepository.confirmHistoricalAlreadyPaid(row['id'] as String),);
  }

  // Match the saved mechanic progress state in both TEST-style indicators.
  // This is presentational only: Starting does not credit payroll hours.
  static IconData _workStatusIcon(String state, {bool inner = false}) {
    switch (state) {
      case 'Done':
        return inner ? Icons.check_circle_outline : Icons.check_circle;
      case 'In Progress':
        return Icons.timelapse;
      default:
        return Icons.radio_button_unchecked;
    }
  }

  static Color _workStatusColor(String state) => switch(state) {
    'Done'=>WorkStatusColors.done,'In Progress'=>WorkStatusColors.progress,_=>WorkStatusColors.open,
  };

  // The approved Tasks TEST separates the job/task header from the mechanic's
  // progress controls. This is a view over the real immutable payroll credits.
  // Approved compact TEST-style hours: readable without dominating the card.
  Widget _compactPlannedHours(double hours) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFE1F6E9),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text('${hours.toStringAsFixed(2)} hrs',
      style: const TextStyle(
        color: Color(0xFF126A46),
        fontSize: 13.5,
        fontWeight: FontWeight.w800,
      ),),
  );

  Widget _taskCard(Map<String, dynamic> row, {bool manage = true}) {
    final paid = (row['paid_minutes'] as int? ?? 0) > 0 ||
        row['paid'] == 1;
    final conflict = row['assignment_conflict'] == 1;
    final removed = row['source_active'] == 0;
    final state = row['state']?.toString() ?? 'Open';
    final archived = row['archived_labor']==1;
    final canProgress = !archived && !paid && !conflict && !removed && !_busy;
    final planned = (row['estimated_minutes'] as int? ?? 0) / 60;
    final actual = row['recorded_actual_minutes'] as int? ??
        row['actual_minutes'] as int? ?? 0;
    final credited = row['actual_minutes'] as int? ?? 0;
    return KeyedSubtree(
      key: ValueKey('mechanic-work-${row['id']}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if(archived) ListTile(title:const Text('Historical labor · excluded from payroll'),
              trailing: paid ? null : TextButton(onPressed:()=>_reviewCarry(row),child:const Text('Review unpaid work'),),),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(_workStatusIcon(state),
                color: _workStatusColor(state),size:22,),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(row['description']?.toString() ?? 'Task',
                    style: const TextStyle(fontSize: 15.5,
                      fontWeight: FontWeight.w800,),),
                  const SizedBox(height: 3),
                  Text(_employeeLabel(row['employee_id']?.toString()),
                    style: const TextStyle(fontWeight: FontWeight.w700),),
                ],
              ),),
              const SizedBox(width: 5),
                TaskScheduleIndicator(row),
              _compactPlannedHours(planned),
              if (paid) const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.lock_outline,size:20,
                  color: Color(0xFF64748B),),),
              if (manage && (!paid || archived)) IconButton(
                tooltip: 'Edit Assignment',
                icon: const Icon(Icons.edit_outlined,size:19,
                  color: Color(0xFF00897E),),
                onPressed: _busy || conflict || removed
                  ? null : () => _editEstimated(row),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth:34,minHeight:34,),
              ),
            ],),
            const SizedBox(height: 9),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10,vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F5F8),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: const Color(0xFFDCE6EB)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(_workStatusIcon(state, inner: true),size:19,
                      color: _workStatusColor(state),),
                    const SizedBox(width: 7),
                    Expanded(child: Text(
                      _employeeLabel(row['employee_id']?.toString()),
                      style:const TextStyle(fontWeight:FontWeight.w700),),
                      ),
                      TaskScheduleIndicator(row),
                    _compactPlannedHours(planned),
                  ],),
                  const SizedBox(height: 5),
                  // Keep the completion control beside In Progress.
                  // The previous Wrap placed Mark Done on its own bottom
                  // line where the Android navigation area obscured it.
                  if (state == 'In Progress')
                    Row(children: [
                      const Expanded(child: Text('In Progress',
                        style:TextStyle(color:Color(0xFF64748B),
                          fontWeight:FontWeight.w600,),),),
                      if (canProgress)
                        OutlinedButton.icon(
                          onPressed:()=>_recordTaskProgress(row,markDone:true),
                          style:OutlinedButton.styleFrom(
                            foregroundColor:WorkStatusColors.done,
                            side:const BorderSide(color:WorkStatusColors.done,),
                            visualDensity:VisualDensity.compact,
                            padding:const EdgeInsets.symmetric(
                              horizontal:12,vertical:6,),),
                          icon:const Icon(Icons.done,size:17),
                          label:const Text('Mark Done'),),
                    ],)
                  else
                    Wrap(alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,runSpacing: 2,children: [
                        Text(state == 'Open' ? 'Not Started' : state,
                          style:const TextStyle(color:Color(0xFF64748B),
                            fontWeight:FontWeight.w600,),),
                        if (canProgress && state == 'Open')
                          TextButton.icon(
                            onPressed:()=>_recordTaskProgress(row),
                            icon:const Icon(Icons.play_arrow,size:18),
                            label:const Text('Start'),),
                        if (canProgress && state == 'Open')
                          OutlinedButton.icon(
                            onPressed:()=>_recordTaskProgress(row,markDone:true),
                            style:OutlinedButton.styleFrom(foregroundColor:WorkStatusColors.done,side:const BorderSide(color:WorkStatusColors.done,),),
                            icon:const Icon(Icons.done,size:17),
                            label:const Text('Mark Done'),),
                        if (conflict)
                          TextButton(onPressed:_busy?null:()=>_runOwnerTaskEdit(
                            ()=>_taskEditRepository.acceptChangedAssignment(
                              row['id'] as String,),),
                            child:const Text('Accept work'),),
                        if (paid) const Text('Paid · Locked',
                          style:TextStyle(fontWeight:FontWeight.w700,
                            color:Color(0xFF64748B),),),
                      ],),
                  if (widget.focusLineId == null) _quickLaborActions(row, markDone: false),
                  if (actual > 0 || credited > 0)
                    Text('Actual: ${(actual/60).toStringAsFixed(2)}h · '
                      'Credited: ${(credited/60).toStringAsFixed(2)}h',
                      style:const TextStyle(fontSize:11,
                        color:Color(0xFF64748B),),),
                  if (removed) const Text('Removed from invoice',
                    style:TextStyle(fontSize:11),),
                  if (conflict) const Text(
                    'Assignment changed; Owner review required',
                    style:TextStyle(fontSize:11),),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addRecheck({String? jobId}) async {
    final job = jobId ?? widget.jobId;
    if (job == null) return;
    final employee = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Assign recheck'),
        children: [
          for (final employee in _employees)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, employee),
              child: Text(_employeeLabel((employee['id']??employee['employee_id'])?.toString())),
            ),
        ],
      ),
    );
    if (!mounted || employee == null) return;
    final description = await payrollLanInput(context, 'Additional job work / Recheck', 'Task description');
    if (!mounted || description == null || description.isEmpty) return;
    final estimated = await payrollLanInput(context, 'Mechanic estimated hours', 'Estimated hours');
    if (!mounted || estimated == null) return;
    final hours = double.tryParse(estimated);
    if (hours == null || !hours.isFinite || hours < 0 || hours > 10000) return;
    final rate = employee['rate'] as int?;
    if (rate == null || rate <= 0) {
      setState(() => _error = 'Save this employee’s hourly compensation first.');
      return;
    }
    // This is a task creation, not a payroll payment. The local Owner
    // repository checks session identity before and after the transaction.
    // Paired-device writes retain their existing LAN Owner-grant protection.
    if (!_canView) return;
    final operation = _operationId();
    final id = (employee['employee_id'] ?? employee['id']) as String;
    final name = (employee['name'] ?? employee['employee_name'] ?? _employeeLabel(id)).toString();
    // Do not turn a missing or unreadable pairing record into a silent
    // unpaired write; show an error and preserve the saved task.
    var paired = false;
    try {
      final identity = await PayrollLanIdentity.load();
      paired = await PayrollLanEnrollment(identity)
          .ownerPeer(widget.businessId, id) != null;
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return;
    }
    if (!mounted || !_canView) return;
    if (!paired) {
      await _runOwnerTaskEdit(() => _taskEditRepository.createRecheck(
        operation: operation, job: job, description: description,
        employee: id, name: name, rate: rate,
        estimatedMinutes: (hours * 60).round(),
      ));
    } else {
      await _run(() async {
        final workflow = await _workflow(id);
        await workflow.assignRecheck(
          operation: operation, job: job, description: description,
          employeeName: name, rate: rate,
          estimatedMinutes: (hours * 60).round(),
        );
      });
    }
  }

  Future<void> _recordWeekly(
    DateTime week, DateTime date, String method,
    List<Map<String, dynamic>> selected, int adjustment, int repayment,
    int net, String reason, int base,
  ) async {
    final employee = _employee;
    if (employee == null || (selected.isEmpty && base <= 0)) {
      throw StateError('Select payable work for this employee.');
    }
    final pending = PayrollOwnerLedger(_db, widget.businessId);
    final request = {'employee': employee, 'week': _date(week), 'date': _date(date),
      'method': method, 'selected': selected, 'adjustment': adjustment,
      'repayment': repayment, 'net': net, 'reason': reason, 'base': base,};
    // Stable intent identity survives a lost UI/transport response and restart.
    final operation = await PayrollOwnerLedger.operationFor(request);
    var recordedNew = false;
    await _run(() async {
      await pending.intent(request);
      final ledger = await _localPaymentLedger(operation: operation);
      if (base > 0) {
        await ledger.enableWeeklyBase(employee, _employeeLabel(employee));
      }
      final identity = await PayrollLanIdentity.load();
      final peer = await PayrollLanEnrollment(identity,).ownerPeer(widget.businessId, employee);
      if (peer == null) {
        recordedNew = await ledger.verify(
          operation: operation, employee: employee, week: _date(week), date: _date(date),
          method: method, selected: selected, base: base, hourlyAdjustment: adjustment,
          adjustmentReason: reason, repayment: repayment, confirmedNet: net,
          beforeCommit: () => pending.resolve(operation),
        );
      } else {
        final workflow = await _workflow(employee, ownerProof: ledger.ownerProof,);
        recordedNew = await workflow.pay(operation: operation, week: _date(week), date: _date(date), method: method,
          selected: selected, reason: reason, net: net, base: base,
          adjustment: adjustment, repayment: repayment, onRecorded: () => pending.resolve(operation),);
      }
    }, verifyPayment: true, rethrowError: true,);
    if (!recordedNew) throw const PayrollAlreadyRecorded();
  }

  String _operationId() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(256)
        .toRadixString(16).padLeft(2, '0'),).join();
  }

  Future<LocalPayrollRepository> _localPaymentLedger({String? operation,}) async {
    _assertOwner();
    final connection = widget.ownerConnection ?? PayrollUiScope.of(context)?.connection ?? await OwnerPayrollConnections.open(context, widget.businessId, _grant!);
    final proof = await connection.acquire(_grant!, operation ?? _operationId(),);
    return LocalPayrollRepository(
      _db, business: widget.businessId, owner: true,
      deviceId: connection.lease.identity.deviceId, assertOwnerGrant: _assertOwner,
      ownerProof: proof,
    );
  }

  bool get _canSaveAdvance =>
      !_busy && !_loadingLocal && !_confirmingBalance && _advanceBalance != null;

  bool get _isOpeningBalance => !_hasAdvanceHistory && _advanceBalance == 0;

  int? get _proposedBalance {
    if (_opening.text.trim().isEmpty || _advanceBalance == null) return null;
    try {
      return AmountCalculator.cents(_opening.text, balanceCents: _advanceBalance);
    } on FormatException {
      return null;
    }
  }

  void _advanceSaveFailed(String action, Object error) {
    final detail = switch (error) {
      PayrollPending() => 'Use the Owner device with the current payroll ledger '
          'or connect both Owner devices on shop Wi-Fi and try again.',
      StateError(:final message) => message,
      ArgumentError(:final message) => message,
      _ => error.toString(),
    };
    setState(() => _advanceError = 'Could not save $action. $detail');
    unawaited(_load());
  }

  Future<void> _saveOpening() async {
    final employee = _employee;
    final before = _advanceBalance;
    final proposed = _proposedBalance;
    if (!_canSaveAdvance || employee == null || before == null ||
        proposed == null || proposed == before) {
      return;
    }
    final opening = _isOpeningBalance;
    final reason = _balanceReason.text.trim();
    if (!opening && reason.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _confirmingBalance = true;
      _advanceError = null;
    });
    bool? confirmed;
    try {
      confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => OwnerConfirmationDialog(
          title: opening ? 'Record opening amount owed?' : 'Adjust amount owed?',
          sections: [
            Text('Current balance: ${_money(before)}'),
            Text('Proposed balance: ${_money(proposed)}'),
            if (reason.isNotEmpty) Text('Reason: $reason'),
            const SizedBox(height: 10),
            const Text('This changes the amount owed only.'),
          ],
          confirm: 'Confirm Balance',
        ),
      );
    } finally {
      if (mounted) setState(() => _confirmingBalance = false);
    }
    if (confirmed != true || !mounted || employee != _employee) return;

    final operation = _balanceOperation ??= _operationId();
    await _run(() async {
      final ledger = await _localPaymentLedger(operation: operation);
      if (opening) {
        await ledger.recordOpeningAdvance(employee, proposed);
      } else {
        await ledger.adjustAdvance(
          employee: employee,
          operation: operation,
          expectedCents: before,
          proposedCents: proposed,
          reason: reason,
        );
      }
      if (mounted) {
        setState(() {
          _advanceWriteRevision++;
          _advanceBalance = proposed;
          _hasAdvanceHistory = true;
          if (opening) _openingAdvance = proposed;
          _advanceSection = null;
          _balanceOperation = null;
          _balanceReason.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Balance saved: ${_money(proposed)}')),
        );
        // A refresh started during confirmation may hold the old balance.
        // Let it finish before fetching updated balance history.
        final pendingRead = _localRead;
        if (pendingRead != null) {
          unawaited(pendingRead.then<void>(
            (_) {},
            onError: (Object _, StackTrace _) {},
          ).whenComplete(() {
            if (mounted) return _load();
          }));
        }
      }
    }, onError: (error) => _advanceSaveFailed('the balance', error));
  }

  int? get _repaymentCents {
    final value = _repayment.text.trim();
    if (!RegExp(r'^(?:\d+(?:\.\d{0,2})?|\.\d{1,2})$').hasMatch(value)) {
      return null;
    }
    final dollars = double.tryParse(value);
    if (dollars == null || dollars > 1000000) return null;
    final cents = AmountCalculator.cents(value);
    return cents > 0 && cents <= (_advanceBalance ?? 0) ? cents : null;
  }

  Future<void> _saveRepayment() async {
    final amount = _repaymentCents;
    final employee = _employee;
    if (!_canSaveAdvance || amount == null || employee == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _advanceError = null);
    final operation = _repaymentOperation ??= _operationId();
    final date = _date(_repaymentDate);
    final method = _repaymentMethod;
    final note = _repaymentNote.text.trim();
    await _run(() async {
      final ledger = await _localPaymentLedger(operation: operation);
      await ledger.recordRepayment(
        employee: employee,
        operation: operation,
        amount: amount,
        date: date,
        method: method,
        note: note,
      );
      if (mounted) {
        setState(() {
          _advanceSection = null;
          _repaymentOperation = null;
          _repayment.clear();
          _repaymentNote.clear();
        });
      }
    }, onError: (error) => _advanceSaveFailed('the repayment', error));
  }

  void _openRecordedWork(String id, {required bool invoice}) {
    if(!_canView)return;
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => invoice
          ? JobDocumentScreen(
              businessId: widget.businessId, documentId: id, isOwner: true,
              roleCode: 'owner',
              sharedBottomNavigationBar: widget.sharedBottomNavigationBar,
            )
          : JobDetailScreen(
              businessId: widget.businessId, jobId: id, roleCode: 'owner',
              bottomNavigationBar: widget.sharedBottomNavigationBar,
            ),
    ),);
  }

  Widget _reports() => Scaffold(
    bottomNavigationBar: widget.sharedBottomNavigationBar,
    appBar: AppBar(title: Text(widget.employeeName ?? 'Payroll reports')),
    body: Column(children: [
      if(!_canView)const Text('Sign in as Owner to view payroll.'),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null) Text(_error!),
      if (_canView && widget.employeeId == null && _employees.isNotEmpty)
        DropdownButton<String>(
          value: _employee,
          items: [
            for (final row in _employees)
              DropdownMenuItem(value: row['id'] as String, child: Text(_employeeLabel(row['id'] as String)),),
          ],
          onChanged: _busy ? null : (value) {
            setState(() {
              _employee = value;
              _history = [];
              _verifiedWeeks = null;
            });
            unawaited(_load());
          },
        ),
      if (_canView)
        Expanded(child: _reportsPanel()),
    ],),
  );

  Widget _panel(Widget child) => Card(
    margin: const EdgeInsets.symmetric(vertical: 6),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: child
    ),
  );

  Widget _header() => ApprovedEmployeeIdentity(name:_employeeLabel(widget.employeeId),role:widget.employeeRole??'Employee',active:widget.employeeActive,onDetails:widget.openEmployeeDetails);

  void _selectAmount(TextEditingController controller) {
    controller.selection = TextSelection(baseOffset: 0, extentOffset: controller.text.length,);
  }

  Future<void> _saveFlexiblePaySettings() async {
    final employee = _employee;
    final base = double.tryParse(_weeklyBasePreview.text.trim());
    final hourly = double.tryParse(_hourlySupplementPreview.text.trim());
    final adjustment = double.tryParse(_weeklyAdjustmentPreview.text.trim());
    if (employee == null || base == null || hourly == null || adjustment == null ||
        !base.isFinite || !hourly.isFinite || !adjustment.isFinite ||
        base < 0 || base > 1000000 || hourly < 0 || hourly > 100000 ||
        adjustment.abs() > 1000000) {
      setState(() => _error = 'Enter valid weekly amounts and rates.');
      return;
    }
    await _run(() async => (await _localPaymentLedger()).saveWeeklyDefaults(
      employee, (base * 100).round(), (hourly * 100).round(),
      (adjustment * 100).round(), _laborAdditionalToBase,
    ),);
  }

  Future<void> _finalizeFlexibleWeekly() async {
    final employee = _employee;
    if (_settlingWeekly || employee == null) return;
    setState(() => _settlingWeekly = true);
    try {
      await _confirmFlexibleWeekly(employee);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _settlingWeekly = false);
    }
  }

  Future<void> _confirmFlexibleWeekly(String employee) async {
    final base = double.tryParse(_weeklyBasePreview.text.trim());
    final rate = double.tryParse(_hourlySupplementPreview.text.trim());
    final adjustment = double.tryParse(_weeklyAdjustmentPreview.text.trim());
    final hours = double.tryParse(_approvedSupplementHours.text.trim());
    if (base == null || rate == null || adjustment == null || hours == null ||
        ![base, rate, adjustment, hours].every((value) => value.isFinite) ||
        base <= 0 || rate < 0 || hours < 0 || hours > 168 ||
        base > 1000000 || rate > 100000 || adjustment.abs() > 1000000) {
      throw ArgumentError('Enter valid weekly amounts and approved hours.');
    }
    final additional = _laborAdditionalToBase;
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => WeeklyLaborReview(
        sharedBottomNavigationBar: widget.sharedBottomNavigationBar,
        employeeId: employee, employeeName: _employeeLabel(employee),
        tasks: _work, week: _week,
        weeklyBaseCents: (base * 100).round(),
        weeklyAdjustmentCents: (adjustment * 100).round(),
        settlementRateCents: additional ? (rate * 100).round() : 0,
        requiredSupplementMinutes: additional ? (hours * 60).round() : null,
        settlementReason: additional
            ? 'Owner-approved weekly base and supplemental labor at ${_currency.format(rate)} per hour.'
            : 'Labor included in the weekly base. Selected credits receive coverage without an added hourly component.',
        advanceBalance: () => _viewRepository.advance(employee),
        recordPayment: _recordWeekly,
      ),
    ),);
    if (mounted && _canView) await _load();
  }

  Widget _flexibleWeeklyPreview(double trackedHours) {
    double value(TextEditingController input) =>
      double.tryParse(input.text.trim()) ?? 0;
    final base = value(_weeklyBasePreview);
    final rate = value(_hourlySupplementPreview);
    final adjustment = value(_weeklyAdjustmentPreview);
    final approvedHours = double.tryParse(
      _approvedSupplementHours.text.trim());
    // Never automatically add historical or previously paid hours.
    // A preview is invalid until the Owner enters safe supplemental hours.
    final validHours = approvedHours != null &&
      approvedHours.isFinite && approvedHours >= 0 &&
      approvedHours <= 168;
    final validMoney = [base, rate, adjustment].every((n) => n.isFinite) &&
      base >= 0 && rate >= 0 &&
      base <= 1000000 && rate <= 100000 &&
      adjustment.abs() <= 1000000;
    final supplement = _laborAdditionalToBase && validHours
      ? approvedHours * rate : 0.0;
    final total = base + supplement + adjustment;
    final validPreview = validHours && validMoney &&
      total.isFinite && total >= 0;
    Widget field(String label, TextEditingController controller) =>
      TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(
          signed: true, decimal: true,),
        selectAllOnFocus: true,
        onTapAlwaysCalled: true,
        onTap: () => _selectAmount(controller),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: label,
          prefixText: r'$ ', isDense: true,
          border: const OutlineInputBorder(),),
      );
    return _panel(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Flexible weekly pay',
          style: TextStyle(fontWeight: FontWeight.w800),),
        const SizedBox(height: 5),
        const Text('Owner-adjustable estimate only. No payment is created.',
          style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),),
        const SizedBox(height: 10),
        field('Weekly base', _weeklyBasePreview),
        const SizedBox(height: 8),
        field('Hourly supplement rate', _hourlySupplementPreview),
        const SizedBox(height: 8),
        TextField(
          controller: _approvedSupplementHours,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          selectAllOnFocus: true,
          onTapAlwaysCalled: true,
          onTap: () => _selectAmount(_approvedSupplementHours),
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Approved supplemental hours this week',
            isDense: true, border: OutlineInputBorder(),),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Add tracked labor to base'),
          subtitle: Text(_laborAdditionalToBase
            ? '${validHours ? approvedHours.toStringAsFixed(2) : 'Invalid'} approved hours × rate'
            : 'Labor included in base · no double counting',),
          value: _laborAdditionalToBase,
          onChanged: (v) => setState(() => _laborAdditionalToBase = v),
        ),
        Text('Tracked task allocations (all weeks): '
          '${trackedHours.toStringAsFixed(2)} hrs · Reference only. '
          'Previously paid hours must not be paid again.',
          style: const TextStyle(fontSize: 11,
            color: Color(0xFF64748B)),),
        const SizedBox(height: 8),
        field('Other weekly adjustment (+/-)', _weeklyAdjustmentPreview),
        const SizedBox(height: 10),
        Text(validPreview
            ? 'Preview gross: ${_currency.format(total)}'
            : 'Preview unavailable · check amounts and hours',
          style: const TextStyle(fontWeight: FontWeight.w800,
            fontSize: 16),),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: _busy || !validPreview ? null : _saveFlexiblePaySettings,
          child: const Text('Save weekly defaults'),),
        const Text('Approved hours are a temporary preview and are not '
          'saved as payable coverage. Review actual unpaid labor before '
          'verifying any payment.',
          style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy || _settlingWeekly || !validPreview || base <= 0 || total <= 0
            ? null : _finalizeFlexibleWeekly,
          icon: const Icon(Icons.verified_outlined),
          label: const Text('Verify Weekly Payment'),
        ),
      ],
    ),);
  }

  Widget _payrollTab() {
    final person=_employees.where((r)=>r['id']==_employee).firstOrNull;
    final base=person?['base_enabled']==1;
    if(base) { return ListView(padding:const EdgeInsets.all(12),children:[
      Row(children:[IconButton(tooltip:'Previous payroll week',onPressed:()=>setState(()=>_week=_week.subtract(const Duration(days:7)),),icon:const Icon(Icons.chevron_left),),Expanded(child:Text('Week of ${DateFormat.yMMMd().format(EmployeeWorkReview.monday(_week))}',textAlign:TextAlign.center,),),IconButton(tooltip:'Next payroll week',onPressed:()=>setState(()=>_week=_week.add(const Duration(days:7))),icon:const Icon(Icons.chevron_right),),],),
      _flexibleWeeklyPreview(_currentPayrollWork.fold<double>(0,(n,r)=>n+(r['actual_minutes'] as int)/60,),),
      _advancePanel(),
    ],); }
    return WeeklyLaborReview(
      key:ValueKey('employee-payroll-${widget.employeeId}'),
      employeeId:widget.employeeId!,employeeName:_employeeLabel(widget.employeeId),
      tasks:_work,week:_week,embedded:true,profileLayout:true,
      onOpenJob: (id) => _openRecordedWork(id, invoice: false),
      onOpenTask: (task) => _openTaskDetails({...task,'line_id':task['task_id']},false),
      paymentHistory: _history.where((row) => row['reversed_at'] == null).toList(),
      savedRateCents:person?['rate'] as int?,reviewMessage:_work.any((r)=>r['job_number']=='J-40' && r['description']?.toString().trim().toLowerCase()=='oil separator',)?_carryReview:null,
      advanceBalance:()=>_viewRepository.advance(widget.employeeId!),
      recordPayment:_recordWeekly,onPaymentSaved:_load,
      onWeekChanged:(week)=>setState(()=>_week=week),
      saveDraft:(week,selected,adjustment,repayment,reason) async {
        await _taskEditRepository.savePayrollDraft(widget.employeeId!,_date(week),selected,adjustment:adjustment,repayment:repayment,reason:reason,);
        if (mounted) setState(() => _draftRevision++);
      },
      loadDraft:(week)=>_viewRepository.payrollDraftDetails(widget.employeeId!,_date(week)),
      profileAdvanceBalance: _advanceBalance,
      advancePanel: _advancePanel,
    );
  }

  Widget _taxesTab() => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      _panel(const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Taxes', style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w800),),
          SizedBox(height: 10),
          Text('Your own earnings, federal / self-employment / '
            'Louisiana estimated taxes, suggested reserve and 1099-NEC.',),
          SizedBox(height: 10),
          Text('Tax calculations and 1099s are intentionally disabled '
            'until actual posted pay, classification, W-9 permissions '
            'and tax-year rules are verified.',
            style: TextStyle(color: Color(0xFF64748B)),),
        ],
      ),),
    ],
  );

  void _selectAdvanceSection(_AdvanceSection? section) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      final next = _advanceSection == section ? null : section;
      if (next == _AdvanceSection.balance && _balanceOperation == null) {
        final balance = _advanceBalance;
        _opening.text = _isOpeningBalance || balance == null
            ? ''
            : (balance / 100).toStringAsFixed(2);
      }
      _advanceSection = next;
      _advanceError = null;
    });
  }

  Widget _advancePanel([Widget Function(VoidCallback cancel)? paycheckEditor]) {
    final expanded = _advanceExpanded ?? ((_advanceBalance ?? 0) > 0);
    final enabled = !_busy && !_confirmingBalance;
    final section = _advanceSection;
    final selectedMode = section == _AdvanceSection.paycheck ||
            section == _AdvanceSection.repayment
        ? section
        : null;
    return Card(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.payments_outlined, color: taskGreen),
            title: const Text(
              'Advances & Repayments',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            trailing: Icon(
              expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            ),
            onTap: enabled ? () {
              FocusManager.instance.primaryFocus?.unfocus();
              setState(() => _advanceExpanded = !expanded);
            } : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF166F9D), BriskersColors.customerSave, Color(0xFF174B92)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      const Text(
                        'Outstanding balance',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        _moneyNullable(_advanceBalance),
                        key: const Key('outstanding-advance-balance'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                if (expanded) ...[
                  if (paycheckEditor != null)
                    SegmentedButton<_AdvanceSection>(
                      segments: [
                        ButtonSegment(
                          value: _AdvanceSection.paycheck,
                          label: const Text('Deduct from paycheck', textAlign: TextAlign.center),
                          enabled: enabled,
                        ),
                        ButtonSegment(
                          value: _AdvanceSection.repayment,
                          label: const Text('Record separate repayment', textAlign: TextAlign.center),
                          enabled: enabled,
                        ),
                      ],
                      selected: {?selectedMode},
                      emptySelectionAllowed: true,
                      selectedIcon: const Icon(Icons.check_circle, color: taskGreen),
                      onSelectionChanged: (selection) =>
                          _selectAdvanceSection(selection.firstOrNull),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: enabled
                          ? () => _selectAdvanceSection(_AdvanceSection.repayment)
                          : null,
                      icon: Icon(
                        section == _AdvanceSection.repayment
                            ? Icons.check_circle
                            : Icons.add_circle_outline,
                      ),
                      label: const Text('Record separate repayment'),
                    ),
                  if (section != null &&
                      (section != _AdvanceSection.paycheck || paycheckEditor != null)) ...[
                    const SizedBox(height: 12),
                    switch (section) {
                      _AdvanceSection.balance => _balanceForm(),
                      _AdvanceSection.paycheck =>
                        paycheckEditor!(() => _selectAdvanceSection(null)),
                      _AdvanceSection.repayment => _repaymentForm(),
                      _AdvanceSection.history => _advanceHistory(),
                    },
                  ],
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: enabled
                            ? () => _selectAdvanceSection(_AdvanceSection.balance)
                            : null,
                        child: const Text('Correct amount owed'),
                      ),
                      TextButton(
                        onPressed: enabled
                            ? () => _selectAdvanceSection(_AdvanceSection.history)
                            : null,
                        child: const Text('Repayment history'),
                      ),
                    ],
                  ),
                  if (_advanceError case final message?) ...[
                    const SizedBox(height: 8),
                    Text(message, style: const TextStyle(color: BriskersColors.destructive)),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _advanceField(String label, {String? prefixText}) =>
      InputDecoration(
        labelText: label,
        prefixText: prefixText,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: const OutlineInputBorder(),
      );

  Widget _balanceForm() {
    final proposed = _proposedBalance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _opening,
          enabled: !_busy && _advanceBalance != null,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          selectAllOnFocus: true,
          onTapAlwaysCalled: true,
          onTap: () => _selectAmount(_opening),
          onChanged: (_) => setState(() => _advanceError = null),
          decoration: _advanceField(
            _isOpeningBalance ? 'Opening amount owed' : 'New amount owed',
            prefixText: r'$ ',
          ).copyWith(
            suffixIcon: IconButton(
              icon: const Icon(Icons.calculate_outlined),
              tooltip: 'Amount calculator',
              onPressed: _busy || _advanceBalance == null ? null : () async {
                final cents = await showAmountCalculator(
                  context,
                  initial: _opening.text,
                  balanceCents: _advanceBalance,
                );
                if (cents != null && mounted) {
                  setState(() {
                    _opening.text = (cents / 100).toStringAsFixed(2);
                    _advanceError = null;
                  });
                }
              },
            ),
          ),
        ),
        if (!_isOpeningBalance) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _balanceReason,
            enabled: !_busy,
            onChanged: (_) => setState(() => _advanceError = null),
            decoration: _advanceField('Adjustment reason (required)').copyWith(
              helperText: 'Enter a reason to enable Save Balance.',
            ),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          proposed == null && _opening.text.trim().isNotEmpty
              ? 'Enter a valid amount or use the calculator.'
              : 'Proposed balance: ${_moneyNullable(proposed)}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        FilledButton(
          onPressed: _canSaveAdvance && proposed != null &&
                  proposed != _advanceBalance &&
                  (_isOpeningBalance || _balanceReason.text.trim().isNotEmpty)
              ? _saveOpening
              : null,
          child: const Text('Save Balance'),
        ),
      ],
    );
  }

  Widget _repaymentForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _repayment,
        enabled: !_busy,
        selectAllOnFocus: true,
        onTapAlwaysCalled: true,
        onTap: () => _selectAmount(_repayment),
        onChanged: (_) => setState(() => _advanceError = null),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: _advanceField('Repayment amount', prefixText: r'$ ').copyWith(
          suffixIcon: IconButton(
            icon: const Icon(Icons.calculate_outlined),
            tooltip: 'Calculator for separate repayment',
            onPressed: _busy ? null : () async {
              final employee = _employee;
              final cents = await showAmountCalculator(context, initial: _repayment.text);
              if (cents != null && mounted && !_busy && employee == _employee) {
                setState(() {
                  _repayment.text = (cents / 100).toStringAsFixed(2);
                  _advanceError = null;
                });
              }
            },
          ),
        ),
      ),
      if (_repayment.text.trim().isNotEmpty && _repaymentCents == null)
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('Enter a positive amount up to the current balance.'),
        ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _busy ? null : () async {
          final date = await showDatePicker(
            context: context,
            initialDate: _repaymentDate,
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (date != null && mounted) setState(() => _repaymentDate = date);
        },
        icon: const Icon(Icons.calendar_month),
        label: Text('Repayment date: ${DateFormat.yMMMd().format(_repaymentDate)}'),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        initialValue: _repaymentMethod,
        isExpanded: true,
        decoration: _advanceField('Repayment method'),
        items: const [
          DropdownMenuItem(value: 'Cash', child: Text('Cash')),
          DropdownMenuItem(value: 'Zelle', child: Text('Zelle')),
          DropdownMenuItem(value: 'Check', child: Text('Check')),
          DropdownMenuItem(value: 'ACH', child: Text('ACH')),
        ],
        onChanged: _busy ? null : (value) => setState(() => _repaymentMethod = value ?? 'Cash'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _repaymentNote,
        enabled: !_busy,
        decoration: _advanceField('Notes (optional)'),
      ),
      const SizedBox(height: 10),
      FilledButton(
        onPressed: _canSaveAdvance && _repaymentCents != null ? _saveRepayment : null,
        child: const Text('Save Repayment'),
      ),
    ],
  );

  Widget _advanceHistory() {
    final deductions = _history.where((p) => (p['repayment'] as num? ?? 0) > 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_repayments.isEmpty && deductions.isEmpty)
          const Text('No repayments recorded'),
        for (final item in _repayments)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text("${_money(item['cents'] as int)} · ${item['method']}"),
            subtitle: Text([
              item['date'] as String,
              if ((item['note'] as String?)?.isNotEmpty ?? false) item['note'] as String,
            ].join('\n')),
            trailing: Text(_money(item['remaining_after_cents'] as int)),
          ),
        for (final payment in deductions)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('Payroll deduction: ${_money(payment['repayment'] as int)}'),
            subtitle: Text("${payment['verified_date']}${payment['reversed_at'] == null ? '' : ' · Reversed'}"),
          ),
        if (_openingAdvance != null || _advanceAdjustments.isNotEmpty) ...[
          const Divider(),
          const Text('Balance history', style: TextStyle(fontWeight: FontWeight.w700)),
          if (_openingAdvance != null)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('Original opening debt: ${_money(_openingAdvance!)}'),
            ),
          for (final item in _advanceAdjustments)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('Balance adjustment: ${_money(item['before_cents'] as int)} → '
                  '${_money(item['after_cents'] as int)}'),
              subtitle: Text("${item['reason']} · ${item['recorded_at']}"),
            ),
        ],
      ],
    );
  }

  Future<void> _newJobLabor() async {
    if (!_canView || widget.jobId == null) return;
    try {
      final documents = await LocalDocumentRepository(database: _db,)
          .listByJob(widget.businessId, widget.jobId!);
      if (!mounted || !_canView) return;
      final invoices = documents.where((row) => row['kind'] == 'invoice' && row['id'] is String).toList();
      if (invoices.isEmpty) {
        setState(() => _error = 'Create an invoice for this job before adding labor.',);
        return;
      }
      final id = invoices.length == 1 ? invoices.single['id'] as String :
          await showDialog<String>(context: context, builder: (dialog) =>
            SimpleDialog(title: const Text('Choose invoice'), children: [
              for (final invoice in invoices)
                SimpleDialogOption(onPressed: () => Navigator.pop(dialog, invoice['id']),
                  child: Text('Invoice ${invoice['document_number'] ?? ''}',),),
            ],),);
      if (!mounted || !_canView || id == null) return;
      final detail = await LocalDocumentDetailCache(database:_db,).load(widget.businessId,id);
      if (!mounted || !_canView) return;
      final raw = detail?['lines'] ?? detail?['items'];
      final lines = raw is List ? raw.whereType<Map>().map(Map<String,dynamic>.from)
          .where((r)=>r['id'] is String && r['line_kind']!='discount').toList()
          : <Map<String,dynamic>>[];
      if (lines.isEmpty) {
        setState(()=>_error='No saved service items are available on this invoice.',);
        return;
      }
      final line = await showTaskSelection<Map<String, dynamic>>(
        context, title: 'Choose existing service', options: lines,
        label: (row) => (row['name'] ?? row['description'] ?? 'Service').toString(),
        description: (row) => (row['description'] ?? '').toString(),
      );
      if (!mounted || !_canView || line == null) return;
      await _assign(id,line,enterHours:true);
      if (mounted && _canView) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _newServiceTask() => _serviceEditor();
  Future<void> _serviceEditor([Map<String, dynamic>? source, bool focusDescription = false]) async {
    if (!mounted || !_canView) return;
    final known = await _viewRepository.employees();
    final roster=await OfflineJobAdminService(database:_db,).cachedEmployees(widget.businessId);
    final staff= <String, Map<String, dynamic>>{for(final r in known) r['id'] as String:r,for(final r in roster) r['id'] as String:{...?known.where((k)=>k['id']==r['id']).firstOrNull,...r,},};
    final jobs=(await _db.customSelect(
                  "SELECT j.*,d.work_date FROM local_jobs j LEFT JOIN local_job_work_dates d ON d.business_id=j.business_id AND d.job_id=j.id WHERE j.business_id=? AND j.status NOT IN ('deleted','cancelled') ORDER BY j.created_at DESC",
      variables:[Variable(widget.businessId)],
                )
                .get())
            .map((r) => Map<String, dynamic>.from(r.data))
            .toList();
    final task = source == null
        ? null
        : (source['task_id'] ?? source['id']) as String;
    final allocations = task == null
        ? <Map<String, dynamic>>[]
        : (await _viewRepository.work())
              .where((r) => r['task_id'] == task)
              .toList();
    final job = (source?['job_id'] ?? widget.jobId ?? '').toString();
    final lead =
        jobs.where((j) => j['id'] == job).firstOrNull?['assigned_employee_id']
            as String?;
    final date = jobs.where((j)=>j['id']==job).firstOrNull?['work_date'] as String? ?? LocalTaskSchedule.day(LocalJobWorkDate.today());
    final settled = allocations.any(
      (r) =>
          r['paid'] == 1 ||
          r['owner_prior_paid'] == 1 ||
          (r['paid_minutes'] as int? ?? 0) > 0,
    );
    final operation = _operationId();
    if (!mounted || !_canView) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceTaskEditor(
          jobs: jobs,
          employees: staff.values.toList(),
          pickCustomer:()async{
            final customer=await Navigator.push<Map<String,dynamic>>(context,MaterialPageRoute(builder:(_)=>JobCustomerPickerScreen(businessId:widget.businessId,localCustomers:LocalCustomerRepository(database:_db))));
            if(customer==null || !mounted)return null;
            final details=await LocalCustomerRepository(database:_db).customerDetail(widget.businessId,customer['id'] as String);
            return {...customer,'vehicles':details?['vehicles']??[]};
          },
          focusDescription: focusDescription,
          editing: task != null,
          onOpenJob: (id) => _openRecordedWork(id, invoice: false),
          onLinkInvoiceLabor:widget.jobId==null?null:(){Navigator.pop(context,false);unawaited(_newJobLabor());},
          invoiceLabor: source?['source_kind'] == 'invoice',
          statusLocked: allocations.any((r) => r['state'] == 'Done') || source?['status']=='done' || source?['archived_labor']==1,
          payrollLocked: settled,
          initial: ServiceTaskDraft(
            job: job,
            taskName: source?['task_name'] as String?,
            description: (source?['description'] ?? source?['title'] ?? '')
                .toString(),
            mechanics: allocations.isEmpty
                ? task!=null?<TaskMechanicDraft>[]:[TaskMechanicDraft(widget.employeeId ?? lead ?? '', 0)]
                : allocations
                      .map(
                        (r) => TaskMechanicDraft(
                          r['employee_id'] as String,
                          r['estimated_minutes'] as int? ??
                              r['actual_minutes'] as int? ??
                              0,
                          originalEmployee: r['employee_id'] as String,
                          hoursEditable: r['can_edit_planned_hours']==true,
                          locked:
                              r['paid'] == 1 ||
                              r['owner_prior_paid'] == 1 ||
                              (r['paid_minutes'] as int? ?? 0) > 0,
                        ),
                      )
                      .toList(),
            start: source?['work_start_date'] as String? ?? date,
            end: source?['work_end_date'] as String? ?? date,
            priority: source?['priority'] as String? ?? 'Normal',
            status: source?['status']=='done' || source?['archived_labor']==1 || (allocations.isNotEmpty && allocations.every((r) => r['state'] == 'Done'))
                ? 'Done'
                : allocations.any((r) => r['state'] == 'In Progress' || r['state']=='Done')
                ? 'In Progress'
                : 'Open',
            treatment: settled?'preserve':source?['payroll_treatment'] as String? ?? 'unpaid',
          ),
          save: (v) async {
            if (!_canView) throw StateError('Owner account changed.');
            await _db.transaction(()async{
              var jobId=v.job;
              if(jobId=='new') {
                final prior=await _db.customSelect('SELECT job_id FROM regular_payroll_tasks WHERE business_id=? AND labor_id=?',variables:[Variable(widget.businessId),Variable(jsonEncode(['job',operation]))]).getSingleOrNull();
                jobId=prior?.data['job_id'] as String? ?? await OfflineJobAdminService(database:_db).queueJobCreate(widget.businessId,customerId:v.newCustomer!['id'] as String,customerName:(v.newCustomer!['display_name']??v.newCustomer!['name']??'Customer').toString(),vehicleId:v.newVehicle?['id'] as String?,vehicleLabel:v.newVehicle==null?null:'${v.newVehicle!['year']??''} ${v.newVehicle!['make']??''} ${v.newVehicle!['model']??''}',title:v.description);
              }
            await _taskEditRepository.saveServiceTask(
              operation: operation,
              task: task,
              job: jobId,
              description: v.description,
              taskName: v.taskName,
              mechanics: v.mechanics
                  .map(
                    (m) => <String, dynamic>{
                      'employee': m.employee,
                      'previous': m.originalEmployee,
                      'minutes': m.minutes,
                      'name': staff[m.employee]?['name'] ?? m.employee,
                      'rate': staff[m.employee]?['rate'] ?? 0,
                    },
                  )
                  .toList(),
              datesEdited: v.datesEdited,
              start: v.start,
              end: v.end,
              priority: v.priority,
              status: v.status,
              treatment: v.treatment,
            );
              if(!_canView)throw StateError('Owner account changed.');
            });
          },
        ),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _createEmployeeGeneralTask()=>_generalEditor();
  Future<void> _editJobGeneralTask(Map<String,dynamic> task)=>_generalEditor(task);
  Future<void> _generalEditor([Map<String,dynamic>? source]) async {
    if(!_canView || _busy)return;
    final roster=await OfflineJobAdminService(database:_db).cachedEmployees(widget.businessId);
    final staff={for(final e in _employees)e['id']:e,for(final e in roster)e['id']:e};
    final jobs=(await _db.customSelect("SELECT * FROM local_jobs WHERE business_id=? AND status NOT IN ('deleted','cancelled') ORDER BY created_at DESC",variables:[Variable(widget.businessId)]).get()).map((r)=>Map<String,dynamic>.from(r.data)).toList();
    final operation=_operationId();
    if (!mounted || !_canView) return;
    final saved = await Navigator.push<bool>(
      context,MaterialPageRoute(builder:(_)=>GeneralTaskEditor(
      sharedBottomNavigationBar: widget.sharedBottomNavigationBar, employees:staff.values.toList(),jobs:jobs,initial:source??{'employee_id':widget.employeeId,'job_id':widget.jobId},save:(v)async{if(!_canView)throw StateError('Owner account changed.');
    if (v['reminder_enabled'] ==1 && !await LocalTaskReminders().prepare(requestPermission: true)) {
              throw StateError('Enable notifications in device settings, or turn the reminder off to save.');
            }
            await _taskEditRepository.saveGeneralTask(operation:operation,
      id:source?['id'] as int?, previousEmployee:source?['employee_id'] as String?,
      employee:v['employee_id'] as String, description:v['description'] as String,
      category:v['category'] as String,job:v['job_id'] as String?,due:v['due_at']==null?null:DateTime.fromMillisecondsSinceEpoch(v['due_at'] as int
    ),reminder:v['reminder_enabled']==1,reminderMinutes:v['reminder_minutes'] as int);
      await _syncSavedGeneralReminders();
    })));
    if(saved==true && mounted)await _load();
  }

  Widget _tasksTab() => Builder(builder: (context) {
    final week = EmployeeWorkReview.monday(_week);
    final weekKey = _date(week);
    final recorded = _verifiedWeeks?[weekKey];
    final balance = _history.where((payment) =>
      payment['week'] == weekKey && payment['employee_id'] == widget.employeeId &&
      payment['reversed_at'] == null,
    ).fold<int>(0, (sum, payment) {
      final net = payment['net'] as int;
      return sum + (payment['original_net'] as int? ?? net) - net;
    });
    return EmployeeWorkReview(
        key: ValueKey('${widget.employeeId}-WorkScroll'),
        employeeId: widget.employeeId,
        week: week,
        rows: _work,
        generalTasks: _generalTasks,
        jobs: const [],
        employeeName: _employeeLabel(widget.employeeId),
        paidMinutesThisWeek: _verifiedWeeks == null ? null : recorded?.minutes ?? 0,
        onWeekChanged: (week) => setState(() => _week = week),
        onJob: (id) => _openRecordedWork(id, invoice: false),
        onTask: (task) => unawaited(
          _openTaskDetails({...task, 'line_id': task['task_id']}, false),
        ),
        onGeneralTask: (task) => unawaited(_openTaskDetails(task, true)),
        payrollSummary: WorkPayrollSummary(
          week: week,
          rows: _work,
          recorded: recorded,
          paymentBalance: balance,
          historyLoaded: _verifiedWeeks != null,
          historyLoading: _loadingLocal,
          revision: _draftRevision,
          loadDraft: (week) => _viewRepository.payrollDraftDetails(
            widget.employeeId!,
            _date(week),
          ),
          onReview: () => DefaultTabController.of(context).animateTo(1),
        ),
    );
  });

  String _employeeLabel(String? employee) {
    final row = _employees.where((row) => row['id'] == employee).firstOrNull;
    if(row!=null)return EmployeeNicknameStore.displayLabel(row,_employees);
    return employee==widget.employeeId ? widget.employeeName??'Employee' : employee??'Unassigned';
  }

  Widget _recoveryStatus() {
    if(!_canView)return const SizedBox.shrink();
    return Padding(padding:const EdgeInsets.symmetric(horizontal:12,vertical:3),
      child:Row(children:[
        Expanded(child:Text(_backfillActive
          ? 'Checking up to 25 invoices: $_checkedInvoices'
          : _backfillDone ? 'Historical invoice recovery complete'
          : _checkedInvoices>0
            ? 'Last batch: $_checkedInvoices checked · $_recoveredTasks newly linked · $_unavailableInvoices unavailable'
            : 'Historical invoice recovery (optional)',
          style:const TextStyle(fontSize:11),),),
        if(!_backfillActive && !_backfillDone)
          TextButton(onPressed:()=>unawaited(_backfillTasks()),
            child:Text(_checkedInvoices==0?'Recover 25':'Continue'),),
      ],),);
  }

  Map<String,List<Map<String,dynamic>>> get _taskAllocations {
    final result=<String,List<Map<String,dynamic>>>{};
    for(final row in _work){(result[row['task_id'] as String]??=[]).add(row);}
    return result;
  }
  List<Map<String,dynamic>> get _serviceTaskRows {
    final byTask=_taskAllocations;
    final service = [
      for (final entry in byTask.entries)
        if (!entry.value.every((row) => row['duplicate_of_task_id'] != null))
        {...entry.value.first,
          // Grouped task status must use ALL mechanic allocations. Paid
          // history is not active work, and an unpaid completed split must
          // remain visible under Unpaid until its coverage is settled.
          'remaining_minutes': entry.value.fold<int>(0,(sum,r)=>
            sum+(r['remaining_minutes'] as int? ?? 0),),
          'paid': entry.value.every((r)=>r['state']=='Done') &&
              entry.value.every((r)=>(r['remaining_minutes'] as int? ?? 0)==0,) &&
              entry.value.any((r)=>(r['actual_minutes'] as int? ?? 0)>0) ? 1 : 0,
          'completed_date': ([
            for(final r in entry.value)
              if(r['completed_date']?.toString().isNotEmpty==true)
                r['completed_date'].toString(),
          ]..sort()).lastOrNull,
          'source_missing': entry.value.every((r)=>r['source_active']==0 && r['state']=='Open',)?1:0,
          'line_id': entry.key,
          'document_id': entry.value.first['invoice_id'],
          'source_description': entry.value.first['description'],
          'status': entry.value.every((row) => row['state'] == 'Done') ? 'done'
              : entry.value.any((row) => row['state'] != 'Open') ? 'in_progress'
              : 'planned',
        },
    ];
    for (final task in _taskSources) {
      if (byTask.containsKey(task['id']) || task['source_active'] == 0) { continue;
      }
      service.add({
        ...task, 'line_id': task['id'], 'document_id': task['invoice_id'],
        'source_description': task['description'], 'status': task['source_kind']=='invoice' && !LocalInvoiceTaskStore.currentPayrollDate(task['invoice_date']) ? 'done' : 'planned',
      });
    }
    return service;
  }

  Future<void> _runPriority(Map<String,dynamic> row,bool general,String priority) async {
    try{await _priority(row,general,priority);}catch(e){if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not save priority: $e')));
      }
    }
  }
  Future<void> _priority(Map<String,dynamic> row,bool general,String priority) async {
    await _taskEditRepository.setTaskPriority((general?row['id']:row['line_id']??row['task_id']??row['id']).toString(),priority,general:general);
    await _load();
  }

  Future<void> _openTaskDetails(Map<String,dynamic> initial,bool general) async {
    final id=(general?initial['id']:initial['line_id']).toString();
    Future<({Map<String,dynamic> task,List<Map<String,dynamic>> allocations})> snapshot() async {
      final pending=_localRead;if(pending!=null)await pending.timeout(const Duration(seconds:8));
      if(!_canView)throw StateError('Sign in as Owner to view this task.');
      final row=(general?_generalTasks:_serviceTaskRows).where((r)=>(general?r['id']:r['line_id']).toString()==id).firstOrNull;
      if(row==null) {
        throw StateError('Task no longer available. Return to Tasks and refresh.');
      }
      final job=row['job_id']?.toString();
      final jobs=job==null?[]:await _db.customSelect('SELECT status,job_number,customer_name,vehicle_label FROM local_jobs WHERE business_id=? AND id=?',variables:[Variable(widget.businessId),Variable(job)]).get();
      // Payroll is employee-scoped; the existing Task Details must still show
      // every saved mechanic allocation of this exact task.
      final allocations=general?<Map<String,dynamic>>[]:widget.employeeId==null
          ? _taskAllocations[id]??[]
          : (await _viewRepository.work(job:job)).where((r)=>r['task_id']==id).toList();
      final paymentHistory = general
          ? <Map<String, dynamic>>[]
          : await _viewRepository.taskPaymentHistory(id);
      final detailed = [
        for (final allocation in allocations)
          {
            ...allocation,
            'payment_history': paymentHistory
                .where(
                  (p) =>
                      p['credit_id'] == allocation['id'] &&
                      p['employee_id'] == allocation['employee_id'],
                )
                .toList(),
          },
      ];
      return (task:{...row,if(allocations.isNotEmpty)'status':allocations.every((r)=>r['state']=='Done')?'done':allocations.any((r)=>r['state']!='Open')?'in_progress':'planned',if(jobs.isNotEmpty)...{'job_status':jobs.first.data['status'],'job_number':jobs.first.data['job_number'],'customer_name':jobs.first.data['customer_name'],'vehicle_label':jobs.first.data['vehicle_label']}},allocations: detailed,
      );
    }
    final data=await snapshot();if(!mounted)return;
    await Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>ApprovedTaskDetails(
      initialTask:data.task,allocations:data.allocations,general:general,employeeName:_employeeLabel,reload:snapshot,
      sharedBottomNavigationBar: widget.sharedBottomNavigationBar,
      onEdit:()async{final current=await snapshot();if(general){await _generalEditor(current.task);}else{await _serviceEditor(current.task);}},
      onEditDescription:()async{final current=await snapshot();if(general){await _generalEditor(current.task);}else{await _serviceEditor(current.task,true);}},
      onPriority:(p)async{final current=await snapshot();await _priority(current.task,general,p);},
      onProgress:(finish)async{
        final current=await snapshot();
        if(general){await _changeGeneralTaskStatus(current.task['employee_id'] as String,current.task['id'] as int,finish?'done':'in_progress');}
        else if(finish){await _markTaskDone(current.task,current.allocations);}
        else {for(final allocation in current.allocations.where((r)=>r['state']=='Open')){await _recordTaskProgress(allocation);}}
        if(_error!=null)throw StateError(_error!);
      },
      onJob:data.task['job_id']==null?null:()=>_openRecordedWork(data.task['job_id'] as String,invoice:false),
      onInvoice:data.task['invoice_id']==null?null:()=>_openRecordedWork(data.task['invoice_id'] as String,invoice:true),
    )));
  }

  void _openInvoiceHistory()=>Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>HistoricalInvoiceLaborReview(
    sharedBottomNavigationBar:widget.sharedBottomNavigationBar,
    businessId:widget.businessId,database:_db,weekStart:DateTime(_week.year,_week.month,_week.day).subtract(Duration(days:_week.weekday-1)),canView:()=>mounted&&_canView)));

  Widget _workspace() {
    final byTask=_taskAllocations;
    final service=_serviceTaskRows;
    final jobRow=_workspaceJob??service.where((r)=>r['job_id']==widget.jobId).firstOrNull??_generalTasks.where((r)=>r['job_id']==widget.jobId).firstOrNull;
    return Scaffold(
      backgroundColor:taskCanvas,
      bottomNavigationBar: widget.sharedBottomNavigationBar,
      appBar: ApprovedTasksHeader(title:_jobMode?'Job ${jobRow?['job_number']??''}':'Tasks',subtitle:_jobMode ? (jobRow?['customer_name']?.toString()) : null,actions:[PopupMenuButton<String>(icon:const Icon(Icons.more_vert,color:Colors.white),onSelected:(_)=>_openInvoiceHistory(),itemBuilder:(_)=>[const PopupMenuItem(value:'history',child:Text('Invoice labor history'))])]),
      body: SafeArea(
        top: false,
        child: Column(children: [
        if(!_canView)const Text('Sign in as Owner to view tasks.'),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        if (_backfillActive) _recoveryStatus(),
        if (_canView)
          Expanded(child: _jobMode && widget.invoiceId == null
            ? JobScopedTasks(
                onOpenTask:(r,g)=>unawaited(_openTaskDetails(r,g)),
                onPriority:(r,g,p)=>unawaited(_runPriority(r,g,p)),
                jobId: widget.jobId!,
                onMarkAllDone: _markAllJobTasksDone,
                markAllDoneCount: JobTaskCompletionPlan.fromRows(widget.jobId!,
                  _work,_generalTasks,DateTime.now(),).count,
                serviceTasks: service,
                generalTasks: _generalTasks,
                allocationsByLine: byTask,
                employeeName: _employeeLabel,
                onAddLabor: _newServiceTask,
                onAddGeneral: _createEmployeeGeneralTask,
                onLaborProgress: (allocation, finish) =>
                    _recordTaskProgress(allocation, markDone: finish),
                onGeneralProgress: (id, status) async {
                  final task = _generalTasks.where((r) => r['id'] == id).firstOrNull;
                  if (task != null) {
                    await _changeGeneralTaskStatus(
                      task['employee_id'] as String, id, status,);
                  }
                },
                onReconcileLabor: (row) => unawaited(_confirmHistoricalPaid(row)),
                onReviewLabor: (row) => unawaited(_reviewCarry(row)),
                        onEditLabor: (row) => _serviceEditor(row),
                onManageLabor: (row) => unawaited(_serviceEditor(row)),
                onManageGeneral: (row) =>
                    unawaited(_editJobGeneralTask(row)),
              )
            : TasksWorkspace(
            onOpenTask:(r,g)=>unawaited(_openTaskDetails(r,g)),
            onPriority:(r,g,p)=>unawaited(_runPriority(r,g,p)),
            scopedJob: widget.jobId,
            serviceTasks: service,
            generalTasks: _generalTasks,
            allocationsByLine: byTask,
            employeeName: _employeeLabel,
            employeeIds: [
              for (final row in _employees)
                if (row['id'] case final String id) id,
            ],
            serviceTaskCard: (row) => byTask.containsKey(row['line_id'])
                ? Column(children: [
                    for (final allocation in byTask[row['line_id']]!) _taskCard(allocation, manage:row['invoice_id'] is! String,),
                    if (row['invoice_id'] is String && row['source_line_id'] is String && row['source_active'] != 0)
                      TextButton.icon(icon:const Icon(Icons.edit_outlined),
                        label:const Text('Edit Assignment'),
                        onPressed:_busy?null:()=>_openAssignments(row),),
                  ],)
                : ListTile(
                    title: Text(row['description'] as String),
                    subtitle: Text(row['archived_labor']==1
                      ? 'Historical invoice labor · view only' : 'Unassigned · Planned',),
                    trailing: row['archived_labor']==1 ? const Icon(Icons.lock_outline)
                      : const Icon(Icons.edit_outlined),
                    onTap: row['invoice_id'] is String && row['source_line_id'] is String
                      ? () => _openAssignments(row) : null,
                  ),
            onEditService:(row)=>unawaited(_serviceEditor(row)),
            onEditGeneral:(row)=>unawaited(_editJobGeneralTask(row)),
            onMarkDone:(row)=>unawaited(_markTaskDone(row,byTask[row['line_id']]??[])),
            onAddService : _newServiceTask,
            onAddRecheck: (jobId) => _addRecheck(jobId: jobId),
            onAddGeneral: _createEmployeeGeneralTask,
            onGeneralStatus: (id, status) async {
              final row = _generalTasks.where((row) => row['id'] == id).firstOrNull;
              if (row == null) return;
              await _changeGeneralTaskStatus(row['employee_id'] as String, id, status);
            },
            onOpenJob: (id) => _openRecordedWork(id, invoice: false),
            onOpenInvoice: (id) => _openRecordedWork(id, invoice: true),
            onEmployeeTap: (id) => _openEmployeeProfile(id,_week,0),
          ),),
      ],
        ),),
    );
  }

  Future<void> _markTaskDone(Map<String,dynamic> task,List<Map<String,dynamic>> allocations) async {
    for(final row in allocations.where((r)=>r['state']!='Done' && r['archived_labor']!=1 && r['source_active']!=0 && r['assignment_conflict']!=1,
    )) {
      await _recordTaskProgress(row,markDone:true);
    }
  }

  Widget _profile() => DefaultTabController(
    length: 4,
    initialIndex: widget.initialTab,
    child: Scaffold(
      backgroundColor:taskCanvas,
      bottomNavigationBar: widget.sharedBottomNavigationBar,
      appBar: ApprovedTasksHeader(title:'Employee Profile',actions:[PopupMenuButton<String>(icon:const Icon(Icons.more_vert,color:Colors.white),onSelected:(v){if(v=='details'){widget.openEmployeeDetails?.call();}else{unawaited(_load());}},itemBuilder:(_)=>[if(widget.openEmployeeDetails!=null)const PopupMenuItem(value:'details',child:Text('Details')),const PopupMenuItem(value:'refresh',child:Text('Refresh'))])]),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 10), child: _header(),),
        const ApprovedProfileTabs(),
        if(!_canView)const Text('Sign in as Owner to view profile.'),
        if (_authorizing || _loadingLocal || _backfillActive) const LinearProgressIndicator(),
        if (_backfillActive) _recoveryStatus(),
        if (_error != null)
          ConstrainedBox(constraints:const BoxConstraints(maxHeight:96),child:SingleChildScrollView(child:ListTile(dense: true, title: Text(_error!), trailing: TextButton(
            onPressed: _loadingLocal ? null : () => unawaited(_load()), child: const Text('Retry'),),),),),
        Expanded(child: Builder(builder: (context) {
          final controller = DefaultTabController.of(context);
          return AnimatedBuilder(
            animation: controller,
            builder: (context, _) => IndexedStack(
              sizing: StackFit.expand,
              index: controller.index == 0 ? 0 : 1,
              children: [
                // Keep the Work scroll position and expanded cards mounted
                // while other tabs are active.
                KeyedSubtree(
                  key: ValueKey(widget.employeeId),
                  child: _safeTab(_tasksTab, 'Work'),
                ),
                KeyedSubtree(
                  key: ValueKey(controller.index),
                  child: switch (controller.index) {
                    1 => _safeTab(_payrollTab, 'Payroll'),
                    2 => _safeTab(_reportsPanel, 'Reports'),
                    3 => _taxesTab(),
                    _ => const SizedBox.shrink(),
                  },
                ),
              ],
            ),
          );
        }),),
      ],),
    ),
  );

  Widget _safeTab(Widget Function() content, String name) {
    if (_canView && _hasLocalData && (name=='Work'||_reportsLoaded)) { return SafeArea(top: false, child: content());
    }
    return Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(
      !_canView ? '$name requires the saved Owner account.'
        : _loadingLocal ? 'Loading saved $name…' : 'Saved $name has not loaded. Use Retry above.',),),);
  }

  Future<bool> _correctRecordedPayment(
    Map<String, dynamic> payment, PayrollPaymentAction action,
  ) async {
    if (_busy || !_canView) return false;
    final correction = await PayrollPaymentCorrection.confirm(
      context, payment, _employeeLabel(payment['employee_id'] as String), action,
    );
    if (correction == null || !mounted) return false;
    try {
      await _run(() async {
        await correction.apply(widget.businessId, _grant!.actorId,
          (operation) => _localPaymentLedger(operation: operation));
      }, rethrowError: true);
      return true;
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      return false;
    }
  }

  Widget _reportsPanel() => _PayrollViewport(minHeight:360,child:Column(children: [
    if (_canView && (widget.employeeId ?? _employee) != null)
      TextButton.icon(icon: const Icon(Icons.manage_search),
        label: const Text('Review historical expenses'),
        onPressed: () => HistoricalExpenseReview.open(context,
          businessId: widget.businessId,
          employeeName: _employeeLabel(widget.employeeId ?? _employee),
          access: _historyUnlocked, canView: () => mounted && _canView,
          cache: expenses.LocalFinancialCache(database: _db),),),

    if (_canView)
      TextButton.icon(
        icon: const Icon(Icons.payments_outlined),
        label: const Text('Review payroll expenses'),
        onPressed: () => showPayrollExpenseReview(context,
          database: _db, business: widget.businessId, week: _week,
          employeeId: widget.employeeId ?? _employee),
      ),

    if (_pendingPayments.isNotEmpty)
      MaterialBanner(content: Text(
        "${_pendingPayments.length} payment request(s) pending — not recorded as paid. "
        "Reconnect over shop Wi-Fi, refresh and review unpaid work before retrying.",),
        actions: [TextButton(onPressed: () => showOwnerPayrollConnection(context, widget.businessId),
          child: const Text("Connect"),),],),
    Expanded(child: PayrollHistoryPanel(
              payments: _history,
              onPaymentAction: _correctRecordedPayment,
              employeeName: _employeeLabel(widget.employeeId ?? _employee),
              onOpenTask: (row) => unawaited(_openTaskDetails({...row, 'line_id': row['task_id']}, false)),
              unlocked: _historyUnlocked,
              onOpenJob: (id) => _openRecordedWork(id, invoice: false),
              onOpenInvoice: (id) => _openRecordedWork(id, invoice: true),
            ),),
  ],),);

  Future<void> _openEmployeeProfile(String id, DateTime week, int tab) async {
    final row = _employees.where((row) => row['id'] == id).firstOrNull;
    if (row == null) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => OwnerPayrollScreen(
        businessId: widget.businessId, employeeId: id, employeeName: _employeeLabel(id),
        employeeRole: (row['position'] ?? row['position_name'])?.toString(),
        employeeLegalName: row['name']?.toString(),
        employeePayType: row['payment_type']?.toString(),
        initialWeek: week, initialTab: tab, database: widget.database,
        sharedBottomNavigationBar: widget.sharedBottomNavigationBar,
        unlockOwner: widget.unlockOwner, ownerConnection: widget.ownerConnection,
        openEmployeeDetails: () => Navigator.of(context).push<bool>(MaterialPageRoute(
          builder: (_) => EmployeeEditScreen(
            sharedBottomNavigationBar: widget.sharedBottomNavigationBar,
            businessId: widget.businessId, isOwner: true, employeeId: id,
            rosterName: row['name']?.toString(),
            rosterPosition: (row['position'] ?? row['position_name'])?.toString(),
          ),
        ),),
      ),
    ),);
    if (mounted) await _load();
  }

  Future<void> _openAssignments(Map<String,dynamic> row) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => OwnerPayrollScreen(
      sharedBottomNavigationBar: widget.sharedBottomNavigationBar,
      businessId:widget.businessId, jobId:row['job_id'] as String, invoiceId:row['invoice_id'] as String,
      focusLineId:row['source_line_id'] as String, database:_db, unlockOwner:widget.unlockOwner,
      ownerConnection:widget.ownerConnection,),),);
    if(mounted) await _load();
  }

  Future<void> _reviewCarry(Map<String,dynamic> row) async {
    final ok=await showDialog<bool>(context:context,builder:(dialog)=>AlertDialog(
      title:const Text('Carry unpaid work into payroll?'),
      content:Text('Confirm that you reviewed the historical payments for ${_employeeLabel(row['employee_id'] as String)} and this specific labor is still unpaid.',),
      actions:[TextButton(onPressed:()=>Navigator.pop(dialog),child:const Text('Cancel'),),
        TextButton(onPressed:()=>Navigator.pop(dialog,true),child:const Text('Confirm unpaid'),),],),);
    if(ok==true && mounted) {
      await _runOwnerTaskEdit(()=>_taskEditRepository.reviewUnpaidCarry(row['employee_id'] as String,row['id'] as String,),);
    }
  }

  Future<void> _removeAssignment(Map<String,dynamic> row) async {
    final approved = await showDialog<bool>(context:context,builder:(dialog)=>AlertDialog(
      title:const Text('Remove unpaid assignment?'),
      content:Text('Remove ${_employeeLabel(row['employee_id'] as String)} from this labor line?',),
      actions:[TextButton(onPressed:()=>Navigator.pop(dialog),child:const Text('Cancel'),),
        TextButton(onPressed:()=>Navigator.pop(dialog,true),child:const Text('Remove'),),],),);
    if(approved==true && mounted) {
      await _runOwnerTaskEdit(()=>_taskEditRepository.removeOpenAllocation(row['task_id'] as String,row['employee_id'] as String,),);
    }
  }

  Widget _assignmentCard(Map<String, dynamic> row) {
    final paid = (row['paid_minutes'] as int? ?? 0) > 0 || row['paid'] == 1;
    final archived = row['archived_labor'] == 1;
    final conflict = row['assignment_conflict'] == 1;
    final removed = row['source_active'] == 0;
    final state = row['state']?.toString() ?? 'Open';
    final canProgress = !archived && !paid && !conflict && !removed && !_busy;
    final hours = (row['estimated_minutes'] as int? ?? 0) / 60;
    final actual = row['recorded_actual_minutes'] as int? ?? row['actual_minutes'] as int? ?? 0;
    final credited = row['actual_minutes'] as int? ?? 0;
    return ApprovedTaskCardSurface(
      key: ValueKey('mechanic-work-${row['id']}'),
      borderColor: taskStatusColor(state),
      child: Padding(padding: const EdgeInsets.all(14), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(taskStatusIcon(state), color: taskStatusColor(state)),
            const SizedBox(width: 10),
            Expanded(child: Text(_employeeLabel(row['employee_id']?.toString()),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17))),
            TaskScheduleIndicator(row),
            _compactPlannedHours(hours),
            if (paid) const Icon(Icons.lock_outline, color: BriskersColors.secondaryText),
            if (!paid || archived) IconButton(
              tooltip: 'Edit Assignment',
              onPressed: _busy || conflict || removed ? null : () => _editEstimated(row),
              icon: const Icon(Icons.edit_outlined, color: BriskersColors.confirm)),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center, children: [
            TaskStatusPill(state),
            if (canProgress && state == 'Open') TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: taskBlue),
              onPressed: () => _recordTaskProgress(row),
              icon: const Icon(Icons.play_arrow, size: 18), label: const Text('Start')),
            if (canProgress && (state == 'Open' || state == 'In Progress'))
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: taskBlue, foregroundColor: Colors.white),
                onPressed: () => _recordTaskProgress(row, markDone: true),
                icon: const Icon(Icons.done, size: 18),
                label: Text(state == 'Open' ? 'Mark Done' : 'Finish')),
          ]),
          if (paid) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Paid · Locked')),
          if (archived) ListTile(contentPadding: EdgeInsets.zero,
            title: const Text('Historical labor · excluded from payroll'),
            trailing: paid ? null : TextButton(onPressed: () => _reviewCarry(row),
              child: const Text('Review unpaid work'))),
          if (removed) const Text('Removed from invoice'),
          if (conflict) TextButton(onPressed: _busy ? null : () => _runOwnerTaskEdit(
            () => _taskEditRepository.acceptChangedAssignment(row['id'] as String)),
            child: const Text('Review changed assignment')),
          if (actual > 0 || credited > 0)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(
              'Actual: ${(actual / 60).toStringAsFixed(2)}h · Credited: ${(credited / 60).toStringAsFixed(2)}h',
              style: const TextStyle(color: BriskersColors.secondaryText))),
        ])),
    );
  }

  Widget _assignmentManager() {
    final source = _taskSources.where((r)=>r['job_id']==widget.jobId &&
      r['invoice_id']==widget.invoiceId && r['source_line_id']==widget.focusLineId,).firstOrNull;
    final rows = _work.where((r)=>r['job_id']==widget.jobId && r['invoice_id']==widget.invoiceId &&
      r['source_line_id']==widget.focusLineId,).toList();
    return Scaffold(bottomNavigationBar: widget.sharedBottomNavigationBar,
      backgroundColor: taskCanvas,
      appBar: const ApprovedTasksHeader(title: 'Labor Assignments'),
      body:SafeArea(child:ListView(padding:const EdgeInsets.fromLTRB(16,16,16,32),children:[
        if(_busy || _loadingLocal) const LinearProgressIndicator(),
        if(_error!=null) Text(_error!),
        if(source!=null) Padding(padding: const EdgeInsets.only(bottom: 14),
          child: Text(source['description']?.toString() ?? 'Invoice labor',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: taskNavy))),
        for(final row in rows) ...[
          _assignmentCard(row),
          if (row['owner_prior_paid'] == 1)
            const ListTile(
              dense:true,
              leading:Icon(Icons.verified,color:Color(0xFF078C49)),
              title:Text('Historical wages reconciled · Done'),
              subtitle:Text('Owner-confirmed historical settlement'),
            )
          else if ((row['paid_minutes'] as int? ?? 0)==0 &&
                   row['paid']!=1 && row['assignment_conflict']!=1)
            CheckboxListTile(
              value:false,
              dense:true,
              activeColor: BriskersColors.confirm,
              controlAffinity:ListTileControlAffinity.leading,
              title:const Text('Reconcile previously paid wages'),
              subtitle:const Text('Owner confirmation also marks this labor Done',),
              onChanged:_busy?null:(checked){
                if(checked==true) {unawaited(_confirmHistoricalPaid(row));
                          }
              },
            ),
          if(row['state']=='Open' && (row['paid_minutes'] as int? ?? 0)==0)
            Align(alignment:Alignment.centerRight,child:TextButton(onPressed:_busy?null:()=>_removeAssignment(row),
              style: TextButton.styleFrom(foregroundColor: BriskersColors.destructive),
              child:Text('Remove ${_employeeLabel(row['employee_id'] as String)}',),),),
        ],
        if(source!=null && source['source_active']!=0)
          FilledButton.icon(style: FilledButton.styleFrom(
            backgroundColor: BriskersColors.confirm, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14)),onPressed:_busy?null:()=>_assign(widget.invoiceId!,{
            'id':widget.focusLineId,'description':source['description'],}),
            icon:const Icon(Icons.person_add_alt_1),label:const Text('Add mechanic'),),
        if(!_loadingLocal && source==null) const Text('No saved invoice labor is available for this line.'),
      ],),),);
  }

  Widget _overview() => Scaffold(
    bottomNavigationBar: widget.sharedBottomNavigationBar,
    appBar: AppBar(title: const Text('Payroll')),
    body: Column(children: [
      if(!_canView)const Text('Sign in as Owner to view payroll.'),
      if (_busy || _loadingLocal || _backfillActive) const LinearProgressIndicator(),
      if (_error != null) Text(_error!),
      _recoveryStatus(),
      if(_canView && _loadingLocal && _employees.isEmpty)const Text('Loading saved employees…'),
      if(_canView && _hasLocalData && !_loadingLocal && _employees.isEmpty)const Padding(padding:EdgeInsets.all(12),child:Text('No saved employees are available. Review the offline employee roster.',),),
      if (_canView)
        Expanded(child: !_reportsLoaded ? Center(child:Text(_loadingLocal?'Loading saved payroll totals…':'Saved payroll totals are unavailable. Use Retry above.',),) : PayrollOverview(
          employees: _employees, work: _currentPayrollWork, payments: _overviewPayments,
          onOpenProfile: (id, week) => _openEmployeeProfile(id, week, 0),
          onReviewWeek: (id, week) => _openEmployeeProfile(id, week, 0),
        ),),
    ],),
  );

  @override
  Widget build(BuildContext context) => widget.focusLineId != null ? _assignmentManager() : (widget.globalTasks || (_jobMode && widget.invoiceId == null)) ? _workspace() : widget.reportsOnly ? _reports() : widget.employeeId != null ? _profile() : !_jobMode ? _overview() : Scaffold(
        bottomNavigationBar: widget.sharedBottomNavigationBar,
        appBar: AppBar(title: Text(widget.reportsOnly
            ? 'Payroll reports'
            : _jobMode ? 'Job labor tasks' : 'Owner payroll',),),
        body: ListView(
          // Keep the last action clear of Android gesture/three-button nav.
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
          children: [
            FilledButton(
              onPressed: _loadingLocal ? null : () => unawaited(_load()),
              child: const Text('Refresh'),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null) Text(_error!),
            if (_grant != null && !widget.reportsOnly) ...[
              TextButton(onPressed: _busy || _employees.isEmpty ? null : () => _managePeer(pair: true),
                child: const Text('Pair employee device'),),
              TextButton(onPressed: _busy || _employees.isEmpty ? null : () => _managePeer(pair: false),
                child: const Text('Sync payroll over shop Wi-Fi'),),
            ],
            if (_canView && _jobMode) ...[
              const ListTile(title: Text('Invoice labor')),
              for (final invoice in <String, List<Map<String, dynamic>>>{
                if (widget.invoiceId != null) widget.invoiceId!: widget.invoiceLines,
                ...widget.jobInvoiceLabor,
              }.entries)
                for (final line in invoice.value.where(isInvoiceLaborLine))
                  if (line['id'] is String)
                    ListTile(
                      title: Text((line['description'] ?? line['name'] ?? 'Invoice labor').toString(),),
                      trailing: TextButton(
                        onPressed: _busy || _employees.isEmpty
                            ? null : () => _assign(invoice.key, line),
                        child: const Text('Assign'),
                      ),
                    ),
              for(final source in _taskSources.where((r)=>r['job_id']==widget.jobId &&
                  r['invoice_id']!=null && (widget.focusLineId==null || r['source_line_id']==widget.focusLineId),))
                ListTile(title:Text(source['description'].toString()),
                  subtitle:const Text('Invoice labor · mechanic allocations',),
                  trailing:TextButton(onPressed:()=>_assign(source['invoice_id'] as String,
                    {'id':source['source_line_id'],'description':source['description'],}),child:const Text('Add mechanic'),),),
              if (_employees.isEmpty) const Text('No active assignment is saved for this job.'),
              ListTile(
                title: const Text('Additional job work / Rechecks'),
                trailing: TextButton.icon(
                  onPressed: _busy || _employees.isEmpty ? null : _addRecheck,
                  icon: const Icon(Icons.add), label: const Text('Add Recheck'),
                ),
              ),
              for (final row in _work.where((r)=>widget.focusLineId==null || r['source_line_id']==widget.focusLineId,)) _taskCard(row),
            ],
            if (_canView && !_jobMode) ...[
              if (_employees.isEmpty) const Text('No employee work has been recorded yet.'),
              if (_employees.isNotEmpty)
                DropdownButton<String>(
                  value: _employee,
                  items: [
                    for (final employee in _employees)
                      DropdownMenuItem(value: employee['id'] as String, child: Text(_employeeLabel(employee['id'] as String)),),
                  ],
                  onChanged: _busy ? null : (value) {
                    setState(() {
                      _employee = value;
                      _work = [];
                      _history = [];
                      _verifiedWeeks = null;
                                });
                    if (_canView) unawaited(_load());
                  },
                ),
              if (_employee != null)
                FilledButton.icon(
                  onPressed: _busy ? null : () {
                    final employee = _employee!;
                    Navigator.of(context).push<bool>(MaterialPageRoute(
                      builder: (_) => WeeklyLaborReview(
                        sharedBottomNavigationBar: widget.sharedBottomNavigationBar,
                        employeeId: employee,
                        employeeName: _employees.where((row) => row['id'] == employee)
                            .firstOrNull?['name']?.toString() ?? 'Weekly payroll',
                        tasks: _work,
                        week: DateTime.now(),
                        advanceBalance: () => _viewRepository.advance(employee),
                        recordPayment: _recordWeekly,
                      ),
                    ),);
                  },
                  icon: const Icon(Icons.assignment_outlined),
                  label: const Text('Review Weekly Labor'),
                ),
            ],
          ],
        ),
      );
}

/// Retain the original fixed-footer panels at normal phone sizes. A short
/// viewport (keyboard, error message, split-screen) can still reach every control.
class _PayrollViewport extends StatelessWidget {
  const _PayrollViewport({required this.minHeight,required this.child});
  final double minHeight;
  final Widget child;
  @override Widget build(BuildContext context)=>LayoutBuilder(builder:(context,size)=>
    SingleChildScrollView(primary:false,child:SizedBox(height:size.maxHeight<minHeight?minHeight:size.maxHeight,child:child,),),);
}
