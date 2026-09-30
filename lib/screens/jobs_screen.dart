import 'package:flutter/material.dart';

import '../core/briskers_colors.dart';
import '../core/job_status_style.dart';
import '../services/briskers_api.dart';
import '../widgets/job_compact_card.dart';
import 'jobs/job_detail_screen.dart';

class JobsScreen extends StatefulWidget {
  const JobsScreen({
    super.key,
    required this.businessId,
    required this.roleCode,
    this.refreshToken = 0,
  });

  final String businessId;
  final String roleCode;
  final int refreshToken;

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  static const _api = BriskersApi();

  List<Map<String, dynamic>>? _rows;
  List<Map<String, dynamic>> _statuses = const [];
  String? _selectedStatus;
  String? _error;
  String? _busyJobId;

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
  void didUpdateWidget(covariant JobsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<dynamic>([
        _api.jobs(widget.businessId),
        _api.jobStatuses(widget.businessId),
      ]);
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(results[0] as List);
        _statuses = List<Map<String, dynamic>>.from(results[1] as List);
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _rows = const [];
        _error = error.toString();
      });
    }
  }

  Future<void> _openJob(Map<String, dynamic> job) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JobDetailScreen(
          businessId: widget.businessId,
          jobId: job['id'].toString(),
          roleCode: widget.roleCode,
        ),
      ),
    );
    await _load();
  }

  Future<void> _changeStatus(
    Map<String, dynamic> job,
    String statusCode,
  ) async {
    if (!_canManage || statusCode == job['status']?.toString()) return;

    setState(() => _busyJobId = job['id']?.toString());
    try {
      await _api.changeJobStatus(
        widget.businessId,
        job['id'].toString(),
        statusCode,
      );
      await _load();
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

  int _statusCount(String code) {
    final rows = _rows ?? const <Map<String, dynamic>>[];
    return rows.where((job) => job['status']?.toString() == code).length;
  }

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
    final label = job['status_name']?.toString() ?? 'Status';
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
      tooltip: 'Change status',
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
              Text(status['name']?.toString() ?? ''),
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

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 80),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Jobs',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: BriskersColors.jobs,
                      ),
                ),
              ),
              if (_rows != null)
                Text(
                  'Total ${_rows!.length}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: BriskersColors.jobs,
                        fontWeight: FontWeight.w700,
                      ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: PopupMenuButton<String>(
              tooltip: 'Filter jobs',
              onSelected: (value) => setState(
                () => _selectedStatus = value == '__all__' ? null : value,
              ),
              itemBuilder: (_) => [
                PopupMenuItem<String>(
                  value: '__all__',
                  child: Row(
                    children: [
                      const Icon(Icons.all_inclusive),
                      const SizedBox(width: 10),
                      const Expanded(child: Text('All')),
                      _menuCount(_rows?.length ?? 0, alwaysShow: true),
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
                          child: Text(status['name']?.toString() ?? ''),
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
                  final label =
                      selected?['name']?.toString() ?? 'All';

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
    );
  }
}
