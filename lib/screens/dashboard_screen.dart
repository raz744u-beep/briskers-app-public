import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/briskers_colors.dart';
import '../core/employee_role_style.dart';
import '../core/job_status_style.dart';
import '../services/briskers_api.dart';
import 'jobs/job_detail_screen.dart';
import 'jobs/job_document_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.businessId,
    required this.roleCode,
    this.refreshToken = 0,
    this.onCustomersTap,
    this.onAppointmentsTap,
  });

  final String businessId;
  final String roleCode;
  final int refreshToken;
  final VoidCallback? onCustomersTap;
  final VoidCallback? onAppointmentsTap;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _api = BriskersApi();

  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _statuses = const [];
  String? _error;
  String? _checkingInId;
  String? _busyJobId;
  final Set<String> _expandedJobIds = <String>{};

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
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<dynamic>([
        _api.dashboard(
          widget.businessId,
          DateFormat('yyyy-MM-dd').format(DateTime.now()),
        ),
        _api.jobStatuses(widget.businessId),
      ]);

      if (!mounted) return;
      setState(() {
        _data = Map<String, dynamic>.from(results[0] as Map);
        _statuses = List<Map<String, dynamic>>.from(results[1] as List);
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _openJob(String jobId) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JobDetailScreen(
          businessId: widget.businessId,
          jobId: jobId,
          isOwner: widget.roleCode == 'owner',
        ),
      ),
    );
    await _load();
  }


  Future<void> _openDashboardDocument(String documentId) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JobDocumentScreen(
          businessId: widget.businessId,
          documentId: documentId,
          roleCode: widget.roleCode,
        ),
      ),
    );
    await _load();
  }

  Future<void> _dashboardDocumentAction(Map<String, dynamic> job, String action) async {
    final jobId = job['id'].toString();
    setState(() => _busyJobId = jobId);
    try {
      final documents = await _api.jobDocuments(widget.businessId, jobId);
      final estimates = documents.where((d) => d['kind']?.toString() == 'estimate').toList();
      final invoices = documents.where((d) => d['kind']?.toString() == 'invoice').toList();
      String? id;
      if (action == 'add_estimate') id = await _api.createEstimate(widget.businessId, jobId);
      if (action == 'add_invoice') id = await _api.createInvoice(widget.businessId, jobId);
      if (action == 'estimate' && estimates.isNotEmpty) id = estimates.last['id'].toString();
      if (action == 'invoice' && invoices.isNotEmpty) id = invoices.last['id'].toString();
      if (action == 'convert' && estimates.isNotEmpty) id = await _api.convertEstimate(widget.businessId, estimates.last['id'].toString());
      if (!mounted || id == null) return;
      await _openDashboardDocument(id);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busyJobId = null);
    }
  }

  Future<void> _checkIn(Map<String, dynamic> appointment) async {
    if (!_canManage) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Check in vehicle?'),
        content: Text(
          'Check in ${appointment['customer'] ?? 'this customer'} and create the Job?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Check In'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final appointmentId = appointment['id'].toString();
    setState(() => _checkingInId = appointmentId);

    try {
      final jobId = await _api.checkInAppointment(
        widget.businessId,
        appointmentId,
      );
      await _load();
      if (mounted) await _openJob(jobId);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _checkingInId = null);
    }
  }

  Future<void> _changeJobStatus(
    Map<String, dynamic> job,
    String statusCode,
  ) async {
    if (!_canManage || statusCode == job['status']?.toString()) return;

    final id = job['id'].toString();
    setState(() => _busyJobId = id);

    try {
      await _api.changeJobStatus(
        widget.businessId,
        id,
        statusCode,
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busyJobId = null);
    }
  }

  String _hours(Object? raw) {
    final value = num.tryParse(raw?.toString() ?? '') ?? 0;
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2);
  }

  Widget _todayStatusControl(Map<String, dynamic> job) {
    final color = colorFromHex(job['status_color']?.toString());
    final label = job['status_name']?.toString() ?? 'Status';
    final busy = _busyJobId == job['id']?.toString();

    final child = Container(
      constraints: const BoxConstraints(maxWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.34)),
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
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: color,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
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
      onSelected: (value) => _changeJobStatus(job, value),
      itemBuilder: (context) => _statuses.map((status) {
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

  Widget _activeJobCard(Map<String, dynamic> job) {
    final requested = job['requested_work']?.toString().trim() ?? '';
    final title = job['title']?.toString().trim() ?? '';
    final description = requested.isNotEmpty ? requested : title;
    final number = job['job_number']?.toString().trim() ?? '';
    final customer = job['customer']?.toString().trim() ?? '';
    final mechanic = job['mechanic']?.toString().trim() ?? '';
    final vehicle = job['vehicle']?.toString().trim() ?? '';
    final mechanicStyle = employeeRoleStyle('mechanic');
    final id = job['id'].toString();
    final expanded = _expandedJobIds.contains(id);
    final statusColor = colorFromHex(job['status_color']?.toString());

    void toggleExpanded() {
      setState(() {
        if (expanded) {
          _expandedJobIds.remove(id);
        } else {
          _expandedJobIds.add(id);
        }
      });
    }

    Widget separator() => Container(
          width: 1,
          height: 22,
          margin: const EdgeInsets.symmetric(horizontal: 7),
          color: statusColor.withValues(alpha: 0.28),
        );

    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 7, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        <String>[
                          if (number.isNotEmpty) number,
                          if (customer.isNotEmpty) customer,
                        ].join('  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _todayStatusControl(job),
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        description.isEmpty ? 'No description' : description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: expanded ? 'Collapse job' : 'Expand job',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 34,
                        minHeight: 34,
                      ),
                      onPressed:
                          _busyJobId == id ? null : toggleExpanded,
                      icon: Icon(
                        expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 24,
                      ),
                    ),
                  ],
                ),
                Divider(
                  height: 12,
                  color: statusColor.withValues(alpha: 0.20),
                ),
                Row(
                  children: [
                    if (vehicle.isNotEmpty)
                      Flexible(
                        flex: 5,
                        child: Text(
                          vehicle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (vehicle.isNotEmpty && mechanic.isNotEmpty)
                      separator(),
                    if (mechanic.isNotEmpty) ...[
                      Icon(
                        mechanicStyle.icon,
                        size: 15,
                        color: mechanicStyle.color,
                      ),
                      const SizedBox(width: 3),
                      Flexible(
                        flex: 4,
                        child: Text(
                          mechanic,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                    if (vehicle.isNotEmpty || mechanic.isNotEmpty)
                      separator(),
                    Text(
                      '${_hours(job['planned_hours'])} hr',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 3),
                    const Icon(
                      Icons.timer_outlined,
                      size: 15,
                      color: BriskersColors.jobs,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busyJobId == id ? null : () => _openJob(id),
                      icon: const Icon(Icons.open_in_new_outlined),
                      label: const Text('Open full job', style: TextStyle(fontSize: 15)),
                    ),
                  ),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _api.jobDocuments(widget.businessId, id),
                    builder: (context, snapshot) {
                      final docs = snapshot.data ?? const <Map<String, dynamic>>[];
                      final hasEstimate = docs.any((d) => d['kind']?.toString() == 'estimate');
                      final hasInvoice = docs.any((d) => d['kind']?.toString() == 'invoice');
                      return PopupMenuButton<String>(
                        tooltip: 'Job actions',
                        onSelected: (value) {
                          if (value == 'open') _openJob(id);
                          if (value == 'add_estimate' || value == 'add_invoice' ||
                              value == 'estimate' || value == 'invoice' || value == 'convert') {
                            _dashboardDocumentAction(job, value);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(value: 'open', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.open_in_new_outlined), title: Text('Open full job'))),
                          if (!hasEstimate && !hasInvoice) ...[
                            const PopupMenuItem(value: 'add_estimate', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.description_outlined, color: BriskersColors.estimates), title: Text('Add estimate'))),
                            const PopupMenuItem(value: 'add_invoice', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.receipt_long_outlined, color: BriskersColors.invoices), title: Text('Add invoice'))),
                          ],
                          if (hasEstimate) ...[
                            const PopupMenuItem(value: 'estimate', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.description_outlined, color: BriskersColors.estimates), title: Text('View / edit estimate'))),
                            if (!hasInvoice) const PopupMenuItem(value: 'convert', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.transform_outlined, color: BriskersColors.invoices), title: Text('Convert estimate to invoice'))),
                          ],
                          if (hasInvoice) const PopupMenuItem(value: 'invoice', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.receipt_long_outlined, color: BriskersColors.invoices), title: Text('View / edit invoice'))),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_data == null && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final appointments = List<dynamic>.from(
      _data?['appointments'] ?? const [],
    ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();

    final activeJobs = List<dynamic>.from(
      _data?['active_jobs'] ?? const [],
    ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Text(
            DateFormat('EEEE, MMMM d').format(DateTime.now()),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'Customers',
                  value: '${_data?['customer_count'] ?? '—'}',
                  icon: Icons.people,
                  color: BriskersColors.customers,
                  onTap: widget.onCustomersTap,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCard(
                  label: 'Requests',
                  value: '${_data?['pending_appointment_requests'] ?? 0}',
                  icon: Icons.pending_actions,
                  color: BriskersColors.appointments,
                  onTap: widget.onAppointmentsTap,
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              const Icon(
                Icons.calendar_month_outlined,
                color: BriskersColors.appointments,
              ),
              const SizedBox(width: 7),
              Text(
                'Appointments',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: BriskersColors.appointments,
                    ),
              ),
              const Spacer(),
              Text(
                '${appointments.length}',
                style: const TextStyle(
                  color: BriskersColors.appointments,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          if (appointments.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No confirmed appointments for today.'),
              ),
            )
          else
            ...appointments.map((item) {
              final start =
                  DateTime.tryParse(item['starts_at']?.toString() ?? '');
              final time = start == null
                  ? ''
                  : DateFormat('h:mm a').format(start.toLocal());
              final mechanic = item['mechanic']?.toString() ?? '';
              final checking = _checkingInId == item['id']?.toString();

              return Card(
                margin: const EdgeInsets.only(bottom: 7),
                child: ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 19,
                    backgroundColor:
                        BriskersColors.appointments.withValues(alpha: 0.14),
                    child: const Icon(
                      Icons.event_outlined,
                      color: BriskersColors.appointments,
                      size: 21,
                    ),
                  ),
                  title: Text(
                    <String>[
                      if (time.isNotEmpty) time,
                      item['title']?.toString() ?? 'Appointment',
                    ].join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    <String>[
                      item['customer']?.toString() ?? '',
                      if ((item['vehicle']?.toString() ?? '').isNotEmpty)
                        item['vehicle'].toString(),
                      if (mechanic.isNotEmpty) 'Planned: $mechanic',
                    ].where((value) => value.isNotEmpty).join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: _canManage
                      ? checking
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : IconButton(
                              tooltip: 'Check in / Create job',
                              onPressed: () => _checkIn(item),
                              icon: const Icon(
                                Icons.login_outlined,
                                color: BriskersColors.appointments,
                              ),
                            )
                      : null,
                ),
              );
            }),
          const SizedBox(height: 20),
          Row(
            children: [
              const Icon(
                Icons.build_outlined,
                color: BriskersColors.jobs,
              ),
              const SizedBox(width: 7),
              Text(
                'Active Jobs',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: BriskersColors.jobs,
                    ),
              ),
              const Spacer(),
              Text(
                '${activeJobs.length}',
                style: const TextStyle(
                  color: BriskersColors.jobs,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          if (activeJobs.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No active jobs right now.'),
              ),
            )
          else
            ...activeJobs.map(_activeJobCard),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color.withValues(alpha: 0.08),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: color.withValues(alpha: 0.16),
                child: Icon(icon, color: color, size: 19),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
              ),
              Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
