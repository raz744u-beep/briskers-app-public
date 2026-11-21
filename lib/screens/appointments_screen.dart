import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' show Variable;

import '../local/local_database_provider.dart';

import '../core/briskers_colors.dart';
import '../core/briskers_i18n.dart';
import '../core/connection_mode.dart';
import '../core/navigation_content_timing.dart';
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
    this.repository,
    this.appointmentSync,
    this.api = const BriskersApi(),
    this.visibilityFactory,
  });

  final int dockResetToken;
  final String businessId;
  final String roleCode;
  final LocalAppointmentRepository? repository;
  final AppointmentSyncService? appointmentSync;
  final BriskersApi api;
  final JobSummaryVisibility Function(
    String businessId,
    ValueChanged<Set<String>> onQuarantine,
  )? visibilityFactory;

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  BriskersApi get _api => widget.api;
  // Avoid full remote reload each time the Appointments tab is reopened.
  static final Map<String, DateTime> _lastSuccessfulPull = {};
  static const _entryRefreshInterval = Duration(minutes: 2);
  late final AppointmentSyncService _appointmentSync =
      widget.appointmentSync ?? AppointmentSyncService();
  late final JobSyncService _jobSync = JobSyncService();
  late final LocalAppointmentRepository _localAppointments =
      widget.repository ?? LocalAppointmentRepository();

  late JobSummaryVisibility _jobVisibility;
  List<Map<String, dynamic>>? _appointments;
  String _filter = 'today';
  final TextEditingController _search = TextEditingController();
  String? _error;
  String? _checkingInId;
  int _pending = 0;
  bool _onlineReady = false;
  bool _showingLocal = false;
  bool _refreshFailed = false;
  bool _hasOrphanMock = false;
  int _localLoadGeneration = 0;
  int _connectionGeneration = 0;
  Future<void>? _refreshFuture;
  late final StreamSubscription<String> _syncSubscription;

  bool get _canManage =>
      widget.roleCode == 'owner' ||
      widget.roleCode == 'manager' ||
      widget.roleCode == 'office';

  bool get _canCheckIn =>
      _canManage || widget.roleCode == 'kiosk';

  @override
  void dispose() {
    BriskersConnectionModeController.instance.removeListener(
      _onConnectionModeChanged,
    );
    unawaited(_syncSubscription.cancel());
    _jobVisibility.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _listenForQuarantine();
    _syncSubscription = AppointmentSyncService.syncEvents.listen((businessId) {
      if (mounted && businessId == widget.businessId) {
        unawaited(_loadLocal());
        unawaited(_probeOwnerOrphan());
      }
    });
    BriskersConnectionModeController.instance.addListener(
      _onConnectionModeChanged,
    );
    _load(initialEntry: true);
    unawaited(_probeOwnerOrphan());
  }

  Future<void> _probeOwnerOrphan() async {
    if (widget.roleCode != 'owner') {
      if (mounted) setState(() => _hasOrphanMock = false);
      return;
    }
    final businessId = widget.businessId;
    try {
      final rows = await localDatabase.customSelect(
        "SELECT id FROM local_appointments WHERE business_id=? AND id=? "
        "AND sync_state='pending' LIMIT 1",
        variables: [Variable<String>(businessId),
          const Variable<String>(AppointmentSyncService.orphanMockAppointmentId)],
      ).get();
      if (mounted && widget.businessId == businessId) {
        setState(() => _hasOrphanMock = rows.length == 1);
      }
    } catch (_) {
      // A failed preview must not permit destructive action or block the list.
      if (mounted && widget.businessId == businessId) {
        setState(() => _hasOrphanMock = false);
      }
    }
  }

  void _listenForQuarantine() {
    void onQuarantine(Set<String> jobIds) {
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
    }

    _jobVisibility = widget.visibilityFactory?.call(
          widget.businessId, onQuarantine,
        ) ??
        JobSummaryVisibility(
          businessId: widget.businessId,
          onQuarantine: onQuarantine,
        );
  }

  void _onConnectionModeChanged() {
    final generation = ++_connectionGeneration;
    setState(() {
      _onlineReady = false;
      _refreshFailed = false;
      _showingLocal = _appointments != null;
    });
    if (BriskersConnectionModeController.instance.forceOffline) {
      // A stalled online request must not keep offline cache behind a spinner.
      unawaited(() async {
        await _loadLocal(reportError: true);
        if (!mounted || generation != _connectionGeneration) return;
        setState(() => _appointments ??= const []);
      }());
    }
    // Let a current replay finish before starting another refresh. Changing
    // modes must not dispatch concurrent flushes of the same pending work.
    unawaited(() async {
      final running = _refreshFuture;
      await running;
      if (!mounted || generation != _connectionGeneration) return;
      if (identical(_refreshFuture, running)) _refreshFuture = null;
      await _load();
    }());
  }

  @override
  void didUpdateWidget(covariant AppointmentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId) {
      _jobVisibility.dispose();
      _localLoadGeneration++;
      _refreshFuture = null;
      _appointments = null;
      _pending = 0;
      _onlineReady = false;
      _showingLocal = false;
      _refreshFailed = false;
      _error = null;
      _checkingInId = null;
      _hasOrphanMock = false;
      _listenForQuarantine();
      unawaited(_probeOwnerOrphan());
      _load(initialEntry: true);
    } else if (oldWidget.dockResetToken != widget.dockResetToken) {
      // Tab re-entry keeps the current filter, search and scroll position.
      _load(initialEntry: true);
    }
  }

  Future<bool> _loadLocal({bool reportError = false}) async {
    final visibility = _jobVisibility;
    final generation = visibility.epoch;
    final localGeneration = ++_localLoadGeneration;
    final businessId = widget.businessId;
    final filter = _filter;
    final search = _search.text.trim();
    try {
      final localRows = await visibility.filter(
        await _localAppointments.appointments(
          businessId,
          filter: filter,
          search: search.isEmpty ? null : search,
        ),
        jobIdKey: 'job_id',
      );
      final bootstrapped = await _localAppointments.hasBootstrap(businessId);
      final available = bootstrapped || localRows.isNotEmpty;
      if (mounted && visibility.isCurrent(generation) &&
          localGeneration == _localLoadGeneration &&
          (available || _appointments != null)) {
        setState(() {
          _appointments = localRows;
          if (!bootstrapped) {
            _lastSuccessfulPull.remove(businessId);
            _onlineReady = false;
            _pending = 0;
          }
          _showingLocal = !_onlineReady;
          _error = null;
        });
      }
      return available;
    } catch (error) {
      if (reportError && mounted && visibility.isCurrent(generation) &&
          localGeneration == _localLoadGeneration) {
        setState(() => _error = error.toString());
      }
      return false;
    }
  }

  Future<void> _load({
    bool initialEntry = false,
    bool afterMutation = false,
  }) async {
    final running = _refreshFuture;
    if (running != null) {
      if (!afterMutation) return running;
      final businessId = widget.businessId;
      await _loadLocal(reportError: true);
      await running;
      if (!mounted || businessId != widget.businessId) return;
      // Work queued after the active flush started needs its own replay.
      if (identical(_refreshFuture, running)) _refreshFuture = null;
      return _load();
    }
    final refresh = _refresh(initialEntry: initialEntry);
    _refreshFuture = refresh;
    try {
      await refresh;
    } finally {
      if (identical(_refreshFuture, refresh)) _refreshFuture = null;
    }
  }

  Future<void> _refresh({required bool initialEntry}) async {
    final visibility = _jobVisibility;
    // Query changes have their own generation. They must not discard the
    // result of a background sync, while quarantine/disposal still must.
    final generation = visibility.epoch;
    final businessId = widget.businessId;
    final mode = BriskersConnectionModeController.instance;
    final forceOnline = mode.forceOnline;
    final localAvailable = !forceOnline && await _loadLocal();
    if (!mounted || !visibility.isCurrent(generation)) return;

    if (mode.forceOffline) {
      setState(() {
        _onlineReady = false;
        _showingLocal = localAvailable || _appointments != null;
        _refreshFailed = false;
        _appointments ??= const [];
      });
      return;
    }

    // The old mock's deletion may already be absent on the server. Its
    // tombstone still needs a fresh, Owner-authorized negative existence
    // receipt; a normal check-in refresh never flushes delete operations.
    // Attempt reconciliation before the short no-refresh interval.
    if (widget.roleCode == 'owner') {
      try {
        final retired = await _appointmentSync.reconcileAbsentOrphanMock(
          businessId, isOwner: true,
        );
        if (retired && mounted) {
          unawaited(_probeOwnerOrphan());
          unawaited(_loadLocal(reportError: true));
        }
      } catch (_) {
        // Offline/unsupported server response must leave the delete queue
        // untouched. Never report the appointment deleted on an error.
      }
    }

    final lastPull = _lastSuccessfulPull[businessId];
    if (initialEntry && !forceOnline && localAvailable && lastPull != null &&
        DateTime.now().difference(lastPull) < _entryRefreshInterval) {
      return;
    }

    try {
      final appliedJobs = await _appointmentSync.flush(businessId);
      if (appliedJobs.isNotEmpty) {
        try {
          await _jobSync.pull(businessId);
        } catch (_) {}
      }
      await _appointmentSync.pull(businessId);
      if (!mounted || !visibility.isCurrent(generation)) return;

      // Re-read the latest query, not the query captured before the network
      // request. Saved cards can render before the dashboard count is ready.
      await _loadLocal(reportError: true);
      final bootstrapped = await _localAppointments.hasBootstrap(businessId);
      if (!mounted || !visibility.isCurrent(generation)) return;
      setState(() {
        _lastSuccessfulPull[businessId] = DateTime.now();
        _onlineReady = bootstrapped && !mode.forceOffline;
        _appointments ??= const [];
        _showingLocal = !_onlineReady;
        _refreshFailed = false;
      });

      if (_canManage && !mode.forceOffline) {
        try {
          final dashboard = await _api.dashboard(
            businessId,
            DateFormat('yyyy-MM-dd').format(DateTime.now()),
          );
          if (!mounted || !visibility.isCurrent(generation)) return;
          setState(() {
            _pending = int.tryParse(
                  dashboard['pending_appointment_requests']?.toString() ?? '',
                ) ?? 0;
          });
        } catch (_) {}
      }
    } catch (error) {
      if (!mounted || !visibility.isCurrent(generation)) return;
      setState(() {
        _onlineReady = false;
        _refreshFailed = !mode.forceOffline;
        if (_appointments != null && !forceOnline) {
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
    if (changed == true && mounted) {
      // New/edited appointments have already committed their local snapshot.
      // Update the current list first; do not await replay/pull/dashboard.
      await _loadLocal(reportError: true);
      if (mounted) unawaited(_load(afterMutation: true));
    }
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
    if (changed == true && mounted) {
      // New/edited appointments have already committed their local snapshot.
      // Update the current list first; do not await replay/pull/dashboard.
      await _loadLocal(reportError: true);
      if (mounted) unawaited(_load(afterMutation: true));
    }
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
      await _load(afterMutation: true);
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

  Future<void> _deleteVerifiedOrphanMock(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    if (widget.roleCode != 'owner' ||
        id != AppointmentSyncService.orphanMockAppointmentId) {
      return;
    }
    final ok = await _confirm(
      title: 'Delete orphan test appointment?',
      message: 'This is the disposable mock with missing customer, vehicle '
          'and job links. Remove only its failed appointment edit and queue '
          'a server-verified deletion. No jobs, invoices, payments, '
          'customers or other pending changes will be deleted. '
          'The appointment stays hidden while the server confirms.',
      action: 'Delete test appointment',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await _appointmentSync.queueDeleteVerifiedOrphanMock(
        widget.businessId, id, isOwner: true,
      );
      if (!mounted) return;
      await _loadLocal(reportError: true);
      await _probeOwnerOrphan();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Test appointment hidden; deletion awaiting server confirmation.'),
      ));
      unawaited(_load(afterMutation: true));
    } catch (error) {
      if (mounted) setState(() => _error = 'Test appointment not deleted: $error');
    }
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
      await _load(afterMutation: true);
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
      await _load(afterMutation: true);
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

    final businessId = widget.businessId;
    final visibility = _jobVisibility;
    final generation = visibility.epoch;
    final confirmed = await _confirm(
      title: 'Check in vehicle?',
      message:
          'Briskers will save the check-in on this device immediately. If offline, the linked job will be created when the connection returns.',
      action: 'Check In',
    );
    if (!confirmed || !mounted || !_canCheckIn ||
        widget.businessId != businessId || !visibility.isCurrent(generation)) {
      return;
    }

    final appointmentId = item['id'].toString();
    setState(() => _checkingInId = appointmentId);

    try {
      await _appointmentSync.queueCheckIn(businessId, appointmentId);
      if (!mounted || widget.businessId != businessId ||
          !visibility.isCurrent(generation)) {
        return;
      }

      await _loadLocal(reportError: true);
      if (!mounted || widget.businessId != businessId ||
          !visibility.isCurrent(generation)) {
        return;
      }
      // Use the same serialized refresh as mode changes and manual refreshes.
      // An active replay may already apply this check-in, so recover its Job
      // from the durable row rather than only the next flush's return value.
      await _load(afterMutation: true);
      if (!mounted || widget.businessId != businessId ||
          !visibility.isCurrent(generation)) {
        return;
      }
      final appointment = await _localAppointments.appointment(
        businessId, appointmentId,
      );
      if (!mounted || widget.businessId != businessId ||
          !visibility.isCurrent(generation)) {
        return;
      }
      final visible = await visibility.filter(
        appointment == null ? const [] : [appointment],
        jobIdKey: 'job_id',
      );
      if (!mounted || widget.businessId != businessId ||
          !visibility.isCurrent(generation)) {
        return;
      }
      final local = visible.isEmpty ? null : visible.single;
      final jobId = local != null && local['sync_state'] == 'synced'
          ? local['job_id']?.toString()
          : null;

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
            businessId: businessId,
            jobId: jobId,
            roleCode: widget.roleCode,
          ),
        ),
      );
      if (mounted && widget.businessId == businessId &&
          visibility.isCurrent(generation)) {
        await _load(afterMutation: true);
      }
    } catch (error) {
      if (mounted && widget.businessId == businessId) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && widget.businessId == businessId &&
          _checkingInId == appointmentId) {
        setState(() => _checkingInId = null);
      }
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
            if (widget.roleCode == 'owner' &&
                item['id']?.toString() ==
                    AppointmentSyncService.orphanMockAppointmentId &&
                queued)
              ListTile(
                leading: const Icon(Icons.delete_forever_outlined,
                    color: Colors.red),
                title: const Text('Delete orphan test appointment',
                    style: TextStyle(color: Colors.red)),
                subtitle: const Text('Includes its one stuck edit; protects linked records'),
                onTap: () => Navigator.pop(sheetContext, 'delete_orphan_mock'),
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
      case 'delete_orphan_mock':
        await _deleteVerifiedOrphanMock(item);
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
    // Until local bootstrap or a server pull completes, zero is not a
    // verified appointment count. Do not label an unresolved load Total 0.
    final total = _appointments?.length;
    if (_appointments != null) {
      NavigationContentTiming.contentVisible(
        'appointments',
        context: context,
        source: _showingLocal ? 'local' : 'retained',
      );
    }

    return Stack(
      children: [
        Column(
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
                      '${tr('total')} ${total ?? '—'}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: BriskersColors.appointments,
                                  fontWeight: FontWeight.w700,
                                ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Four compact filters stay on one row. "Today" includes all
                // appointment statuses; confirmed-only remains an internal
                // query for kiosk and other workflows, not a duplicate tab.
                Row(
                  children: [
                    for (final option in const <String>[
                      'today',
                      'upcoming',
                      'past',
                      'all',
                    ])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: ChoiceChip(
                            label: SizedBox(
                              width: double.infinity,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  option == 'today'
                                      ? tr('today')
                                      : option == 'upcoming'
                                          ? tr('upcoming')
                                          : option == 'past'
                                              ? tr('past')
                                              : tr('all'),
                                  maxLines: 1,
                                ),
                              ),
                            ),
                            labelPadding: const EdgeInsets.symmetric(
                              horizontal: 3,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            selected: _filter == option,
                            onSelected: (_) {
                              if (_filter == option) return;
                              setState(() => _filter = option);
                              unawaited(_loadLocal(reportError: true));
                            },
                            selectedColor: BriskersColors.actionBlue
                                .withValues(alpha: 0.16),
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
                        ),
                      ),
                  ],
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
                            _loadLocal(reportError: true);
                          },
                          icon: const Icon(Icons.close),
                        ),
                    ],
                    onChanged: (_) {
                      setState(() {});
                      _loadLocal(reportError: true);
                    },
                  )),

                ]),

              ],
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
              children: [
                if (widget.roleCode == 'owner' && _hasOrphanMock)
                  Card(
                    child: ListTile(
                      key: const ValueKey('owner-orphan-appointment-cleanup'),
                      leading: const Icon(Icons.delete_outline, color: Colors.red),
                      title: const Text('Remove orphan test appointment'),
                      subtitle: const Text('One stuck edit • owner review required'),
                      onTap: () => _deleteVerifiedOrphanMock(const {
                        'id': AppointmentSyncService.orphanMockAppointmentId,
                      }),
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
                        Icon(
                          BriskersConnectionModeController.instance.forceOffline
                              ? Icons.cloud_off_outlined
                              : Icons.storage_outlined,
                          size: 18,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                                child: Text(
                                  BriskersConnectionModeController.instance.forceOffline
                                      ? tr('savedAppointmentsOffline')
                                      : _refreshFailed
                                          ? 'Unable to refresh. Showing saved appointments.'
                                          : 'Showing saved appointments.',
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
                  Card(
                    key: const ValueKey('appointment-awaiting-server'),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        BriskersConnectionModeController.instance.forceOffline
                            ? 'No saved appointments are available offline.'
                            : _refreshFailed
                                ? 'Could not refresh appointments. Pull down to retry.'
                                : 'Checking appointments in the background. No saved list is available yet.',
                      ),
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
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
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
                                    if (_canManage || _canCheckIn) ...[
                                      const SizedBox(height: 3),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          tr('tapForOptions'),
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                      ),
                                    ],
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
        ),
        if (_canManage && MediaQuery.viewInsetsOf(context).bottom == 0)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              heroTag: 'appointments_screen-quick-create',
              tooltip: 'Add appointment',
              onPressed: _addAppointment,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              backgroundColor: BriskersColors.appointments,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('New',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
      ],
    );
  }
}
