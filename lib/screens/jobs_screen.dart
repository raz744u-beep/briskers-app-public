import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../core/briskers_colors.dart';
import '../core/briskers_i18n.dart';
import '../core/connection_mode.dart';
import '../core/job_status_style.dart';
import '../services/briskers_api.dart';
import '../services/job_sync_service.dart';
import '../services/job_summary_visibility.dart';
import '../services/document_index_sync_service.dart';
import '../services/local_document_repository.dart';
import '../services/local_job_repository.dart';
import '../services/local_customer_repository.dart';
import '../services/offline_job_admin_service.dart';
import '../widgets/job_compact_card.dart';
import 'jobs/job_detail_screen.dart';
import 'jobs/job_create_screen.dart';
import 'jobs/job_customer_picker_screen.dart';
import 'jobs/job_document_screen.dart';

class JobsScreen extends StatefulWidget {
  const JobsScreen({
    super.key,
    required this.businessId,
    required this.roleCode,
    this.refreshToken = 0,
    this.onJobsChanged,
    this.jobDetailBottomNavigationBar,
  });

  final String businessId;
  final String roleCode;
  final int refreshToken;
  final VoidCallback? onJobsChanged;
  final Widget? jobDetailBottomNavigationBar;

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  static const _api = BriskersApi();
  final LocalJobRepository _localJobs = LocalJobRepository();
  final JobSyncService _jobSync = JobSyncService();
  final DocumentIndexSyncService _documentSync = DocumentIndexSyncService();
  final LocalDocumentRepository _localDocuments = LocalDocumentRepository();
  final OfflineJobAdminService _offlineJobAdmin = OfflineJobAdminService();

  List<Map<String, dynamic>>? _rows;
  List<Map<String, dynamic>> _statuses = const [];
  String? _selectedStatus;
  String _sort = 'newest';
  final TextEditingController _search = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;
  late JobSummaryVisibility _jobVisibility;
  int _totalCount = 0;
  Map<String, int> _statusCounts = const {};
  List<Map<String, dynamic>> _documentMatches = const [];
  String? _error;
  String? _busyJobId;
  bool _onlineReady = false;
  bool _showingLocal = false;

  bool get _canManage =>
      widget.roleCode == 'owner' ||
      widget.roleCode == 'manager' ||
      widget.roleCode == 'office';

  @override
  void initState() {
    super.initState();
    _listenForQuarantine();
    _restoreSort();
    _load();
  }

  void _listenForQuarantine() {
    _jobVisibility = JobSummaryVisibility(
      businessId: widget.businessId,
      onQuarantine: (jobIds) {
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
      },
    );
  }

  // An invoice can remain independently readable after its Job is revoked.
  List<Map<String, dynamic>> _withoutJobLabels(
    List<Map<String, dynamic>> rows, Set<String> jobIds,
  ) => rows.map((row) => jobIds.contains(row['job_id']?.toString())
      ? <String, dynamic>{...row, 'job_number': null, 'job_title': null}
      : row).toList();

  Future<void> _refreshQuarantineCounts() async {
    final visibility = _jobVisibility;
    final epoch = visibility.epoch;
    try {
      final query = _search.text.trim();
      final counts = await Future.wait<dynamic>([
        _localJobs.jobCount(widget.businessId,
          status: _selectedStatus, search: query.isEmpty ? null : query),
        _localJobs.jobStatusCounts(widget.businessId),
      ]);
      if (!mounted || !visibility.isCurrent(epoch)) return;
      setState(() {
        _totalCount = counts[0] as int;
        _statusCounts = Map<String, int>.from(counts[1] as Map);
      });
    } catch (_) {
      // Keep the already-pruned cards when a local count refresh fails.
    }
  }

  Future<void> _restoreSort() async {
    final prefs = await SharedPreferences.getInstance();
    final chosen = prefs.getString('briskers_job_sort_${widget.businessId}_${widget.roleCode}');
    if (!mounted || chosen == null) return;
    setState(() => _sort = chosen);
    unawaited(_load());
  }

  Future<void> _setSort(String value) async {
    setState(() => _sort = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('briskers_job_sort_${widget.businessId}_${widget.roleCode}', value);
    if (mounted) unawaited(_load());
  }

  @override
  void dispose() {
    _jobVisibility.dispose();
    _searchDebounce?.cancel();
    _search.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant JobsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId) {
      _jobVisibility.dispose();
      _rows = null;
      _documentMatches = const [];
      _statuses = const [];
      _statusCounts = const {};
      _totalCount = 0;
      _onlineReady = false;
      _listenForQuarantine();
      _load();
    } else if (oldWidget.refreshToken != widget.refreshToken) {
      _load();
    }
  }

  Future<void> _createNewJob() async {
    if (!_canManage) return;
    final selected = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) =>
          JobCustomerPickerScreen(businessId: widget.businessId)),
    );
    if (selected == null || !mounted) return;
    try {
      final id = selected['id']?.toString() ?? '';
      if (id.isEmpty) return;
      final localDetail = await LocalCustomerRepository()
          .customerDetail(widget.businessId, id);
      final detail = localDetail ??
          await _api.customerDetail(widget.businessId, id);
      if (!mounted) return;
      final created = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => JobCreateScreen(
          businessId: widget.businessId,
          customerId: id,
          customerName: selected['display_name']?.toString() ?? 'Customer',
          vehicles: List<dynamic>.from(detail['vehicles'] ?? const []),
        )),
      );
      if (created == true && mounted) {
        _searchDebounce?.cancel();
        _search.clear();
        setState(() => _selectedStatus = null);
        if (_scrollController.hasClients) _scrollController.jumpTo(0);
        // Refresh the durable local row before any optional network work.
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

  Future<void> _load({bool navigationRefresh = false}) async {
    final visibility = _jobVisibility;
    final generation = visibility.beginLoad();
    var localAvailable = false;
    final forceOnline = BriskersConnectionModeController.instance.forceOnline;

    if (!forceOnline) {
      try {
      final query = _search.text.trim();
      final localResults = await Future.wait<dynamic>([
        _localJobs.listJobs(
          widget.businessId,
          status: _selectedStatus,
          sort: _sort,
          search: query.isEmpty ? null : query,
          limit: 30,
        ),
        _localJobs.jobStatuses(widget.businessId),
        _localJobs.hasJobBootstrap(widget.businessId),
        _localJobs.jobCount(
          widget.businessId,
          status: _selectedStatus,
          search: query.isEmpty ? null : query,
        ),
        _localJobs.jobStatusCounts(widget.businessId),
      ]);

      final localRows = await visibility.filter(
          List<Map<String, dynamic>>.from(localResults[0] as List));
      final documentMatches = query.isEmpty
          ? <Map<String, dynamic>>[]
          : await _localDocuments.search(widget.businessId, query, limit: 30);
      final blockedJobIds = await visibility.blockedJobIds();
      final localStatuses =
          List<Map<String, dynamic>>.from(localResults[1] as List);
      final bootstrapped = localResults[2] == true;
      final localTotal = localResults[3] as int;
      final statusCounts = Map<String, int>.from(localResults[4] as Map);

      localAvailable = bootstrapped || localRows.isNotEmpty;

      if (mounted && localAvailable && visibility.isCurrent(generation)) {
        setState(() {
          _rows = localRows;
          _statuses = localStatuses;
          _showingLocal = true;
          if (!navigationRefresh) _onlineReady = false;
          _totalCount = localTotal;
          _statusCounts = statusCounts;
          _documentMatches = _withoutJobLabels(documentMatches, blockedJobIds);
          _error = null;
        });
      }
    } catch (_) {
      // Online loading below can still succeed if the local cache is unavailable.
      }
    }

    if (!mounted || !visibility.isCurrent(generation)) return;

    // Navigation back from a job or invoice must not launch a second full
    // network bootstrap on top of the regular background synchronization.
    // Local rows have already painted above. Search/filter and explicit
    // refresh still use the authoritative online refresh path.
    if (navigationRefresh && !forceOnline && localAvailable) return;

    try {
      // Jobs themselves are refreshed incrementally into the local database.
      // Do not download the complete server job list as history grows.
      final onlineStatuses = await _api.jobStatuses(widget.businessId);
      await _localJobs.replaceJobStatuses(widget.businessId, onlineStatuses);
      if (_canManage) {
        try {
          await _offlineJobAdmin.flush(widget.businessId);
        } catch (_) {
          // Queued job edits remain local and retry when connectivity returns.
        }
        try {
          await _offlineJobAdmin.refreshEmployees(widget.businessId);
        } catch (_) {
          // Keep the last cached employee list for offline assignment.
        }
      }
      await _jobSync.pull(widget.businessId);
      unawaited(_documentSync.refreshBestEffort(widget.businessId));

      final query = _search.text.trim();
      final refreshed = await Future.wait<dynamic>([
        _localJobs.listJobs(
          widget.businessId,
          status: _selectedStatus,
          sort: _sort,
          search: query.isEmpty ? null : query,
          limit: 30,
        ),
        _localJobs.jobCount(
          widget.businessId,
          status: _selectedStatus,
          search: query.isEmpty ? null : query,
        ),
        _localJobs.jobStatusCounts(widget.businessId),
      ]);

      final onlineDocumentMatches = query.isEmpty
          ? <Map<String, dynamic>>[]
          : await _localDocuments.search(
              widget.businessId, query, limit: 30,
            );
      final currentRows = await visibility.filter(
          List<Map<String, dynamic>>.from(refreshed[0] as List));
      final blockedJobIds = await visibility.blockedJobIds();
      if (!mounted || !visibility.isCurrent(generation)) return;
      setState(() {
        _rows = currentRows;
        _statuses = onlineStatuses;
        _documentMatches = _withoutJobLabels(onlineDocumentMatches, blockedJobIds);
        _totalCount = refreshed[1] as int;
        _statusCounts = Map<String, int>.from(refreshed[2] as Map);
        _showingLocal = false;
        _onlineReady = true;
        _error = null;
      });
    } catch (error) {
      if (!mounted || !visibility.isCurrent(generation)) return;
      setState(() {
        _onlineReady = false;
        if (localAvailable && !forceOnline) {
          _showingLocal = true;
          _error = null;
        } else {
          _rows = const [];
          _showingLocal = false;
          _error = error.toString();
        }
      });
    }
  }


  void _searchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 300),
      () {
        if (mounted) _load();
      },
    );
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
          isOwner: widget.roleCode == 'owner',
          canManageExpenses: <String>{'owner', 'manager', 'office'}
              .contains(widget.roleCode),
        ),
      ),
    );
    if (mounted) unawaited(_load(navigationRefresh: true));
    widget.onJobsChanged?.call();
  }

  Future<void> _openJob(Map<String, dynamic> job, {String? initialAction}) async {
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
          employees =
              await _offlineJobAdmin.refreshEmployees(widget.businessId);
        } catch (_) {
          employees =
              await _offlineJobAdmin.cachedEmployees(widget.businessId);
        }
      } else {
        employees =
            await _offlineJobAdmin.cachedEmployees(widget.businessId);
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
              final parsed = num.tryParse(controller.text.trim().isEmpty ? '0' : controller.text.trim());
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
    if (!_canManage ||
        statusCode == job['status']?.toString()) {
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

      await _load();
      widget.onJobsChanged?.call();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busyJobId = null);
    }
  }

  List<Map<String, dynamic>> get _visibleRows {
    final rows = _rows ?? const <Map<String, dynamic>>[];
    if (_selectedStatus == null) return rows;
    return rows
        .where((job) => job['status']?.toString() == _selectedStatus)
        .toList();
  }

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

  List<Map<String, dynamic>> _availableStatusesFor(
    Map<String, dynamic> job,
  ) => _statuses;

  Widget _statusControl(Map<String, dynamic> job) {
    final color = colorFromHex(job['status_color']?.toString());
    final label = jobStatusLabel(job['status']?.toString(), job['status_name']?.toString() ?? 'Status');
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
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: color,
              ),
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
              Text(jobStatusLabel(status['code']?.toString(), status['name']?.toString() ?? '')),
            ],
          ),
        );
      }).toList(),
      child: child,
    );
  }

  Future<void> _showJobActions(Map<String, dynamic> job) async {
    final owner = widget.roleCode == 'owner';
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('Open Job'),
              onTap: () => Navigator.pop(sheetContext, 'open'),
            ),
            if (_canManage)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit Job'),
                onTap: () => Navigator.pop(sheetContext, 'edit'),
              ),
            if (owner)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete Job', style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.pop(sheetContext, 'delete'),
              ),
            const Divider(),
            if (_canManage) ...[
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Add Pre-inspection'),
                onTap: () => Navigator.pop(sheetContext, 'inspection'),
              ),
              ListTile(
                leading: const Icon(Icons.notes_outlined),
                title: const Text('Add Customer Complaint'),
                onTap: () => Navigator.pop(sheetContext, 'complaint'),
              ),
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: const Text('Add Finding'),
                onTap: () => Navigator.pop(sheetContext, 'finding'),
              ),
              ListTile(
                leading: const Icon(Icons.request_quote_outlined),
                title: const Text('Add Estimate'),
                onTap: () => Navigator.pop(sheetContext, 'estimate'),
              ),
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('Add Invoice'),
                onTap: () => Navigator.pop(sheetContext, 'invoice'),
              ),
              ListTile(
                leading: const Icon(Icons.add_card_outlined),
                title: const Text('Add Expense'),
                onTap: () => Navigator.pop(sheetContext, 'expense'),
              ),
            ],
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    await _openJob(job, initialAction: action == 'open' ? null : action);
  }

  Widget _jobCard(Map<String, dynamic> job) => JobCompactCard(
        job: job,
        statusControl: _statusControl(job),
        onOpen: () => _openJob(job),
        onLongPress: () => _showJobActions(job),
        onEditMechanic:
            _canManage ? () => _quickEditMechanic(job) : null,
        onEditPlannedTime:
            _canManage ? () => _quickEditPlannedTime(job) : null,
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
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: BriskersColors.jobs,
                                ),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      tooltip: 'Sort jobs',
                      onSelected: _setSort,
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'newest', child: Text('Newest first')),
                        PopupMenuItem(value: 'updated', child: Text('Recently updated')),
                        PopupMenuItem(value: 'status', child: Text('By job status')),
                        PopupMenuItem(value: 'appointment', child: Text('Appointment date')),
                        PopupMenuItem(value: 'customer', child: Text('Customer A–Z')),
                        PopupMenuItem(value: 'oldest', child: Text('Oldest first')),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.sort, color: BriskersColors.jobs, size: 19),
                          const SizedBox(width: 3),
                          Text({
                            'newest':'Newest first',
                            'updated':'Recently updated',
                            'status':'By status',
                            'appointment':'Appointment date',
                            'customer':'Customer A–Z',
                            'oldest':'Oldest first',
                          }[_sort] ?? 'Newest first', style: const TextStyle(fontSize: 12)),
                          const Icon(Icons.arrow_drop_down, size: 19),
                        ]),
                      ),
                    ),
                    PopupMenuButton<String>(
                    tooltip: tr('filterJobs'),
                    onSelected: (value) {
                      setState(() => _selectedStatus = value == '__all__' ? null : value);
                      _load();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem<String>(
                        value: 'paid_still_open',
                        child: Row(children: [
                          Icon(Icons.payments_outlined),
                          SizedBox(width: 10),
                          Text('Paid, Still Open'),
                        ]),
                      ),
                      PopupMenuItem<String>(
                        value: '__all__',
                        child: Row(
                                children: [
                                  const Icon(Icons.all_inclusive),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(tr('all'))),
                                  _menuCount(_statusCounts.values.fold<int>(0, (a, b) => a + b), alwaysShow: true),
                                ],
                        ),
                      ),
                      ..._statuses.map((status) {
                        final color =
                                  colorFromHex(status['color_hex']?.toString());
                        final code = status['code']?.toString() ?? '';
                        final count = _statusCount(code);
                        return PopupMenuItem<String>(
                                value: code,
                                child: Row(
                                  children: [
                                    Icon(
                                      jobStatusIcon(status['icon_key']?.toString()),
                                      color: color,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(jobStatusLabel(status['code']?.toString(), status['name']?.toString() ?? '')),
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
                                  if (status['code']?.toString() == _selectedStatus) {
                                    selected = status;
                                    break;
                                  }
                                }
                        }
                        final color = selected == null
                                  ? BriskersColors.jobs
                                  : colorFromHex(selected['color_hex']?.toString());
                        final label = _selectedStatus == 'paid_still_open'
                                  ? 'Paid, Still Open'
                                  : selected == null
                                  ? tr('all')
                                  : jobStatusLabel(selected['code']?.toString(), selected['name']?.toString() ?? '');

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
                                    Text(
                                      label,
                                      style: TextStyle(
                                        color: color,
                                        fontWeight: FontWeight.w800,
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
                    const Spacer(),
                    if (_rows != null)
                      Text(
                        '${tr('total')} $_totalCount',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
                        hintText: 'Search job, customer, vehicle, VIN, plate or invoice #',
                        leading: const Icon(Icons.search),
                        trailing: [
                          if (_search.text.isNotEmpty)
                            IconButton(
                              tooltip: 'Clear',
                              onPressed: () {
                                _searchDebounce?.cancel();
                                _search.clear();
                                setState(() {});
                                _load();
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
            onRefresh: _load,
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 80),
              children: [
                if (_showingLocal)
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
                    child: const Row(
                      children: [
                        Icon(Icons.cloud_off_outlined, size: 18),
                        SizedBox(width: 7),
                        Expanded(
                                child: Text(
                                  'Showing saved jobs • online actions are temporarily disabled',
                                  style: TextStyle(fontWeight: FontWeight.w700),
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
                if (_search.text.trim().isNotEmpty && _documentMatches.isNotEmpty) ...[
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
                                  if ((document['job_number']?.toString() ?? '').isNotEmpty)
                                    'Job #${document['job_number']}',
                                  document['vehicle'],
                                ].where((value) => value != null && value.toString().isNotEmpty).join(' • '),
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
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('No jobs in this status.'),
                    ),
                  )
                else
                  ...visible.map(_jobCard),

              ],
            ),
          ),
        ),
      ],
    );
  }
}
