import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/briskers_colors.dart';
import '../services/appointment_sync_service.dart';
import '../services/briskers_api.dart';
import '../services/job_sync_service.dart';
import '../services/local_appointment_repository.dart';
import 'appointments/appointment_manage_screen.dart';
import 'jobs/job_detail_screen.dart';

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({
    super.key,
    required this.businessId,
    required this.roleCode,
  });

  final String businessId;
  final String roleCode;

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  static const _api = BriskersApi();
  final AppointmentSyncService _appointmentSync =
      AppointmentSyncService();
  final JobSyncService _jobSync = JobSyncService();
  final LocalAppointmentRepository _localAppointments =
      LocalAppointmentRepository();

  List<Map<String, dynamic>>? _appointments;
  String _filter = 'today';
  String? _error;
  String? _checkingInId;
  int _pending = 0;
  bool _onlineReady = false;
  bool _showingLocal = false;

  bool get _canManage =>
      widget.roleCode == 'owner' ||
      widget.roleCode == 'manager' ||
      widget.roleCode == 'office';

  bool get _canCheckIn =>
      _canManage || widget.roleCode == 'kiosk';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var localAvailable = false;

    try {
      final localRows =
          await _localAppointments.appointments(widget.businessId);
      final bootstrapped =
          await _localAppointments.hasBootstrap(widget.businessId);
      localAvailable = bootstrapped || localRows.isNotEmpty;

      if (mounted && localAvailable) {
        setState(() {
          _appointments = localRows;
          _showingLocal = true;
          _onlineReady = false;
          _error = null;
        });
      }
    } catch (_) {
      // Online refresh below can still populate the local appointment cache.
    }

    try {
      final appliedJobs =
          await _appointmentSync.flush(widget.businessId);
      if (appliedJobs.isNotEmpty) {
        try {
          await _jobSync.pull(widget.businessId);
        } catch (_) {}
      }

      await _appointmentSync.pull(widget.businessId);
      final localRows =
          await _localAppointments.appointments(widget.businessId);
      final bootstrapped =
          await _localAppointments.hasBootstrap(widget.businessId);

      final now = DateTime.now();
      var pending = 0;
      if (_canManage) {
        try {
          final dashboard = await _api.dashboard(
            widget.businessId,
            DateFormat('yyyy-MM-dd').format(now),
          );
          pending = int.tryParse(
                dashboard['pending_appointment_requests']?.toString() ?? '',
              ) ??
              0;
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _appointments = localRows;
        _pending = pending;
        _onlineReady = bootstrapped;
        _showingLocal = !bootstrapped;
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
          _appointments ??= const [];
          _error = error.toString();
        }
      });
    }
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<Map<String, dynamic>> get _visibleAppointments {
    final rows = _appointments ?? const <Map<String, dynamic>>[];
    final now = DateTime.now();
    return rows.where((row) {
      final start =
          DateTime.tryParse(row['starts_at']?.toString() ?? '')?.toLocal();
      if (start == null) return false;
      switch (_filter) {
        case 'today':
          return _sameDay(start, now);
        case 'upcoming':
          return start.isAfter(now) && !_sameDay(start, now);
        case 'past':
          return start.isBefore(now) && !_sameDay(start, now);
        default:
          return true;
      }
    }).toList();
  }

  Future<void> _addAppointment() async {
    if (!_onlineReady || !_canManage) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AppointmentManageScreen(
          businessId: widget.businessId,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _editAppointment(Map<String, dynamic> item) async {
    if (!_onlineReady || !_canManage) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AppointmentManageScreen(
          businessId: widget.businessId,
          appointment: item,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
    bool destructive = false,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('No'),
              ),
              FilledButton(
                style: destructive
                    ? FilledButton.styleFrom(backgroundColor: Colors.red)
                    : null,
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _cancelAppointment(Map<String, dynamic> item) async {
    if (!_onlineReady || !_canManage) return;
    final ok = await _confirm(
      title: 'Cancel appointment?',
      message:
          'This keeps the appointment in your records and marks it as canceled.',
      action: 'Cancel appointment',
      destructive: true,
    );
    if (!ok) return;
    try {
      await _api.cancelAppointment(widget.businessId, item['id'].toString());
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _deleteAppointment(Map<String, dynamic> item) async {
    if (!_onlineReady || widget.roleCode != 'owner') return;
    final ok = await _confirm(
      title: 'Delete appointment?',
      message:
          'This permanently deletes the appointment. This cannot be undone.',
      action: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    try {
      await _api.deleteAppointment(widget.businessId, item['id'].toString());
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _setStatus(
    Map<String, dynamic> item,
    String status,
  ) async {
    if (!_onlineReady || !_canManage) return;
    try {
      await _api.setAppointmentStatus(
        widget.businessId,
        item['id'].toString(),
        status,
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _checkIn(Map<String, dynamic> item) async {
    if (!_canCheckIn || item['can_check_in'] != true) return;

    final syncState = item['sync_state']?.toString() ?? 'synced';
    if (syncState == 'conflict') {
      setState(() {
        _error =
            'This appointment changed elsewhere. Reconnect and refresh before checking it in.';
      });
      return;
    }

    final confirmed = await _confirm(
      title: 'Check in vehicle?',
      message:
          'Briskers will save the check-in on this device immediately. If offline, the linked job will be created when the connection returns.',
      action: 'Check In',
    );
    if (!confirmed) return;

    final appointmentId = item['id'].toString();
    setState(() => _checkingInId = appointmentId);

    try {
      await _appointmentSync.queueCheckIn(
        widget.businessId,
        appointmentId,
      );

      final local = await _localAppointments.appointments(
        widget.businessId,
      );
      if (mounted) {
        setState(() {
          _appointments = local;
          _error = null;
        });
      }

      Map<String, String> appliedJobs = const {};
      try {
        appliedJobs = await _appointmentSync.flush(widget.businessId);
        await _appointmentSync.pull(widget.businessId);
        if (appliedJobs.isNotEmpty) {
          try {
            await _jobSync.pull(widget.businessId);
          } catch (_) {}
        }
      } catch (_) {
        // Offline is expected. The check-in stays queued locally.
      }

      final jobId = appliedJobs[appointmentId];
      if (!mounted) return;

      if (jobId == null || jobId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Check-in saved on this device. It will sync automatically when Briskers reconnects.',
            ),
          ),
        );
        return;
      }

      await _load();
      if (!mounted) return;

      if (widget.roleCode == 'kiosk') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Check-in completed.')),
        );
        return;
      }

      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => JobDetailScreen(
            businessId: widget.businessId,
            jobId: jobId,
            roleCode: widget.roleCode,
          ),
        ),
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _checkingInId = null);
    }
  }

  Future<void> _showOptions(Map<String, dynamic> item) async {
    if (!_canManage && !_canCheckIn) return;

    final status = item['status']?.toString() ?? '';
    final syncState = item['sync_state']?.toString() ?? 'synced';
    final queued = syncState == 'pending';
    final conflict = syncState == 'conflict';
    final canEdit = _onlineReady &&
        _canManage &&
        {'confirmed', 'tentative'}.contains(status) &&
        item['job_id'] == null &&
        !queued &&
        !conflict;
    final canCheckIn = _canCheckIn &&
        item['can_check_in'] == true &&
        item['job_id'] == null &&
        !queued &&
        !conflict;
    final canCancel = canEdit;
    final canDelete = _onlineReady &&
        widget.roleCode == 'owner' &&
        item['job_id'] == null &&
        item['request_id'] == null &&
        {'confirmed', 'tentative', 'cancelled', 'no_show'}.contains(status);

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                item['customer']?.toString() ?? 'Appointment',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                <String>[
                  item['title']?.toString() ?? '',
                  item['vehicle']?.toString() ?? '',
                ].where((value) => value.isNotEmpty).join(' • '),
              ),
            ),
            if (canEdit)
              ListTile(
                leading: const Icon(
                  Icons.edit_outlined,
                  color: BriskersColors.appointments,
                ),
                title: const Text('Edit appointment'),
                onTap: () => Navigator.pop(sheetContext, 'edit'),
              ),
            if (canCheckIn)
              ListTile(
                leading: const Icon(
                  Icons.login_outlined,
                  color: BriskersColors.appointments,
                ),
                title: const Text('Check in'),
                onTap: () => Navigator.pop(sheetContext, 'checkin'),
              ),
            if (queued)
              const ListTile(
                leading: Icon(Icons.cloud_upload_outlined),
                title: Text('Check-in saved locally'),
                subtitle: Text('Waiting to sync'),
              ),
            if (conflict)
              const ListTile(
                leading: Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange,
                ),
                title: Text('Check-in sync conflict'),
                subtitle: Text('Reconnect and refresh before retrying'),
              ),
            if (canCancel)
              ListTile(
                leading: const Icon(Icons.event_busy_outlined, color: Colors.red),
                title: const Text(
                  'Cancel appointment',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () => Navigator.pop(sheetContext, 'cancel'),
              ),
            if (canDelete)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Delete appointment',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () => Navigator.pop(sheetContext, 'delete'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted) return;
    switch (action) {
      case 'edit':
        await _editAppointment(item);
        break;
      case 'checkin':
        await _checkIn(item);
        break;
      case 'cancel':
        await _cancelAppointment(item);
        break;
      case 'delete':
        await _deleteAppointment(item);
        break;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'tentative':
        return const Color(0xFFEF6C00);
      case 'cancelled':
      case 'no_show':
        return const Color(0xFFC62828);
      case 'arrived':
        return const Color(0xFF2E7D32);
      case 'finished':
        return const Color(0xFF00897B);
      default:
        return BriskersColors.appointments;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'tentative':
        return 'Tentative';
      case 'no_show':
        return 'No show';
      case 'arrived':
        return 'Checked in';
      case 'finished':
        return 'Finished';
      case 'cancelled':
        return 'Canceled';
      default:
        return 'Confirmed';
    }
  }

  Widget _statusPill(Map<String, dynamic> item) {
    final status = item['status']?.toString() ?? 'confirmed';
    final color = _statusColor(status);
    final locked = item['job_id'] != null || {'arrived', 'finished'}.contains(status);

    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    if (!_canManage || !_onlineReady || locked) return pill;

    return PopupMenuButton<String>(
      tooltip: 'Change appointment status',
      onSelected: (value) => _setStatus(item, value),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'tentative', child: Text('Tentative')),
        PopupMenuItem(value: 'confirmed', child: Text('Confirmed')),
        PopupMenuItem(value: 'no_show', child: Text('No show')),
        PopupMenuItem(value: 'cancelled', child: Text('Canceled')),
      ],
      child: pill,
    );
  }

  Widget _makeBadge(String make) {
    final clean = make.trim();
    final upper = clean.toUpperCase();

    String mark;
    if (upper.contains('MERCEDES')) {
      mark = '✦';
    } else if (upper.contains('BMW')) {
      mark = 'BMW';
    } else if (upper.contains('VOLKSWAGEN') || upper == 'VW') {
      mark = 'VW';
    } else if (upper.contains('AUDI')) {
      mark = '○○○○';
    } else if (upper.contains('PORSCHE')) {
      mark = 'P';
    } else if (upper.contains('TOYOTA')) {
      mark = 'T';
    } else if (upper.contains('HONDA')) {
      mark = 'H';
    } else if (upper.contains('FORD')) {
      mark = 'Ford';
    } else if (upper.contains('CHEVROLET') || upper.contains('CHEVY')) {
      mark = '✚';
    } else {
      mark = clean.isEmpty ? 'CAR' : upper.substring(0, upper.length > 3 ? 3 : upper.length);
    }

    return Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFD8DEE8)),
      ),
      child: Text(
        mark,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: upper.contains('BMW')
              ? const Color(0xFF1B4F9C)
              : const Color(0xFF30343B),
          fontSize: mark.length > 3 ? 10 : 14,
          fontWeight: FontWeight.w900,
          letterSpacing: mark == '○○○○' ? -2 : 0,
        ),
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(
        label,
        maxLines: 1,
        softWrap: false,
      ),
      selected: selected,
      onSelected: (_) => setState(() => _filter = value),
      labelStyle: TextStyle(
        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        color: selected ? Colors.white : BriskersColors.appointments,
      ),
      selectedColor: BriskersColors.appointments,
      backgroundColor: BriskersColors.appointments.withValues(alpha: 0.08),
      side: BorderSide(
        color: BriskersColors.appointments.withValues(alpha: 0.35),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      visualDensity: VisualDensity.compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleAppointments;
    final total = _appointments?.length ?? 0;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 84),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Appointments',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: BriskersColors.appointments,
                      ),
                ),
              ),
              Text(
                'Total $total',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: BriskersColors.appointments,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              if (_canManage && _onlineReady) ...[
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: BriskersColors.appointments,
                  ),
                  onPressed: _addAppointment,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('all', 'All'),
                const SizedBox(width: 7),
                _filterChip('today', 'Today'),
                const SizedBox(width: 7),
                _filterChip('upcoming', 'Upcoming'),
                const SizedBox(width: 7),
                _filterChip('past', 'Past'),
              ],
            ),
          ),
          if (_canManage && _onlineReady && _pending > 0) ...[
            const SizedBox(height: 10),
            Card(
              color: BriskersColors.appointments.withValues(alpha: 0.07),
              child: ListTile(
                dense: true,
                leading: const Icon(
                  Icons.pending_actions,
                  color: BriskersColors.appointments,
                ),
                title: const Text('Pending customer requests'),
                trailing: Text(
                  '$_pending',
                  style: const TextStyle(
                    color: BriskersColors.appointments,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
          ],
          if (_showingLocal) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: BriskersColors.appointments.withValues(
                  alpha: 0.08,
                ),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Row(
                children: [
                  Icon(Icons.cloud_off_outlined, size: 18),
                  SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Showing saved appointments • check-in can be queued offline',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 10),
          if (_appointments == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (visible.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('No appointments in this view.'),
              ),
            )
          else
            ...visible.map((item) {
              final start =
                  DateTime.tryParse(item['starts_at']?.toString() ?? '')
                      ?.toLocal();
              final make = item['vehicle_make']?.toString() ?? '';
              final year = item['vehicle_year']?.toString() ?? '';
              final model = item['vehicle_model']?.toString() ?? '';
              final vehicle = <String>[year, make, model]
                  .where((value) => value.trim().isNotEmpty)
                  .join(' ');
              final service = item['title']?.toString() ?? '';
              final checking = _checkingInId == item['id']?.toString();

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 0.8,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: (_canManage || _canCheckIn)
                      ? () => _showOptions(item)
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _makeBadge(make),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    start == null
                                        ? '--'
                                        : DateFormat('h:mm a').format(start),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: BriskersColors.appointments,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      item['customer']?.toString() ??
                                          'Appointment',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (vehicle.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  vehicle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              if (service.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  service,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (checking)
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _statusPill(item),
                              const SizedBox(height: 4),
                              const Icon(
                                Icons.chevron_right,
                                size: 20,
                                color: Color(0xFF8A94A3),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
