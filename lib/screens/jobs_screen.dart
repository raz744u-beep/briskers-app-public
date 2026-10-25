import 'dart:async';

import 'package:flutter/material.dart' hide showDialog, showModalBottomSheet;
import '../services/owner_invoice_auto_close_service.dart';

import '../core/briskers_colors.dart';
import '../core/briskers_i18n.dart';
import '../core/connection_mode.dart';
import '../core/job_status_style.dart';
import '../core/job_list_options.dart';
import '../core/module_modal_theme.dart';
import '../services/briskers_api.dart';
import '../services/job_sync_service.dart';
import '../services/owner_job_retirement_service.dart';
import '../services/job_summary_visibility.dart';
import '../services/document_index_sync_service.dart';
import '../services/local_document_repository.dart';
import '../services/local_job_repository.dart';
import '../services/local_job_access_history.dart';
import '../services/local_customer_repository.dart';
import '../services/offline_job_admin_service.dart';
import '../widgets/job_compact_card.dart';
import 'jobs/job_detail_screen.dart';
import 'jobs/job_create_screen.dart';
import 'jobs/job_customer_picker_screen.dart';
import 'jobs/job_document_screen.dart';
import 'jobs/invoice_payment_navigation.dart';

class JobsScreen extends StatefulWidget {
  const JobsScreen({
    super.key,
    required this.businessId,
    required this.roleCode,
    this.refreshToken = 0,
    this.defaultToOpen = false,
    this.onJobsChanged,
    this.jobDetailBottomNavigationBar,
    this.repository,
    this.documentRepository,
    this.userId,
    this.visibilityFactory,
  });

  final String businessId;
  final String roleCode;
  final int refreshToken;
  final bool defaultToOpen;
  final VoidCallback? onJobsChanged;
  final Widget? jobDetailBottomNavigationBar;
  final LocalJobRepository? repository;
  final LocalDocumentRepository? documentRepository;
  final String? userId;
  final JobSummaryVisibility Function(
    String businessId,
    ValueChanged<Set<String>> onQuarantine,
  )?
  visibilityFactory;

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen>
    with ModuleModalState<JobsScreen> {
  @override
  Color get modalAccent => BriskersColors.jobs;

  static const _api = BriskersApi();
  late final LocalJobRepository _localJobs =
      widget.repository ?? LocalJobRepository();
  final JobSyncService _jobSync = JobSyncService();
  final DocumentIndexSyncService _documentSync = DocumentIndexSyncService();
  late final LocalDocumentRepository _localDocuments =
      widget.documentRepository ?? LocalDocumentRepository();
  final OfflineJobAdminService _offlineJobAdmin = OfflineJobAdminService();

  List<Map<String, dynamic>>? _rows;
  List<Map<String, dynamic>> _statuses = const [];
  String? _selectedStatus;
  JobListView get _listView => _selectedStatus == '__open__'
      ? JobListView.active : JobListView.all;
  String? get _queryStatus => _selectedStatus == '__open__'
      ? null : _selectedStatus;
  static const _pageSize = 30;
  int _visibleLimit = _pageSize;
  bool _restoredView = false;
  bool _loadingMore = false;
  bool _showingJobActions = false;
  String? get _userId => widget.userId ?? LocalJobAccessHistory.currentUserId;
  String get _storageId =>
      'jobs-view:${widget.businessId}:${_userId ?? "signed-out"}';
  String _text(String en, String es) =>
      BriskersLanguageController.instance.isSpanish ? es : en;

  void _rememberView() {
    PageStorage.maybeOf(context)?.writeState(
      context,
      JobListPreferences(
        status: _selectedStatus,
        search: _search.text,
        visibleLimit: _visibleLimit,
      ),
      identifier: _storageId,
    );
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() {
      _loadingMore = true;
      _visibleLimit += _pageSize;
    });
    _rememberView();
    // Re-read an expanded prefix instead of appending OFFSET pages: if a sync
    // changed ordering, a row cannot be duplicated or silently skipped.
    await _load(refreshRemote: false);
    if (mounted) setState(() => _loadingMore = false);
  }

  final TextEditingController _search = TextEditingController();
  Timer? _searchDebounce;
  StreamSubscription<String>? _retirementChanges;
  late JobSummaryVisibility _jobVisibility;
  int _totalCount = 0;
  Map<String, int> _statusCounts = const {};
  List<Map<String, dynamic>> _documentMatches = const [];
  String? _error;
  String? _busyJobId;
  bool _onlineReady = false;
  bool _showingLocal = false;
  bool _refreshFailed = false;

  bool get _canManage =>
      widget.roleCode == 'owner' ||
      widget.roleCode == 'manager' ||
      widget.roleCode == 'office';

  @override
  void initState() {
    super.initState();
    _listenForQuarantine();
    _retirementChanges = OwnerJobRetirementService.statusEvents.listen((
      businessId,
    ) {
      if (businessId == widget.businessId && mounted) {
        unawaited(_load(refreshRemote: false));
      }
    });
  }

  void _listenForQuarantine() {
    void onQuarantine(Set<String> jobIds) {
      if (!mounted) return;
      setState(() {
        if (_rows != null) {
          _rows = JobSummaryVisibility.withoutJobs(_rows!, jobIds);
        }
        _documentMatches = _withoutJobLabels(_documentMatches, jobIds);
        _totalCount = _rows?.length ?? 0;
        _statusCounts = const {};
        if (jobIds.contains(_busyJobId)) _busyJobId = null;
        _onlineReady = false;
        _showingLocal = _rows != null;
      });
      unawaited(_refreshQuarantineCounts());
    }

    _jobVisibility =
        widget.visibilityFactory?.call(widget.businessId, onQuarantine) ??
        JobSummaryVisibility(
          businessId: widget.businessId,
          onQuarantine: onQuarantine,
        );
  }

  // A document may remain independently readable after its Job is revoked.
  List<Map<String, dynamic>> _withoutJobLabels(
    List<Map<String, dynamic>> rows,
    Set<String> jobIds,
  ) => rows
      .map(
        (row) => jobIds.contains(row['job_id']?.toString())
            ? <String, dynamic>{...row, 'job_number': null, 'job_title': null}
            : row,
      )
      .toList();

  Future<void> _refreshQuarantineCounts() async {
    final visibility = _jobVisibility;
    final generation = visibility.epoch;
    try {
      final counts = await Future.wait<dynamic>([
        _localJobs.jobCount(
          widget.businessId,
          status: _queryStatus,
          search: _search.text.trim(),
          view: _listView,
        ),
        _localJobs.jobStatusCounts(widget.businessId, view: JobListView.all),
      ]);
      if (!mounted || !visibility.isCurrent(generation)) return;
      setState(() {
        _totalCount = counts[0] as int;
        _statusCounts = Map<String, int>.from(counts[1] as Map);
      });
    } catch (_) {
      // Keep already-pruned cards if the durable local counts cannot be read.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _restoreView();
  }

  void _restoreView() {
    if (_restoredView) return;
    _restoredView = true;
    final saved = PageStorage.maybeOf(context)
        ?.readState(context, identifier: _storageId);
    if (widget.defaultToOpen) {
      _selectedStatus = '__open__';
    } else if (saved is JobListPreferences) {
      _selectedStatus = saved.status;
      _search.text = saved.search;
      _visibleLimit = saved.visibleLimit;
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    _jobVisibility.dispose();
    _retirementChanges?.cancel();
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant JobsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId ||
        oldWidget.userId != widget.userId) {
      _jobVisibility.dispose();
      _searchDebounce?.cancel();
      _search.clear();
      _rows = null;
      _documentMatches = const [];
      _statuses = const [];
      _statusCounts = const {};
      _totalCount = 0;
      _busyJobId = null;
      _onlineReady = false;
      _showingLocal = false;
      _loadingMore = false;
      _selectedStatus = null;
      _visibleLimit = _pageSize;
      _restoredView = false;
      _listenForQuarantine();
      _restoreView();
    } else if (oldWidget.refreshToken != widget.refreshToken) {
      if (widget.defaultToOpen) {
        _selectedStatus = '__open__';
        _search.clear();
        _visibleLimit = _pageSize;
        _rememberView();
      }
      _load(refreshRemote: false);
    }
  }

  Future<void> _createNewJob() async {
    if (!_canManage) return;
    final selected = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => JobCustomerPickerScreen(businessId: widget.businessId),
      ),
    );
    if (selected == null || !mounted) return;
    try {
      final id = selected['id']?.toString() ?? '';
      if (id.isEmpty) return;
      final localDetail = await LocalCustomerRepository().customerDetail(
        widget.businessId,
        id,
      );
      final detail =
          localDetail ?? await _api.customerDetail(widget.businessId, id);
      if (!mounted) return;
      final created = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => JobCreateScreen(
            businessId: widget.businessId,
            customerId: id,
            customerName: selected['display_name']?.toString() ?? 'Customer',
            roleCode: widget.roleCode,
            vehicles: List<dynamic>.from(detail['vehicles'] ?? const []),
            bottomNavigationBar: widget.jobDetailBottomNavigationBar,
          ),
        ),
      );
      if (created == true && mounted) {
        await _load();
        widget.onJobsChanged?.call();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to prepare new job: $error')),
        );
      }
    }
  }

  Future<void> _load({bool refreshRemote = true}) async {
    final visibility = _jobVisibility;
    final generation = visibility.beginLoad();
    final businessId = widget.businessId;
    final query = _search.text.trim();
    final status = _queryStatus;
    final view = _listView;
    final limit = _visibleLimit;
    final userId = _userId;
    var localAvailable = false;
    final mode = BriskersConnectionModeController.instance;

    Future<void> readSavedJobs({required bool online}) async {
      // Start secondary counters/search lookups concurrently, but do not
      // block the first usable Jobs list frame on all five SQLite reads.
      final metadata = Future.wait<dynamic>([
        _localJobs.jobStatuses(businessId),
        _localJobs.jobCount(
          businessId, status: status, search: query, view: view,
        ),
        _localJobs.jobStatusCounts(businessId, view: JobListView.all),
        query.isEmpty
            ? Future.value(<Map<String, dynamic>>[])
            : _localDocuments.search(businessId, query, limit: 30),
      ]).then<void>((results) async {
        if (!mounted || !visibility.isCurrent(generation)) return;
        final blocked = await visibility.blockedJobIds();
        if (!mounted || !visibility.isCurrent(generation)) return;
        setState(() {
          _statuses = List<Map<String, dynamic>>.from(results[0] as List);
          _totalCount = results[1] as int;
          _statusCounts = Map<String, int>.from(results[2] as Map);
          _documentMatches = _withoutJobLabels(
            List<Map<String, dynamic>>.from(results[3] as List), blocked,
          );
        });
      }).catchError((Object _) {
        // A stale/failed count may not hide already-rendered job cards.
      });
      unawaited(metadata);
      final rows = await _localJobs.listJobs(
        businessId,
        status: status,
        search: query,
        view: view,
        sort: JobListSort.lastModified,
        userId: userId,
        limit: limit,
      );
      if (!mounted || !visibility.isCurrent(generation)) return;
      final visibleRows = await visibility.filter(rows);
      if (!mounted || !visibility.isCurrent(generation)) return;
      localAvailable = true;
      setState(() {
        _rows = visibleRows;
        _showingLocal = !online;
        _onlineReady = online;
        if (online) _refreshFailed = false;
        _error = null;
      });
    }

    if (!mode.forceOnline || !refreshRemote) {
      try {
        await readSavedJobs(online: !refreshRemote && _onlineReady);
      } catch (error) {
        if (mounted && visibility.isCurrent(generation)) {
          // A failed local read must not erase job cards already painted from
          // the device. The next entry can retry SQLite without data loss.
          setState(() {
            _rows ??= const [];
            _showingLocal = _rows!.isNotEmpty;
            _error = _rows!.isEmpty ? error.toString() : null;
          });
        }
      }
    }
    if (!mounted || !visibility.isCurrent(generation)) return;
    if (mode.forceOffline || !refreshRemote) return;

    try {
      final onlineStatuses = await _api.jobStatuses(businessId);
      if (!mounted || !visibility.isCurrent(generation)) return;
      await _localJobs.replaceJobStatuses(businessId, onlineStatuses);
      if (_canManage) {
        try {
          await _offlineJobAdmin.flush(businessId);
        } catch (_) {
          // Queued edits remain local and retry when connectivity returns.
        }
        try {
          await _offlineJobAdmin.refreshEmployees(businessId);
        } catch (_) {
          // Keep the last employee choices for offline assignment.
        }
      }
      if (!mounted || !visibility.isCurrent(generation)) return;
      // Incremental sync populates the same SQLite query in every mode.
      await _jobSync.pull(businessId);
      unawaited(_documentSync.refreshBestEffort(businessId));
      if (!mounted || !visibility.isCurrent(generation)) return;
      await readSavedJobs(online: true);
    } catch (error) {
      if (!mounted || !visibility.isCurrent(generation)) return;
      setState(() {
        _onlineReady = false;
        _refreshFailed = true;
        _showingLocal = localAvailable && !mode.forceOnline;
        if (_showingLocal || (_rows?.isNotEmpty ?? false)) {
          // Never remove an existing local list because an online request
          // failed or its DNS lookup timed out.
          _showingLocal = true;
          _error = null;
        } else {
          _rows ??= const [];
          _error = error.toString();
        }
      });
    }
  }

  void _searchChanged() {
    _searchDebounce?.cancel();
    _visibleLimit = _pageSize;
    _rememberView();
    _jobVisibility.beginLoad();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _load(refreshRemote: false);
    });
  }

  Future<void> _openDocument(Map<String, dynamic> document) async {
    final id = document['id']?.toString() ?? '';
    if (id.isEmpty) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JobDocumentScreen(
          businessId: widget.businessId,
          documentId: id,
          roleCode: widget.roleCode,
          isOwner: widget.roleCode == 'owner',
          canManageExpenses: <String>{
            'owner',
            'manager',
            'office',
          }.contains(widget.roleCode),
        ),
      ),
    );
    if (mounted) unawaited(_load());
    widget.onJobsChanged?.call();
  }

  Future<void> _openJob(
    Map<String, dynamic> job, {
    String? initialAction,
  }) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JobDetailScreen(
          businessId: widget.businessId,
          jobId: job['id'].toString(),
          roleCode: widget.roleCode,
          initialAction: initialAction,
          bottomNavigationBar: widget.jobDetailBottomNavigationBar,
        ),
      ),
    );
    if (mounted) unawaited(_load());
    widget.onJobsChanged?.call();
  }

  Future<void> _quickEditMechanic(Map<String, dynamic> job) async {
    if (!_canManage || _busyJobId != null) return;

    setState(() => _busyJobId = job['id']?.toString());
    try {
      List<Map<String, dynamic>> employees;
      if (_onlineReady) {
        try {
          employees = await _offlineJobAdmin.refreshEmployees(
            widget.businessId,
          );
        } catch (_) {
          employees = await _offlineJobAdmin.cachedEmployees(widget.businessId);
        }
      } else {
        employees = await _offlineJobAdmin.cachedEmployees(widget.businessId);
      }

      if (!mounted) return;
      if (employees.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No employee list is saved on this device yet. Open Jobs once while online, then mechanic changes will work offline.',
            ),
          ),
        );
        return;
      }

      final currentId = job['assigned_employee_id']?.toString();
      final selected = await showModalBottomSheet<String?>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text(
                  'Assign mechanic / employee',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.person_off_outlined),
                title: const Text('Unassigned'),
                trailing: currentId == null || currentId.isEmpty
                    ? const Icon(Icons.check, color: BriskersColors.jobs)
                    : null,
                onTap: () => Navigator.pop(sheetContext, ''),
              ),
              const Divider(),
              ...employees.map((employee) {
                final id = employee['id']?.toString() ?? '';
                return ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(employee['name']?.toString() ?? ''),
                  subtitle: Text(
                    employee['position_name']?.toString() ?? 'Employee',
                  ),
                  trailing: id == currentId
                      ? const Icon(Icons.check, color: BriskersColors.jobs)
                      : null,
                  onTap: () => Navigator.pop(sheetContext, id),
                );
              }),
            ],
          ),
        ),
      );

      if (selected == null) return;

      Map<String, dynamic>? selectedEmployee;
      if (selected.isNotEmpty) {
        for (final employee in employees) {
          if (employee['id']?.toString() == selected) {
            selectedEmployee = employee;
            break;
          }
        }
      }

      await _offlineJobAdmin.queueAssignment(
        widget.businessId,
        job['id'].toString(),
        employeeId: selected.isEmpty ? null : selected,
        employeeName: selectedEmployee?['name']?.toString(),
        position: selectedEmployee?['position_name']?.toString(),
      );

      if (!BriskersConnectionModeController.instance.forceOffline) {
        try {
          await _offlineJobAdmin.flush(widget.businessId);
        } catch (_) {
          // The local change remains queued for the next successful sync.
        }
      }

      await _load();
      widget.onJobsChanged?.call();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busyJobId = null);
    }
  }

  Future<void> _quickEditPlannedTime(Map<String, dynamic> job) async {
    if (!_canManage || _busyJobId != null) return;

    final controller = TextEditingController(
      text: job['planned_hours']?.toString() ?? '0',
    );
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
    var clearedForEntry = false;

    final value = await showDialog<num?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Planned time'),
        content: TextField(
          controller: controller,
          autofocus: true,
          onTap: () {
            if (!clearedForEntry) {
              if (controller.text.trim() == '0') {
                controller.clear();
              } else {
                controller.selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: controller.text.length,
                );
              }
              clearedForEntry = true;
            }
          },
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Hours',
            suffixText: 'hr',
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: BriskersColors.jobs,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              final parsed = num.tryParse(
                controller.text.trim().isEmpty ? '0' : controller.text.trim(),
              );
              Navigator.pop(dialogContext, parsed);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (value == null || value < 0) return;

    setState(() => _busyJobId = job['id']?.toString());
    try {
      await _offlineJobAdmin.queuePlannedHours(
        widget.businessId,
        job['id'].toString(),
        value,
      );
      if (!BriskersConnectionModeController.instance.forceOffline) {
        try {
          await _offlineJobAdmin.flush(widget.businessId);
        } catch (_) {
          // The local change remains queued for the next successful sync.
        }
      }
      await _load();
      widget.onJobsChanged?.call();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busyJobId = null);
    }
  }

  Future<void> _changeStatus(
    Map<String, dynamic> job,
    String statusCode,
  ) async {
    if (!_canManage || statusCode == job['status']?.toString()) {
      return;
    }

    Map<String, dynamic>? selectedStatus;
    for (final status in _statuses) {
      if (status['code']?.toString() == statusCode) {
        selectedStatus = status;
        break;
      }
    }
    if (selectedStatus == null) return;

    setState(() => _busyJobId = job['id']?.toString());
    try {
      await _offlineJobAdmin.queueStatus(
        widget.businessId,
        job['id'].toString(),
        code: statusCode,
        name: selectedStatus['name']?.toString() ?? statusCode,
        colorHex: selectedStatus['color_hex']?.toString(),
        iconKey: selectedStatus['icon_key']?.toString(),
      );

      if (!BriskersConnectionModeController.instance.forceOffline) {
        try {
          await _offlineJobAdmin.flush(widget.businessId);
        } catch (_) {
          // The status change remains queued for the next successful sync.
        }
      }

      if (statusCode == 'completed' && widget.roleCode == 'owner' &&
          !BriskersConnectionModeController.instance.forceOffline) {
        try {
          await OwnerInvoiceAutoCloseService().closeEligible(
            businessId: widget.businessId,
            jobId: job['id'].toString(),
            isOwner: true,
          );
        } catch (_) {
          // A failed close does not undo job completion or payment history.
          // The owner may review the invoice later.
        }
      }
      await _load();
      widget.onJobsChanged?.call();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busyJobId = null);
    }
  }

  List<Map<String, dynamic>> get _visibleRows =>
      _rows ?? const <Map<String, dynamic>>[];

  Iterable<Widget> _jobCards(List<Map<String, dynamic>> rows) =>
      rows.map(_jobCard);

  int _statusCount(String code) => _statusCounts[code] ?? 0;

  Widget _menuCount(int count, {bool alwaysShow = false}) {
    if (count <= 0 && !alwaysShow) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 14),
      child: Text(
        '$count',
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: Color(0xFF405064),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _availableStatusesFor(Map<String, dynamic> job) =>
      _statuses;

  Widget _statusControl(Map<String, dynamic> job) {
    final color = colorFromHex(job['status_color']?.toString());
    final label = jobStatusLabel(
      job['status']?.toString(),
      job['status_name']?.toString() ?? 'Status',
    );
    final busy = _busyJobId == job['id']?.toString();

    final child = Container(
      constraints: const BoxConstraints(maxWidth: 155),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.65)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
            )
          else
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: color,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          if (_canManage && !busy) ...[
            const SizedBox(width: 3),
            Icon(Icons.chevron_right, size: 15, color: color),
          ],
        ],
      ),
    );

    if (!_canManage || busy) return child;

    return PopupMenuButton<String>(
      tooltip: tr('changeStatus'),
      padding: EdgeInsets.zero,
      onSelected: (value) => _changeStatus(job, value),
      itemBuilder: (context) => _availableStatusesFor(job).map((status) {
        final itemColor = colorFromHex(status['color_hex']?.toString());
        return PopupMenuItem<String>(
          value: status['code']?.toString(),
          child: Row(
            children: [
              Icon(
                jobStatusIcon(status['icon_key']?.toString()),
                color: itemColor,
              ),
              const SizedBox(width: 10),
              Text(
                jobStatusLabel(
                  status['code']?.toString(),
                  status['name']?.toString() ?? '',
                ),
              ),
            ],
          ),
        );
      }).toList(),
      child: child,
    );
  }

  Future<void> _showJobActions(Map<String, dynamic> job) async {
    if (_showingJobActions) return;
    _showingJobActions = true;
    try {
      final owner = widget.roleCode == 'owner';
      var selected = false;
      void choose(BuildContext sheetContext, String action) {
        if (selected) return;
        selected = true;
        Navigator.pop(sheetContext, action);
      }

      final action = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const _ActionSectionLabel('Job'),
              ListTile(
                leading: const Icon(Icons.folder_open_outlined),
                title: const Text('Open Job'),
                onTap: () => choose(sheetContext, 'open'),
              ),
              if (_canManage)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit Job'),
                  onTap: () => choose(sheetContext, 'edit'),
                ),
              if (_canManage) ...[
                const Divider(height: 1),
                const _ActionSectionLabel('Repair and documents'),
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined),
                  title: const Text('Add Pre-inspection'),
                  onTap: () => choose(sheetContext, 'inspection'),
                ),
                ListTile(
                  leading: const Icon(Icons.notes_outlined),
                  title: const Text('Add Customer Complaint'),
                  onTap: () => choose(sheetContext, 'complaint'),
                ),
                ListTile(
                  leading: const Icon(Icons.add_circle_outline),
                  title: const Text('Add Finding'),
                  onTap: () => choose(sheetContext, 'finding'),
                ),
                ListTile(
                  leading: const Icon(Icons.request_quote_outlined, color: Colors.deepPurple),
                  title: const Text('Add Estimate'),
                  onTap: () => choose(sheetContext, 'estimate'),
                ),
                ListTile(
                  leading: const Icon(Icons.receipt_long_outlined, color: BriskersColors.invoices),
                  title: const Text('Add Invoice'),
                  onTap: () => choose(sheetContext, 'invoice'),
                ),
                const Divider(height: 1),
                const _ActionSectionLabel('Payment and expenses'),
                ListTile(
                  leading: const Icon(Icons.payments_outlined, color: Colors.green),
                  title: const Text('Add Payment'),
                  onTap: () => choose(sheetContext, 'payment'),
                ),
                ListTile(
                  leading: const Icon(Icons.add_card_outlined,
                      color: BriskersColors.expenses),
                  title: const Text('Add Expense'),
                  onTap: () => choose(sheetContext, 'expense'),
                ),
              ],
              if (owner) ...[
                const Divider(height: 1),
                const _ActionSectionLabel('Delete'),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text(
                    'Delete Job',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () => choose(sheetContext, 'delete'),
                ),
              ],
            ],
          ),
        ),
      );
      if (!mounted || action == null) return;
      if (action == 'payment') {
        final opened = await openJobInvoicePayment(
          context,
          businessId: widget.businessId,
          jobId: job['id'].toString(),
          roleCode: widget.roleCode,
        );
        if (opened && mounted) {
          unawaited(_load());
          widget.onJobsChanged?.call();
        }
        return;
      }
      await _openJob(job, initialAction: action == 'open' ? null : action);
    } finally {
      _showingJobActions = false;
    }
  }

  Widget _jobCard(Map<String, dynamic> job) => JobCompactCard(
    job: job,
    statusControl: _statusControl(job),
    onOpen: () => _openJob(job),
    onLongPress: () => _showJobActions(job),
    onEditMechanic: _canManage ? () => _quickEditMechanic(job) : null,
    onEditPlannedTime: _canManage ? () => _quickEditPlannedTime(job) : null,
    canOpen: _busyJobId != job['id']?.toString(),
  );

  @override
  Widget build(BuildContext context) {
    final visible = _visibleRows;

    return Column(
      children: [
        Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Text(
                      tr('jobs'),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: BriskersColors.jobs,
                          ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      fit: FlexFit.loose,
                      child: PopupMenuButton<String>(
                        tooltip: tr('filterJobs'),
                        onSelected: (value) {
                          setState(() {
                            _selectedStatus = value == '__all__' ? null : value;
                            _visibleLimit = _pageSize;
                          });
                          _rememberView();
                          _load(refreshRemote: false);
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem<String>(
                            value: '__open__',
                            child: Row(children: [
                              const Icon(Icons.work_outline),
                              const SizedBox(width: 10),
                              Expanded(child: Text(_text('Open jobs', 'Trabajos abiertos'))),
                              _menuCount(_statusCounts.entries
                                  .where((e) => !const {'completed','cancelled','closed'}.contains(e.key))
                                  .fold<int>(0, (a, e) => a + e.value), alwaysShow: true),
                            ]),
                          ),
                          PopupMenuItem<String>(
                            value: 'paid_still_open',
                            child: Row(
                              children: [
                                const Icon(Icons.payments_outlined),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _text(
                                      'Paid, Still Open',
                                      'Pagado, aún abierto',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: '__all__',
                            child: Row(
                              children: [
                                const Icon(Icons.all_inclusive),
                                const SizedBox(width: 10),
                                Expanded(child: Text(tr('all'))),
                                _menuCount(
                                  _statusCounts.values.fold<int>(
                                    0,
                                    (a, b) => a + b,
                                  ),
                                  alwaysShow: true,
                                ),
                              ],
                            ),
                          ),
                          ..._statuses.map((status) {
                            final color = colorFromHex(
                              status['color_hex']?.toString(),
                            );
                            final code = status['code']?.toString() ?? '';
                            final count = _statusCount(code);
                            return PopupMenuItem<String>(
                              value: code,
                              child: Row(
                                children: [
                                  Icon(
                                    jobStatusIcon(
                                      status['icon_key']?.toString(),
                                    ),
                                    color: color,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      jobStatusLabel(
                                        status['code']?.toString(),
                                        status['name']?.toString() ?? '',
                                      ),
                                    ),
                                  ),
                                  _menuCount(count),
                                ],
                              ),
                            );
                          }),
                        ],
                        child: Builder(
                          builder: (context) {
                            Map<String, dynamic>? selected;
                            if (_selectedStatus != null) {
                              for (final status in _statuses) {
                                if (status['code']?.toString() ==
                                    _selectedStatus) {
                                  selected = status;
                                  break;
                                }
                              }
                            }
                            final color = selected == null
                                ? BriskersColors.jobs
                                : colorFromHex(
                                    selected['color_hex']?.toString(),
                                  );
                            final label = _selectedStatus == '__open__'
                                ? _text('Open', 'Abiertos')
                                : _selectedStatus == 'paid_still_open'
                                ? _text(
                                    'Paid, Still Open',
                                    'Pagado, aún abierto',
                                  )
                                : selected == null
                                ? _text('All statuses', 'Todos los estados')
                                : jobStatusLabel(
                                    selected['code']?.toString(),
                                    selected['name']?.toString() ?? '',
                                  );

                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: color.withValues(alpha: 0.45),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: color,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  Icon(
                                    Icons.chevron_right,
                                    size: 18,
                                    color: color,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_rows != null)
                      Text(
                        '${tr('total')} $_totalCount',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: BriskersColors.jobs,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SearchBar(
                        controller: _search,
                        hintText: _text(
                          'Search job, customer, vehicle or invoice #',
                          'Buscar trabajo, cliente, vehículo o factura',
                        ),
                        leading: const Icon(Icons.search),
                        trailing: [
                          if (_search.text.isNotEmpty)
                            IconButton(
                              tooltip: _text('Clear', 'Borrar'),
                              onPressed: () {
                                _searchDebounce?.cancel();
                                _search.clear();
                                setState(() {
                                  _visibleLimit = _pageSize;
                                });
                                _rememberView();
                                _load(refreshRemote: false);
                              },
                              icon: const Icon(Icons.close),
                            ),
                        ],
                        onChanged: (_) {
                          setState(() {});
                          _searchChanged();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_canManage)
                      IconButton.filled(
                        tooltip: 'New Job',
                        style: IconButton.styleFrom(
                          backgroundColor: BriskersColors.jobs,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _createNewJob,
                        icon: const Icon(Icons.add),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(),
            child: ListView(
              key: PageStorageKey('jobs-list:$_storageId'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 80),
              children: [
                if (_showingLocal &&
                    (BriskersConnectionModeController.instance.forceOffline ||
                     _refreshFailed))
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: BriskersColors.jobs.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.cloud_off_outlined, size: 18),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            _text(
                              _refreshFailed
                                  ? 'Showing saved jobs · refresh needs attention'
                                  : 'Offline · showing saved jobs',
                              _refreshFailed
                                  ? 'Trabajos guardados · revisar actualización'
                                  : 'Sin conexión · mostrando trabajos guardados',
                            ),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                if (_search.text.trim().isNotEmpty &&
                    _documentMatches.isNotEmpty) ...[
                  Text(
                    'Invoices & estimates',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: BriskersColors.invoices,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ..._documentMatches.map(
                    (document) => Card(
                      child: ListTile(
                        onTap: () => _openDocument(document),
                        leading: Icon(
                          document['kind'] == 'estimate'
                              ? Icons.request_quote_outlined
                              : Icons.receipt_long_outlined,
                          color: BriskersColors.invoices,
                        ),
                        title: Text(
                          '${document['kind'] == 'estimate' ? 'Estimate' : 'Invoice'} #${document['document_number'] ?? ''}',
                        ),
                        subtitle: Text(
                          [
                                document['customer_name'],
                                if ((document['job_number']?.toString() ?? '')
                                    .isNotEmpty)
                                  'Job #${document['job_number']}',
                                document['vehicle'],
                              ]
                              .where(
                                (value) =>
                                    value != null &&
                                    value.toString().isNotEmpty,
                              )
                              .join(' • '),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (_rows == null)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (visible.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text(
                        _text(
                          'No jobs match this view and filters.',
                          'No hay trabajos para esta vista y filtros.',
                        ),
                      ),
                    ),
                  )
                else
                  ..._jobCards(visible),
                if (_rows != null && _rows!.length < _totalCount)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: OutlinedButton(
                      key: const ValueKey('load-more-jobs'),
                      onPressed: _loadingMore ? null : _loadMore,
                      child: Text(
                        _loadingMore
                            ? _text('Loading…', 'Cargando…')
                            : _text(
                                'Load more (${_rows!.length} of $_totalCount)',
                                'Cargar más (${_rows!.length} de $_totalCount)',
                              ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionSectionLabel extends StatelessWidget {
  const _ActionSectionLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
    child: Align(alignment: Alignment.centerLeft,
      child: Text(label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.8, fontWeight: FontWeight.w700))),
  );
}
