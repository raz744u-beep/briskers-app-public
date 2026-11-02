import 'dart:async';

import 'package:flutter/material.dart';

import '../core/connection_mode.dart';
import '../services/appointment_sync_service.dart';
import '../services/customer_vehicle_sync_service.dart';
import '../services/document_index_sync_service.dart';
import '../services/job_sync_service.dart';
import '../services/local_sync_status_repository.dart';

/// Compact shell-header control. Displays the selected preference separately
/// from the most recent successful local data pull (not an invented sync state).
class ConnectionHeaderToggle extends StatefulWidget {
  const ConnectionHeaderToggle({
    super.key,
    required this.businessId,
    this.statusRepository,
  });
  final String businessId;
  final LocalSyncStatusRepository? statusRepository;

  @override
  State<ConnectionHeaderToggle> createState() => _ConnectionHeaderToggleState();
}

class _ConnectionHeaderToggleState extends State<ConnectionHeaderToggle>
    with WidgetsBindingObserver {
  final _controller = BriskersConnectionModeController.instance;
  late LocalSyncStatusRepository _repository;
  LocalSyncStatusSnapshot? _snapshot;
  bool _statusUnavailable = false;
  int _refreshGeneration = 0;
  Timer? _refreshTimer;
  final _subscriptions = <StreamSubscription<String>>[];

  @override
  void initState() {
    super.initState();
    _repository = widget.statusRepository ?? LocalSyncStatusRepository();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_modeChanged);
    for (final events in [
      JobSyncService.syncEvents,
      CustomerVehicleSyncService.syncEvents,
      AppointmentSyncService.syncEvents,
      DocumentIndexSyncService.syncEvents,
      LocalSyncStatusRepository.refreshEvents,
    ]) {
      _subscriptions.add(events.listen((businessId) {
        if (businessId == widget.businessId) unawaited(_refreshTimestamp());
      }));
    }
    _startTimer();
  }

  void _startTimer() {
    _refreshTimer?.cancel();
    // Also observe scopes without broadcast events and age the relative label.
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_refreshTimestamp());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route visibility changes, including returning from Settings.
    ModalRoute.of(context);
    unawaited(_refreshTimestamp());
  }

  @override
  void didUpdateWidget(covariant ConnectionHeaderToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.statusRepository != widget.statusRepository) {
      _repository = widget.statusRepository ?? LocalSyncStatusRepository();
    }
    if (oldWidget.businessId != widget.businessId ||
        oldWidget.statusRepository != widget.statusRepository) {
      _snapshot = null;
      _statusUnavailable = false;
    }
    // The shell keeps this State while navigating between bottom tabs.
    unawaited(_refreshTimestamp());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTimer();
      unawaited(_refreshTimestamp());
    } else {
      _refreshTimer?.cancel();
    }
  }

  void _modeChanged() {
    if (mounted) setState(() {});
    unawaited(_refreshTimestamp());
  }

  Future<void> _refreshTimestamp() async {
    final generation = ++_refreshGeneration;
    try {
      final snapshot = await _repository.load(widget.businessId);
      if (!mounted || generation != _refreshGeneration) return;
      setState(() {
        _snapshot = snapshot;
        _statusUnavailable = false;
      });
    } catch (_) {
      if (!mounted || generation != _refreshGeneration) return;
      setState(() => _statusUnavailable = true);
    }
  }

  String get _lastLabel {
    if (_statusUnavailable) return 'Sync status unavailable';
    if (_snapshot == null) return 'Checking sync…';
    final value = _snapshot?.lastSuccessfulPull;
    if (value == null) return 'Not yet synced';
    final elapsed = DateTime.now().difference(value);
    if (elapsed.isNegative || elapsed.inMinutes < 1) return 'Last sync: just now';
    if (elapsed.inMinutes < 60) return 'Last sync: ${elapsed.inMinutes}m ago';
    if (elapsed.inHours < 24) return 'Last sync: ${elapsed.inHours}h ago';
    return 'Last sync: ${value.toLocal().month}/${value.toLocal().day}';
  }

  @override
  void dispose() {
    _controller.removeListener(_modeChanged);
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = _controller.mode;
    final icon = mode == BriskersConnectionMode.offline
        ? Icons.wifi_off_rounded
        : mode == BriskersConnectionMode.online
            ? Icons.cloud_outlined : Icons.wifi_rounded;
    final color = mode == BriskersConnectionMode.offline
        ? const Color(0xFFC62828)
        : mode == BriskersConnectionMode.online
            ? const Color(0xFF1767AD) : const Color(0xFF008B80);
    final label = switch (mode) {
      BriskersConnectionMode.auto => 'Auto',
      BriskersConnectionMode.offline => 'Offline',
      BriskersConnectionMode.online => 'Online',
    };

    final issues = _snapshot?.issues ?? const <String>[];
    final pending = _snapshot?.pendingUploads ?? 0;
    return SizedBox(
      width: 114,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PopupMenuButton<BriskersConnectionMode>(
            tooltip: 'Connection mode',
            onOpened: _refreshTimestamp,
            onSelected: (next) async {
              await _controller.setMode(next);
              await _refreshTimestamp();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: BriskersConnectionMode.auto,
                child: Text('Auto'),
              ),
              PopupMenuItem(
                value: BriskersConnectionMode.offline,
                child: Text('Force Offline'),
              ),
              PopupMenuItem(
                value: BriskersConnectionMode.online,
                child: Text('Force Online'),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: color),
                color: color.withValues(alpha: 0.06),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: color, size: 17),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                  const Icon(Icons.keyboard_arrow_down, size: 15),
                ],
              ),
            ),
          ),
          const SizedBox(height: 3),
          Tooltip(
            message: _statusUnavailable
                ? 'Unable to verify sync status. Check Local database & sync.'
                : 'Latest successful download, not a guarantee of full sync.'
                  '${issues.isEmpty ? '' : '\n${issues.join('\n')}'}',
            child: Column(
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(_lastLabel,
                    maxLines: 1,
                    style: const TextStyle(fontSize: 10, color: Color(0xFF687481))),
                ),
                if (!_statusUnavailable && (issues.isNotEmpty || pending > 0))
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      issues.isNotEmpty ? 'Sync needs attention' : '$pending pending upload(s)',
                      key: const ValueKey('sync-header-attention'),
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 10,
                        color: issues.isNotEmpty ? const Color(0xFFC62828) : const Color(0xFF687481),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
