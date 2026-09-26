import 'package:flutter/material.dart';

import '../core/briskers_colors.dart';
import '../core/employee_role_style.dart';
import '../core/job_status_style.dart';
import '../services/briskers_api.dart';
import 'jobs/job_detail_screen.dart';
import 'jobs/job_edit_screen.dart';
import 'jobs/job_document_screen.dart';

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
  final Set<String> _expandedIds = <String>{};
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

  Future<void> _editJob(Map<String, dynamic> job) async {
    if (!_canManage) return;

    setState(() => _busyJobId = job['id']?.toString());
    try {
      final detail = await _api.jobDetail(
        widget.businessId,
        job['id'].toString(),
      );
      if (!mounted) return;

      final changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => JobEditScreen(
            businessId: widget.businessId,
            job: detail,
          ),
        ),
      );

      if (changed == true) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busyJobId = null);
    }
  }


  Future<void> _openDocument(String documentId) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JobDocumentScreen(
          businessId: widget.businessId,
          documentId: documentId,
          isOwner: widget.roleCode == 'owner',
        ),
      ),
    );
    await _load();
  }

  Future<void> _documentAction(Map<String, dynamic> job, String action) async {
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
      if (action == 'convert' && estimates.isNotEmpty) {
        id = await _api.convertEstimate(widget.businessId, estimates.last['id'].toString());
      }
      if (!mounted || id == null) return;
      await _openDocument(id);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busyJobId = null);
    }
  }

  Future<List<Map<String, dynamic>>> _documentsFor(Map<String, dynamic> job) =>
      _api.jobDocuments(widget.businessId, job['id'].toString());

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

  Future<void> _cancelJob(Map<String, dynamic> job) async {
    if (!_canManage) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel job?'),
        content: Text(
          'Mark ${job['job_number'] ?? 'this job'} as Cancelled? '
          'The job stays in history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep job'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancel job'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _changeStatus(job, 'cancelled');
    }
  }

  List<Map<String, dynamic>> get _visibleRows {
    final rows = _rows ?? const <Map<String, dynamic>>[];
    if (_selectedStatus == null) return rows;
    return rows
        .where((job) => job['status']?.toString() == _selectedStatus)
        .toList();
  }

  String _hours(Object? raw) {
    final value = num.tryParse(raw?.toString() ?? '') ?? 0;
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2);
  }

  Color _jobCardTint(Map<String, dynamic> job) {
    final statusColor = colorFromHex(job['status_color']?.toString());
    return Color.alphaBlend(
      statusColor.withValues(alpha: 0.11),
      const Color(0xFFF7FAF9),
    );
  }

  List<Map<String, dynamic>> _availableStatusesFor(
    Map<String, dynamic> job,
  ) {
    if (job['status']?.toString() == 'completed') {
      return _statuses
          .where((status) => status['code']?.toString() == 'needs_recheck')
          .toList();
    }
    return _statuses;
  }

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
                alignment: Alignment.centerLeft,
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

  Widget _jobCard(Map<String, dynamic> job) {
    final id = job['id'].toString();
    final expanded = _expandedIds.contains(id);
    final number = job['job_number']?.toString().trim() ?? '';
    final customer = job['customer_name']?.toString().trim() ?? '';
    final requested = job['requested_work']?.toString().trim() ?? '';
    final title = job['title']?.toString().trim() ?? '';
    final description = requested.isNotEmpty ? requested : title;
    final vehicle = job['vehicle']?.toString().trim() ?? '';
    final mechanic = job['assigned_employee']?.toString().trim() ?? '';
    final mechanicStyle = employeeRoleStyle('mechanic');
    final requests =
        int.tryParse(job['pending_requests']?.toString() ?? '') ?? 0;
    final isBusy = _busyJobId == id;
    final cardTint = _jobCardTint(job);
    final statusColor = colorFromHex(job['status_color']?.toString());

    void toggleExpanded() {
      setState(() {
        if (expanded) {
          _expandedIds.remove(id);
        } else {
          _expandedIds.add(id);
        }
      });
    }

    Widget separator() => Container(
          width: 1,
          height: 22,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          color: statusColor.withValues(alpha: 0.30),
        );

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: cardTint,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FractionallySizedBox(
                      widthFactor: 0.72,
                      heightFactor: 0.88,
                      child: Opacity(
                        opacity: 0.32,
                        child: Image.asset(
                          'assets/job_car_watermark.png',
                          fit: BoxFit.contain,
                          alignment: Alignment.centerRight,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 11, 8, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
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
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _statusControl(job),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            description.isEmpty
                                ? 'No description'
                                : description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 13.5,
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
                          onPressed: isBusy ? null : toggleExpanded,
                          icon: Icon(
                            expanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            size: 25,
                          ),
                        ),
                      ],
                    ),
                    Divider(
                      height: 13,
                      color: statusColor.withValues(alpha: 0.22),
                    ),
                    Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              vehicle.isEmpty ? 'No vehicle' : vehicle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        separator(),
                        Expanded(
                          flex: 5,
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(mechanicStyle.icon, size: 17, color: mechanicStyle.color),
                                const SizedBox(width: 5),
                                if (mechanic.isNotEmpty) ...[
                                  CircleAvatar(
                                    radius: 12,
                                    backgroundColor: mechanicStyle.color,
                                    child: Text(
                                      mechanic.split(RegExp(r'\\s+')).where((p) => p.isNotEmpty).take(2).map((p) => p[0].toUpperCase()).join(),
                                      style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      mechanic.split(RegExp(r'\\s+')).first,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ] else
                                  const Text('Unassigned', style: TextStyle(fontSize: 14)),
                              ],
                            ),
                          ),
                        ),
                        separator(),
                        SizedBox(
                          width: 82,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text('${_hours(job['planned_hours'])} hr', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                              const SizedBox(width: 4),
                              const Icon(Icons.timer_outlined, size: 17, color: BriskersColors.jobs),
                            ],
                          ),
                        ),
                        if (_canManage && requests > 0) ...[
                          const SizedBox(width: 5),
                          Text('$requests', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _DetailLine(
                          icon: Icons.directions_car_outlined,
                          label: 'Vehicle',
                          value: vehicle.isEmpty ? 'No vehicle' : vehicle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DetailLine(
                          icon: Icons.engineering_outlined,
                          label: 'Mechanic',
                          value: mechanic.isEmpty ? 'Unassigned' : mechanic,
                        ),
                      ),
                      FutureBuilder<List<Map<String, dynamic>>>(
                        future: _documentsFor(job),
                        builder: (context, snapshot) {
                          final docs = snapshot.data ?? const <Map<String, dynamic>>[];
                          final estimates = docs.where((d) => d['kind']?.toString() == 'estimate').toList();
                          final invoices = docs.where((d) => d['kind']?.toString() == 'invoice').toList();
                          final hasEstimate = estimates.isNotEmpty;
                          final hasInvoice = invoices.isNotEmpty;
                          return PopupMenuButton<String>(
                            tooltip: 'Job actions',
                            onSelected: (value) {
                              if (value == 'open') _openJob(job);
                              if (value == 'edit') _editJob(job);
                              if (value == 'cancel') _cancelJob(job);
                              if (value == 'add_estimate' || value == 'add_invoice' ||
                                  value == 'estimate' || value == 'invoice' || value == 'convert') {
                                _documentAction(job, value);
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(value: 'open', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.open_in_new_outlined), title: Text('Open full job'))),
                              if (_canManage) const PopupMenuItem(value: 'edit', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.edit_outlined), title: Text('Edit job'))),
                              if (!hasEstimate && !hasInvoice) ...[
                                const PopupMenuItem(value: 'add_estimate', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.description_outlined, color: BriskersColors.estimates), title: Text('Add estimate'))),
                                const PopupMenuItem(value: 'add_invoice', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.receipt_long_outlined, color: BriskersColors.invoices), title: Text('Add invoice'))),
                              ],
                              if (hasEstimate) ...[
                                const PopupMenuItem(value: 'estimate', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.description_outlined, color: BriskersColors.estimates), title: Text('View / edit estimate'))),
                                if (!hasInvoice) const PopupMenuItem(value: 'convert', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.transform_outlined, color: BriskersColors.invoices), title: Text('Convert estimate to invoice'))),
                              ],
                              if (hasInvoice) const PopupMenuItem(value: 'invoice', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.receipt_long_outlined, color: BriskersColors.invoices), title: Text('View / edit invoice'))),
                              if (_canManage && job['status']?.toString() != 'completed' && job['status']?.toString() != 'cancelled')
                                const PopupMenuItem(value: 'cancel', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.cancel_outlined), title: Text('Cancel job'))),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                  if (title.isNotEmpty) ...[
                    const SizedBox(height: 9),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  if (requested.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        requested,
                        style: TextStyle(
                          fontSize: 15,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: isBusy ? null : () => _openJob(job),
                      icon: const Icon(Icons.chevron_right),
                      label: const Text('Open job'),
                    ),
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
                  '${visible.length}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: BriskersColors.jobs,
                        fontWeight: FontWeight.w700,
                      ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: const Text('All'),
                    selected: _selectedStatus == null,
                    selectedColor:
                        BriskersColors.jobs.withValues(alpha: 0.16),
                    onSelected: (_) => setState(() => _selectedStatus = null),
                  ),
                ),
                ..._statuses.map((status) {
                  final code = status['code']?.toString() ?? '';
                  final color = colorFromHex(status['color_hex']?.toString());
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      avatar: Icon(
                        jobStatusIcon(status['icon_key']?.toString()),
                        size: 15,
                        color: color,
                      ),
                      label: Text(status['name']?.toString() ?? ''),
                      selected: _selectedStatus == code,
                      selectedColor: color.withValues(alpha: 0.16),
                      side: BorderSide(
                        color: color.withValues(alpha: 0.28),
                      ),
                      onSelected: (_) =>
                          setState(() => _selectedStatus = code),
                    ),
                  );
                }),
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

class _DetailLine extends StatelessWidget {
  const _DetailLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: BriskersColors.jobs),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
