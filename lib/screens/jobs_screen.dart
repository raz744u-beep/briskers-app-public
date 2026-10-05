import 'dart:async';

import 'package:flutter/material.dart';

import '../core/briskers_colors.dart';
import '../core/briskers_i18n.dart';
import '../core/job_status_style.dart';
import '../services/briskers_api.dart';
import '../services/job_sync_service.dart';
import '../services/document_index_sync_service.dart';
import '../services/local_document_repository.dart';
import '../services/local_job_repository.dart';
import '../widgets/job_compact_card.dart';
import 'jobs/job_detail_screen.dart';
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

  List<Map<String, dynamic>>? _rows;
  List<Map<String, dynamic>> _statuses = const [];
  String? _selectedStatus;
  final TextEditingController _search = TextEditingController();
  Timer? _searchDebounce;
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
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant JobsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _load();
    }
  }

  Future<void> _load() async {
    var localAvailable = false;

    try {
      final query = _search.text.trim();
      final localResults = await Future.wait<dynamic>([
        _localJobs.listJobs(
          widget.businessId,
          status: _selectedStatus,
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

      final localRows =
          List<Map<String, dynamic>>.from(localResults[0] as List);
      final documentMatches = query.isEmpty
          ? <Map<String, dynamic>>[]
          : await _localDocuments.search(widget.businessId, query, limit: 30);
      final localStatuses =
          List<Map<String, dynamic>>.from(localResults[1] as List);
      final bootstrapped = localResults[2] == true;
      final localTotal = localResults[3] as int;
      final statusCounts = Map<String, int>.from(localResults[4] as Map);

      localAvailable = bootstrapped || localRows.isNotEmpty;

      if (mounted && localAvailable) {
        setState(() {
          _rows = localRows;
          _statuses = localStatuses;
          _showingLocal = true;
          _onlineReady = false;
          _totalCount = localTotal;
          _statusCounts = statusCounts;
          _documentMatches = documentMatches;
          _error = null;
        });
      }
    } catch (_) {
      // Online loading below can still succeed if the local cache is unavailable.
    }

    try {
      // Jobs themselves are refreshed incrementally into the local database.
      // Do not download the complete server job list as history grows.
      final onlineStatuses = await _api.jobStatuses(widget.businessId);
      await _localJobs.replaceJobStatuses(widget.businessId, onlineStatuses);
      await _jobSync.pull(widget.businessId);
      unawaited(_documentSync.refreshBestEffort(widget.businessId));

      final query = _search.text.trim();
      final refreshed = await Future.wait<dynamic>([
        _localJobs.listJobs(
          widget.businessId,
          status: _selectedStatus,
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

      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(refreshed[0] as List);
        _statuses = onlineStatuses;
        _totalCount = refreshed[1] as int;
        _statusCounts = Map<String, int>.from(refreshed[2] as Map);
        _showingLocal = false;
        _onlineReady = true;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _onlineReady = false;
        if (localAvailable) {
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
    if (mounted) unawaited(_load());
    widget.onJobsChanged?.call();
  }

  Future<void> _openJob(Map<String, dynamic> job) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JobDetailScreen(
          businessId: widget.businessId,
          jobId: job['id'].toString(),
          roleCode: widget.roleCode,
          bottomNavigationBar: widget.jobDetailBottomNavigationBar,
        ),
      ),
    );
    if (mounted) unawaited(_load());
    widget.onJobsChanged?.call();
  }

  Future<void> _changeStatus(
    Map<String, dynamic> job,
    String statusCode,
  ) async {
    if (!_canManage ||
        !_onlineReady ||
        statusCode == job['status']?.toString()) {
      return;
    }

    setState(() => _busyJobId = job['id']?.toString());
    try {
      await _api.changeJobStatus(
        widget.businessId,
        job['id'].toString(),
        statusCode,
      );
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
          if (_canManage && _onlineReady && !busy) ...[
            const SizedBox(width: 3),
            Icon(Icons.chevron_right, size: 15, color: color),
          ],
        ],
      ),
    );

    if (!_canManage || !_onlineReady || busy) return child;

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

  Widget _jobCard(Map<String, dynamic> job) => JobCompactCard(
        job: job,
        statusControl: _statusControl(job),
        onOpen: () => _openJob(job),
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
                    tooltip: tr('filterJobs'),
                    onSelected: (value) {
                      setState(() => _selectedStatus = value == '__all__' ? null : value);
                      _load();
                    },
                    itemBuilder: (_) => [
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
                        final label = selected == null
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
                SearchBar(
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


              ],
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
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