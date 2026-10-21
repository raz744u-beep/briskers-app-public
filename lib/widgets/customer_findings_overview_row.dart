import 'dart:async';

import 'package:flutter/material.dart';

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
      if (event.businessId == widget.businessId && mounted) _refresh();
    });
    _retirements = LocalJobRetirement.events.listen((event) {
      if (event.businessId == widget.businessId && mounted) _refresh();
    });
  }

  @override
  void didUpdateWidget(covariant CustomerFindingsOverviewRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId ||
        oldWidget.customerId != widget.customerId ||
        _vehicleIds(oldWidget.vehicles) != _vehicleIds(widget.vehicles)) {
      _refresh();
    }
  }

  void _refresh() {
    final work = (widget.service ?? CustomerFindingOverviewService()).load(
      businessId: widget.businessId,
      customerId: widget.customerId,
      vehicles: widget.vehicles,
    );
    if (mounted) setState(() => _counts = work);
  }

  @override
  void dispose() {
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
      future: _counts,
      builder: (context, snapshot) {
        final counts = snapshot.data;
        final subtitle = counts == null
            ? (snapshot.hasError
                ? 'Counts unavailable — tap to view'
                : 'Checking all customer vehicles...')
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
              else if (!snapshot.hasError)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
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
