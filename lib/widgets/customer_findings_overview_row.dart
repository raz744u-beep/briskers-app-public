import 'dart:async';

import 'package:flutter/material.dart';

import '../core/connection_mode.dart';
import '../services/customer_finding_overview_service.dart';
import '../services/vehicle_finding_actions_service.dart';
import '../services/local_job_quarantine.dart';
import '../services/local_job_retirement.dart';

/// Tappable customer-wide findings shortcut. Counts are independent from
/// Jobs and are not limited to the latest repair; all accessible linked
/// vehicle findings are included once, even after they were resolved.
class CustomerFindingsOverviewRow extends StatefulWidget {
  const CustomerFindingsOverviewRow({
    super.key,
    required this.businessId,
    required this.customerId,
    required this.vehicles,
    required this.onOpen,
    this.service,
  });

  final String businessId;
  final String customerId;
  final List<dynamic> vehicles;
  final Future<void> Function() onOpen;
  final CustomerFindingOverviewService? service;

  @override
  State<CustomerFindingsOverviewRow> createState() =>
      _CustomerFindingsOverviewRowState();
}

class _CustomerFindingsOverviewRowState
    extends State<CustomerFindingsOverviewRow> {
  late Future<CustomerFindingCounts> _counts;
  CustomerFindingCounts? _lastCounts;
  int _refreshEpoch = 0;
  int _visibilityEpoch = 0;
  StreamSubscription<String>? _changes;
  StreamSubscription<({String businessId, Set<String> jobIds})>?
      _quarantine;
  StreamSubscription<({String businessId, Set<String> jobIds})>?
      _retirements;

  String _vehicleIds(List<dynamic> vehicles) {
    final ids = vehicles.whereType<Map>()
        .map((vehicle) => vehicle['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty).toList()..sort();
    return ids.join('|');
  }

  @override
  void initState() {
    super.initState();
    _refresh();
    _changes = VehicleFindingActionsService.changes.listen((businessId) {
      if (businessId == widget.businessId && mounted) _refresh();
    });
    // A revoked Job or finding identity must be removed from the summary,
    // even if it was visible in an earlier cached customer snapshot.
    _quarantine = LocalJobQuarantine.events.listen((event) {
      if (event.businessId == widget.businessId && mounted) {
        _lastCounts = null;
        ++_visibilityEpoch;
        _refresh();
      }
    });
    _retirements = LocalJobRetirement.events.listen((event) {
      if (event.businessId == widget.businessId && mounted) {
        _lastCounts = null;
        ++_visibilityEpoch;
        _refresh();
      }
    });
  }

  @override
  void didUpdateWidget(covariant CustomerFindingsOverviewRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId ||
        oldWidget.customerId != widget.customerId ||
        _vehicleIds(oldWidget.vehicles) != _vehicleIds(widget.vehicles)) {
      // Counts from a different customer/vehicle scope must never flash while
      // the replacement authorization-filtered local lookup is pending.
      _lastCounts = null;
      ++_visibilityEpoch;
      _refresh();
    }
  }

  void _refresh() {
    final epoch = ++_refreshEpoch;
    final service = widget.service ?? CustomerFindingOverviewService();
    final businessId = widget.businessId;
    final customerId = widget.customerId;
    final vehicles = widget.vehicles;

    // Force Online is an explicit diagnostic choice. In ordinary Auto and
    // Force Offline, never bind the first-frame count to a network request.
    final localFirst =
        !BriskersConnectionModeController.instance.forceOnline;
    final first = service.load(
      businessId: businessId,
      customerId: customerId,
      vehicles: vehicles,
      localOnly: localFirst,
    );
    setState(() { _counts = first; });

    if (!localFirst) return;
    unawaited(() async {
      try {
        final local = await first;
        if (!mounted || epoch != _refreshEpoch) return;
        setState(() => _lastCounts = local);
      } catch (_) {
        // A missing trusted local snapshot is unknown, not a count of zero.
        // Continue best-effort Auto refresh without erasing prior values.
      }
      if (!mounted || epoch != _refreshEpoch ||
          BriskersConnectionModeController.instance.forceOffline) {
        return;
      }

      try {
        final updated = await service.load(
          businessId: businessId,
          customerId: customerId,
          vehicles: vehicles,
        );
        if (!mounted || epoch != _refreshEpoch) return;
        setState(() {
          _lastCounts = updated;
          _counts = Future<CustomerFindingCounts>.value(updated);
        });
      } catch (_) {
        // Keep verified local/previous counts and a tappable retry path.
        // Never replace a useful count with a failed remote Future.
      }
    }());
  }

  @override
  void dispose() {
    ++_refreshEpoch;
    _changes?.cancel();
    _quarantine?.cancel();
    _retirements?.cancel();
    super.dispose();
  }

  Future<void> _open() async {
    await widget.onOpen();
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CustomerFindingCounts>(
      // A FutureBuilder ordinarily retains prior data when its Future changes.
      // Reset across account, vehicle scope or quarantine changes rather than
      // flashing a now-inaccessible customer's finding counts.
      key: ValueKey((widget.businessId, widget.customerId,
          _vehicleIds(widget.vehicles), _visibilityEpoch)),
      future: _counts,
      builder: (context, snapshot) {
        final counts = snapshot.data ?? _lastCounts;
        final subtitle = counts == null
            ? (snapshot.hasError
                ? 'Counts unavailable — tap to view'
                : 'Checking saved vehicle findings...')
            : 'Open ${counts.open} • In Job ${counts.inJob} '
                '• Resolved ${counts.resolved}';
        return ListTile(
          key: const ValueKey('customer-overview-vehicle-findings'),
          dense: true,
          visualDensity: VisualDensity.compact,
          leading: const Icon(Icons.car_repair_outlined,
              color: Colors.deepOrange, size: 25),
          title: const Text('Vehicle Findings',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          subtitle: Text(subtitle,
              style: const TextStyle(fontSize: 12),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (counts != null)
                Text('${counts.total}',
                    key: const ValueKey('customer-findings-total'),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800))
              else
                const Text('—'),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
          onTap: _open,
        );
      },
    );
  }
}
