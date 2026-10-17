import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' show Variable;

import '../local/local_database_provider.dart';

import '../core/briskers_colors.dart';
import '../core/briskers_i18n.dart';
import '../core/connection_mode.dart';
import '../core/appointment_action_policy.dart';
import '../services/appointment_sync_service.dart';
import '../services/briskers_api.dart';
import '../services/job_sync_service.dart';
import '../services/job_summary_visibility.dart';
import '../services/local_appointment_repository.dart';
import 'appointments/appointment_manage_screen.dart';
import 'jobs/job_detail_screen.dart';

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({
    super.key,
    required this.businessId,
    required this.roleCode,
    this.dockResetToken = 0,
  });

  final int dockResetToken;
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

  late JobSummaryVisibility _jobVisibility;
  List<Map<String, dynamic>>? _appointments;
  String _filter = 'confirmed_today';
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
    _jobVisibility.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _listenForQuarantine();
    _load(initialEntry: true);
  }

  void _listenForQuarantine() {
    _jobVisibility = JobSummaryVisibility(
      businessId: widget.businessId,
      onQuarantine: (jobIds) {
        if (!mounted) return;
        _lastSuccessfulPull.remove(widget.businessId);
        setState(() {
          if (_appointments != null) {
            final hidden = _appointments!.where(
                (row) => jobIds.contains(row['job_id']?.toString()));
            if (hidden.any((row) => row['id']?.toString() == _checkingInId)) {
              _checkingInId = null;
            }
            _appointments = JobSummaryVisibility.withoutJobs(
                _appointments!, jobIds, jobIdKey: 'job_id');
          }
          _onlineReady = false;
          _showingLocal = _appointments != null;
        });
      },
    );
  }

  @override
  void didUpdateWidget(covariant AppointmentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId) {
      _jobVisibility.dispose();
      _appointments = null;
      _pending = 0;
      _onlineReady = false;
      _listenForQuarantine();
      _load(initialEntry: true);
    } else if (oldWidget.dockResetToken != widget.dockResetToken) {
      _filter = 'confirmed_today';
      _search.clear();
      _load(initialEntry: true);
    }
  }

  Future<void> _load({bool initialEntry = false}) async {
    final visibility = _jobVisibility;
    final generation = visibility.beginLoad();
    var localAvailable = false;
    final forceOnline = BriskersConnectionModeController.instance.forceOnline;

    if (!forceOnline) {
      try {
      final localRows = await visibility.filter(
          await _localAppointments.appointments(widget.businessId, filter: _filter, search: _search.text.trim().isEmpty ? null : _search.text.trim()),
          jobIdKey: 'job_id');
      final bootstrapped =
          await _localAppointments.hasBootstrap(widget.businessId);
      localAvailable = bootstrapped || localRows.isNotEmpty;

      if (mounted && localAvailable && visibility.isCurrent(generation)) {
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

    if (!mounted || !visibility.isCurrent(generation)) return;

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
      final localRows = await visibility.filter(
          await _localAppointments.appointments(widget.businessId, filter: _filter, search: _search.text.trim().isEmpty ? null : _search.text.trim()),
          jobIdKey: 'job_id');
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

      if (!mounted || !visibility.isCurrent(generation)) return;
      setState(() {
        _lastSuccessfulPull[widget.businessId] = DateTime.now();
        _appointments = localRows;
        _pending = pending;
        _onlineReady = bootstrapped;
        _showingLocal = !bootstrapped;
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

  Future<void> _repairTestJobJ8(Map<String, dynamic> item) async {
    if (widget.roleCode != 'owner' ||
        item['id']?.toString() != '93356a11-f16a-4939-aaec-db5593273de3' ||
        item['job_id']?.toString() != '21604efd-f7ab-4415-a97f-b9b2b2fbfe61') {
      return;
    }
    const appointmentId = '93356a11-f16a-4939-aaec-db5593273de3';
    const jobId = '21604efd-f7ab-4415-a97f-b9b2b2fbfe61';
    try {
      final result = await localDatabase.transaction<String>(() async {
        final jobs = await localDatabase.customSelect(
          'SELECT job_number, title FROM local_jobs WHERE business_id=? AND id=?',
          variables: [Variable<String>(widget.businessId), const Variable<String>(jobId)],
        ).get();
        final appointments = await localDatabase.customSelect(
          'SELECT job_id FROM local_appointments WHERE business_id=? AND id=?',
          variables: [Variable<String>(widget.businessId), const Variable<String>(appointmentId)],
        ).get();
        if (jobs.length != 1 || appointments.length != 1 ||
            jobs.first.read<String>('job_number') != 'J-8' ||
            appointments.first.readNullable<String>('job_id') != jobId) {
          return 'Local J-8 or appointment does not match expected test records. Nothing changed.';
        }
        final protected = <String, String>{
          'documents': 'SELECT COUNT(*) n FROM local_documents WHERE business_id=? AND job_id=?',
          'pre-inspections': 'SELECT COUNT(*) n FROM local_pre_inspections WHERE business_id=? AND job_id=?',
          'job history': 'SELECT COUNT(*) n FROM local_job_visits WHERE business_id=? AND job_id=?',
        };
        for (final entry in protected.entries) {
          try {
            final rows = await localDatabase.customSelect(entry.value,
              variables: [Variable<String>(widget.businessId), const Variable<String>(jobId)]).get();
            if (rows.single.read<int>('n') > 0) {
              return 'Blocked: J-8 has ${entry.key}. Nothing deleted.';
            }
          } catch (_) {
            return 'Could not verify ${entry.key}; deletion blocked.';
          }
        }
        return 'Inspection passed. No records deleted. Cloud deletion and remaining relationships must be verified before cleanup.';
      });
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (context) => AlertDialog(
        title: const Text('J-8 repair inspection'),
        content: Text(result),
        actions: [TextButton(onPressed: () => Navigator.pop(context),
          child: const Text('Close'))],
      ));
    } catch (error) {
      if (mounted) setState(() => _error = 'J-8 inspection: $error');
    }
  }

  Future<void> _showAppointmentDependencies(Map<String, dynamic> item) async {
    if (widget.roleCode != 'owner') return;
    final jobId = item['job_id']?.toString();
    final requestId = item['request_id']?.toString();
    final id = item['id']?.toString() ?? '';
    final sync = item['sync_state']?.toString() ?? 'synced';

    // Read the phone's SQLite data, not just the cached card snapshot.
    // Inspection is deliberately read-only; financial history is never
    // deleted as a side effect of removing an appointment.
    String jobSummary = 'No job reference';
    String documentSummary = 'Not applicable';
    String queueSummary = 'Unknown';
    String inspectionError = '';
    bool jobFound = false;
    bool inspected = false;
    try {
      final queue = await localDatabase.customSelect(
        'SELECT entity_type, state, attempt_count FROM sync_outbox '
        'WHERE business_id = ? AND entity_id = ?',
        variables: [Variable<String>(widget.businessId), Variable<String>(id)],
      ).get();
      queueSummary = queue.isEmpty
          ? 'No appointment operations queued'
          : queue.map((row) => '${row.read<String>('entity_type')}: '
              '${row.read<String>('state')} '
              '(attempts: ${row.read<int>('attempt_count')})').join('; ');
      if (jobId != null && jobId.isNotEmpty) {
        final jobs = await localDatabase.customSelect(
          'SELECT job_number, title, status FROM local_jobs '
          'WHERE business_id = ? AND id = ? LIMIT 1',
          variables: [
            Variable<String>(widget.businessId), Variable<String>(jobId),
          ],
        ).get();
        jobFound = jobs.isNotEmpty;
        jobSummary = jobFound
            ? 'Found locally: ${jobs.first.readNullable<String>('job_number') ?? '(unnumbered)'} '
              '— ${jobs.first.readNullable<String>('title') ?? '(no title)'} '
              '[${jobs.first.readNullable<String>('status') ?? 'unknown'}]'
            : 'MISSING from local_jobs (orphaned local link possible)';
        final documents = await localDatabase.customSelect(
          'SELECT kind, document_number FROM local_documents '
          'WHERE business_id = ? AND job_id = ?',
          variables: [
            Variable<String>(widget.businessId), Variable<String>(jobId),
          ],
        ).get();
        documentSummary = documents.isEmpty
            ? 'No locally cached documents linked to this job'
            : documents.map((row) =>
                '${row.readNullable<String>('kind') ?? 'document'} '
                '${row.readNullable<String>('document_number') ?? ''}')
              .join(', ');
      }
      inspected = true;
    } catch (error) {
      inspectionError = error.toString();
    }
    if (!mounted) return;
    final linked = (jobId != null && jobId.isNotEmpty) ||
        (requestId != null && requestId.isNotEmpty);
    // Keep the existing no-dependency safe delete path; never infer that
    // a locally missing job is safe to cascade-delete on the server.
    final canTryDelete = inspected && !linked && sync != 'conflict' &&
        (sync == 'synced' || id.startsWith('local-appointment-'));
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Appointment local inspection'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Appointment ID: $id'),
              Text('Sync state: $sync'),
              const SizedBox(height: 12),
              Text('Linked job ID: ${jobId ?? 'none'}'),
              Text('Local job: $jobSummary'),
              Text('Job documents: $documentSummary'),
              Text('Customer request ID: ${requestId ?? 'none'}'),
              Text('Sync queue: $queueSummary'),
              if (inspectionError.isNotEmpty)
                Text('Inspection incomplete: $inspectionError'),
              const SizedBox(height: 12),
              Text(jobFound
                  ? 'This job exists on the device. Do not delete it without '
                    'checking related invoices, payments and service history.'
                  : linked
                      ? 'A dependency is recorded but its linked job may be '
                        'missing locally. This is NOT proof that the server '
                        'has no job. No records will be removed.'
                      : 'No direct job or request links appear in this '
                        'appointment. Server relationships are not verified.'),
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
    if (shouldDelete == true && mounted) await _deleteAppointment(item);
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
            if (widget.roleCode == 'owner' &&
                item['id']?.toString() == '93356a11-f16a-4939-aaec-db5593273de3')
              ListTile(
                leading: const Icon(Icons.rule_folder_outlined),
                title: const Text('Inspect J-8 test cleanup'),
                onTap: () => Navigator.pop(sheetContext, 'repair_j8'),
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
      case 'repair_j8':
        await _repairTestJobJ8(item);
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
                        'confirmed_today',
                        'today',
                        'upcoming',
                        'past',
                        'all',
                      ])
                        ChoiceChip(
                          label: Text(
                            option == 'confirmed_today'
                                ? tr('today')
                                : option == 'today'
                                    ? 'All today'
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
                Row(children: [
                  Expanded(child: SearchBar(
                    controller: _search,
                    hintText: 'Search appointments',
                    leading: const Icon(Icons.search),
                    trailing: [
                      if (_search.text.isNotEmpty)
                        IconButton(
                          tooltip: 'Clear',
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
                  )),
                  const SizedBox(width: 8),
                  if (_canManage)
                    IconButton.filled(
                      tooltip: 'Add appointment',
                      style: IconButton.styleFrom(
                        backgroundColor: BriskersColors.actionBlue,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _addAppointment,
                      icon: const Icon(Icons.add),
                    ),
                ]),

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