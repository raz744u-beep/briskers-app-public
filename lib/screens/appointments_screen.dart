import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/briskers_colors.dart';
import '../services/briskers_api.dart';
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
  Map<String, dynamic>? _data;
  String? _error;
  String? _checkingInId;

  bool get _canManage =>
      widget.roleCode == 'owner' ||
      widget.roleCode == 'manager' ||
      widget.roleCode == 'office';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _api.dashboard(
        widget.businessId,
        DateFormat('yyyy-MM-dd').format(DateTime.now()),
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _checkIn(Map<String, dynamic> item) async {
    if (!_canManage) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Check in vehicle?'),
        content: const Text(
          'The appointment will move into Active Jobs and Briskers will create the linked job.',
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

    final appointmentId = item['id'].toString();
    setState(() => _checkingInId = appointmentId);

    try {
      final jobId = await _api.checkInAppointment(
        widget.businessId,
        appointmentId,
      );
      await _load();
      if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    if (_data == null && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final appointments = List<dynamic>.from(
      _data?['appointments'] ?? const [],
    ).map((raw) => Map<String, dynamic>.from(raw as Map)).toList();
    final pending = _data?['pending_appointment_requests'] ?? 0;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Appointments',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: BriskersColors.appointments,
                ),
          ),
          const SizedBox(height: 12),
          if (_canManage)
            Card(
              color: BriskersColors.appointments.withValues(alpha: 0.07),
              child: ListTile(
                leading: const Icon(
                  Icons.pending_actions,
                  color: BriskersColors.appointments,
                ),
                title: const Text('Pending customer requests'),
                trailing: Text(
                  '$pending',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: BriskersColors.appointments,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                subtitle: const Text(
                  'Customer requests waiting for office review',
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            "Today's confirmed appointments",
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (appointments.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('No confirmed appointments scheduled for today.'),
              ),
            ),
          ...appointments.map((item) {
            final start =
                DateTime.tryParse(item['starts_at']?.toString() ?? '');
            final end = DateTime.tryParse(item['ends_at']?.toString() ?? '');
            final time = start == null
                ? ''
                : end == null
                    ? DateFormat('h:mm a').format(start.toLocal())
                    : '${DateFormat('h:mm a').format(start.toLocal())} - '
                        '${DateFormat('h:mm a').format(end.toLocal())}';
            final mechanic = item['mechanic']?.toString() ?? '';
            final checking = _checkingInId == item['id']?.toString();

            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      BriskersColors.appointments.withValues(alpha: 0.14),
                  child: const Icon(
                    Icons.calendar_month,
                    color: BriskersColors.appointments,
                  ),
                ),
                title: Text(
                  item['title']?.toString() ?? 'Appointment',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  <String>[
                    if (time.isNotEmpty) time,
                    item['customer']?.toString() ?? '',
                    if ((item['vehicle']?.toString() ?? '').isNotEmpty)
                      item['vehicle'].toString(),
                    if (mechanic.isNotEmpty) 'Planned: $mechanic',
                  ].where((value) => value.isNotEmpty).join('\n'),
                ),
                isThreeLine: true,
                trailing: _canManage
                    ? checking
                        ? const SizedBox(
                            width: 22,
                            height: 22,
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
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}
