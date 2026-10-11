import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/briskers_colors.dart';
import '../core/briskers_i18n.dart';
import '../core/connection_mode.dart';
import '../core/appointment_action_policy.dart';
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
  // Avoid full remote reload each time the Appointments tab is reopened.
  static final Map<String, DateTime> _lastSuccessfulPull = {};
  static const _entryRefreshInterval = Duration(minutes: 2);
  final AppointmentSyncService _appointmentSync =
      AppointmentSyncService();
  final JobSyncService _jobSync = JobSyncService();
  final LocalAppointmentRepository _localAppointments =
      LocalAppointmentRepository();

  List<Map<String, dynamic>>? _appointments;
  String _filter = 'today';
  final TextEditingController _search = TextEditingController();
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
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load(initialEntry: true);
  }

  Future<void> _load({bool initialEntry = false}) async {
    var localAvailable = false;
    final forceOnline = BriskersConnectionModeController.instance.forceOnline;

    if (!forceOnline) {
      try {
      final localRows =
          await _localAppointments.appointments(widget.businessId, filter: _filter, search: _search.text.trim().isEmpty ? null : _search.text.trim());
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
    }

    // Local rows were displayed first. Manual refresh and mutations still sync.
    final lastPull = _lastSuccessfulPull[widget.businessId];
    if (initialEntry && !forceOnline && localAvailable && lastPull != null &&
        DateTime.now().difference(lastPull) < _entryRefreshInterval) {
      return;
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
      _lastSuccessfulPull[widget.businessId] = DateTime.now();
      final localRows =
          await _localAppointments.appointments(widget.businessId, filter: _filter, search: _search.text.trim().isEmpty ? null : _search.text.trim());
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
        if (localAvailable && !forceOnline) {
          _showingLocal = true;
          _error = null;
        } else {
          _appointments ??= const [];
          _error = error.toString();
        }
      });
    }
  }

  List<Map<String, dynamic>> get _visibleAppointments =>
      _appointments ?? const <Map<String, dynamic>>[];

  Future<void> _showDeletionConflicts() async {
    if (widget.roleCode != 'owner') return;
    try {
      final conflicts = await _appointmentSync.deletionConflicts(
        widget.businessId, isOwner: true,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Appointment deletion conflicts'),
          content: SizedBox(
            width: 440,
            child: conflicts.isEmpty
                ? const Text('No unresolved deletion conflicts.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: conflicts.length,
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (_, index) {
                      final conflict = conflicts[index];
                      return ListTile(
                        title: Text(conflict['customer']?.toString() ??
                            conflict['title']?.toString() ?? 'Appointment'),
                        subtitle: Text(
                          'ID: ${conflict['appointment_id']}\n'
                          'Reason: ${conflict['error'] ?? 'Server version changed'}',
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _addAppointment() async {
    if (!_canManage) return;
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
    if (!_canManage) return;
    // A cached appointment remains editable when Auto loses connectivity.
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AppointmentManageScreen(
          businessId: widget.businessId,
          appointment: item,
          isOwner: widget.roleCode == 'owner',
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

  Future<void> _showAppointmentDependencies(Map<String, dynamic> item) async {
    if (widget.roleCode != 'owner') return;
    final job = item['job_id']?.toString();
    final request = item['request_id']?.toString();
    final id = item['id']?.toString() ?? '';
    final sync = item['sync_state']?.toString() ?? 'synced';
    final hasLinks = (job != null && job.isNotEmpty) ||
        (request != null && request.isNotEmpty);
    final canTryDelete = !hasLinks && sync != 'conflict' &&
        (sync == 'synced' || id.startsWith('local-appointment-'));
    if (!mounted) return;
    final delete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Appointment dependencies'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Appointment ID: $id'),
              Text('Sync status: $sync'),
              const SizedBox(height: 10),
              Text(job == null || job.isEmpty
                  ? 'Linked job: none recorded locally'
                  : 'Linked job ID: $job'),
              Text(request == null || request.isEmpty
                  ? 'Customer request: none recorded locally'
                  : 'Customer request ID: $request'),
              const SizedBox(height: 10),
              Text(hasLinks
                  ? 'Deletion is blocked because related records exist. '
                    'Deleting a job could also destroy estimates, invoices, '
                    'payments, and service history. Those records are NOT '
                    'automatically deleted.'
                  : 'No job or request link is recorded in the local '
                    'appointment. Other server-side relationships have not '
                    'been independently verified.'),
              if (!canTryDelete)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Safe deletion is not available in the current '
                      'sync state. Refresh or resolve linked records first.'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Close'),
          ),
          if (canTryDelete)
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete appointment'),
            ),
        ],
      ),
    );
    if (delete == true && mounted) await _deleteAppointment(item);
  }

  Future<void> _deleteAppointment(Map<String, dynamic> item) async {
    if (widget.roleCode != 'owner') return;
    final isPendingCreate = item['id']?.toString().startsWith('local-appointment-') == true;

    final ok = await _confirm(
      title: 'Delete appointment?',
      message:
          'This permanently deletes the appointment. This cannot be undone.',
      action: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    try {
      if (isPendingCreate) {
        await _appointmentSync.deletePendingCreate(widget.businessId,
          item['id'].toString(), isOwner: true);
      } else {
        await _appointmentSync.queueDeleteSynced(
          widget.businessId,item['id'].toString(),isOwner:true,
        );
      }
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _setStatus(
    Map<String, dynamic> item,
    String status,
  ) async {
    if (!_canManage) return;
    try {
      if (status == 'cancelled') {
        if (item['id'].toString().startsWith('local-appointment-')) {
          await _appointmentSync.cancelPendingCreate(
            widget.businessId,item['id'].toString(),canManage:true,
          );
        } else {
          await _appointmentSync.queueCancel(
            widget.businessId, item['id'].toString(),
            canManage: true,
          );
        }
      } else {
        if (!_onlineReady) return;
        await _api.setAppointmentStatus(
          widget.businessId,item['id'].toString(),status,
        );
      }
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
        filter: _filter,
        search: _search.text.trim().isEmpty ? null : _search.text.trim(),
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
    final canEdit = AppointmentActionPolicy.canEdit(
      canManage: _canManage,
      isOwner: widget.roleCode == 'owner',
      linkedJob: item['job_id'] != null,
      status: status,
      conflict: conflict,
    );
    final canCheckIn = _canCheckIn &&
        item['can_check_in'] == true &&
        item['job_id'] == null &&
        !queued && !conflict;
    final canCancel = AppointmentActionPolicy.canCancel(
      canManage: _canManage,
      linkedJob: item['job_id'] != null,
      status: status,
      pending: queued,
      conflict: conflict,
    );
    final canDelete = AppointmentActionPolicy.canDelete(
      isOwner: widget.roleCode == 'owner',
      linkedJob: item['job_id'] != null,
      linkedRequest: item['request_id'] != null,
      pending: queued,
      conflict: conflict,
    );

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
            if (widget.roleCode == 'owner')
              ListTile(
                leading: const Icon(Icons.account_tree_outlined),
                title: const Text('View dependencies / deletion options'),
                onTap: () => Navigator.pop(sheetContext, 'dependencies'),
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
      case 'dependencies':
        await _showAppointmentDependencies(item);
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
        return tr('tentative');
      case 'no_show':
        return tr('noShow');
      case 'arrived':
        return tr('checkedIn');
      case 'finished':
        return tr('finished');
      case 'cancelled':
        return tr('canceled');
      default:
        return tr('confirmed');
    }
  }

  Widget _statusPill(Map<String, dynamic> item) {
    final status = item['status']?.toString() ?? 'confirmed';
    final color = _statusColor(status);
    final locked =
        item['job_id'] != null || {'arrived', 'finished'}.contains(status);
    final canChange = _canManage && _onlineReady && !locked;

    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _statusLabel(status),
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (canChange) ...[
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down,
              size: 17,
              color: color,
            ),
          ],
        ],
      ),
    );

    if (!canChange) return pill;

    return PopupMenuButton<String>(
      tooltip: tr('changeStatus'),
      onSelected: (value) => _setStatus(item, value),
      itemBuilder: (_) => [
        PopupMenuItem(value: 'tentative', child: Text(tr('tentative'))),
        PopupMenuItem(value: 'confirmed', child: Text(tr('confirmed'))),
        PopupMenuItem(value: 'no_show', child: Text(tr('noShow'))),
        PopupMenuItem(value: 'cancelled', child: Text(tr('canceled'))),
      ],
      child: pill,
    );
  }


  @override
  Widget build(BuildContext context) {
    final visible = _visibleAppointments;
    final total = _appointments?.length ?? 0;

    return Column(
      children: [
        Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              children: [
                Row(
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          tr('appointments'),
                          maxLines: 1,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: BriskersColors.appointments,
                              ),
                        ),
                      ),
                    ),
                    if (_canManage) ...[
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: BriskersColors.actionBlue,
                        ),
                        onPressed: _addAppointment,
                        icon: const Icon(Icons.add),
                        label: Text(tr('add')),
                      ),
                    ],
                    if (widget.roleCode == 'owner')
                      IconButton(
                        tooltip: 'Deletion conflicts',
                        onPressed: _showDeletionConflicts,
                        icon: const Icon(Icons.rule_folder_outlined),
                      ),
                    const Spacer(),
                    Text(
                      '${tr('total')} $total',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: BriskersColors.appointments,
                                  fontWeight: FontWeight.w700,
                                ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 7,
                    runSpacing: 6,
                    children: [
                      for (final option in const <String>[
                        'today',
                        'upcoming',
                        'past',
                        'all',
                      ])
                        ChoiceChip(
                          label: Text(
                            option == 'today'
                                ? tr('today')
                                : option == 'upcoming'
                                    ? tr('upcoming')
                                    : option == 'past'
                                        ? tr('past')
                                        : tr('all'),
                          ),
                          selected: _filter == option,
                          onSelected: (_) {
                            if (_filter == option) return;
                            setState(() => _filter = option);
                            _load();
                          },
                          selectedColor:
                              BriskersColors.actionBlue.withValues(alpha: 0.16),
                          side: BorderSide(
                            color: BriskersColors.actionBlue.withValues(
                              alpha: _filter == option ? 0.75 : 0.34,
                            ),
                          ),
                          labelStyle: TextStyle(
                            color: BriskersColors.actionBlue,
                            fontWeight: _filter == option
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SearchBar(
                  controller: _search,
                  hintText: 'Search appointments',
                  leading: const Icon(Icons.search),
                  trailing: [
                    if (_search.text.isNotEmpty)
                      IconButton(
                        onPressed: () {
                                _search.clear();
                                setState(() {});
                                _load();
                        },
                        icon: const Icon(Icons.close),
                      ),
                  ],
                  onChanged: (_) {
                    setState(() {});
                    _load();
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
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 84),
              children: [
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
                      title: Text(tr('pendingCustomerRequests')),
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
                    child: Row(
                      children: [
                        const Icon(Icons.cloud_off_outlined, size: 18),
                        const SizedBox(width: 7),
                        Expanded(
                                child: Text(
                                  tr('savedAppointmentsOffline'),
                                  style: const TextStyle(fontWeight: FontWeight.w700),
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
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(tr('noAppointments')),
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
                         onLongPress: (_canManage || _canCheckIn)
                             ? () => _showOptions(item)
                             : null,
                        child: Padding(
                                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
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
                                      _statusPill(item),
                                  ],
                                ),
                        ),
                      ),
                    );
                  }),

              ],
            ),
          ),
        ),
      ],
    );
  }
}