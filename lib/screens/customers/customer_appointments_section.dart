import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/briskers_colors.dart';
import '../../core/connection_mode.dart';
import '../../services/briskers_api.dart';
import '../../services/customer_detail_cache.dart';

class CustomerAppointmentsSection extends StatefulWidget {
  const CustomerAppointmentsSection({
    super.key,
    required this.businessId,
    required this.customerId,
  });

  final String businessId;
  final String customerId;

  @override
  State<CustomerAppointmentsSection> createState() =>
      _CustomerAppointmentsSectionState();
}

class _CustomerAppointmentsSectionState
    extends State<CustomerAppointmentsSection> {
  static const _api = BriskersApi();
  static const _cache = CustomerDetailCache();

  List<Map<String, dynamic>> _appointments = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final offline = BriskersConnectionModeController.instance.forceOffline;
    if (offline) {
      final cached = await _cache.load(
        widget.businessId,
        widget.customerId,
        'appointments',
      );
      final rows = cached is List
          ? cached
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _appointments = rows;
        _loading = false;
        _error = null;
      });
      return;
    }

    try {
      final rows = await _api.customerAppointments(
        widget.businessId,
        widget.customerId,
      );
      await _cache.save(
        widget.businessId,
        widget.customerId,
        'appointments',
        rows,
      );
      if (!mounted) return;
      setState(() {
        _appointments = rows;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      final cached = await _cache.load(
        widget.businessId,
        widget.customerId,
        'appointments',
      );
      final rows = cached is List
          ? cached
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _appointments = rows;
        _loading = false;
        _error = rows.isEmpty ? error.toString() : null;
      });
    }
  }

  String _statusLabel(Object? raw) {
    final value = raw?.toString().replaceAll('_', ' ') ?? '';
    if (value.isEmpty) return '';
    return value[0].toUpperCase() + value.substring(1);
  }

  String _dateTime(Object? raw) {
    final date = DateTime.tryParse(raw?.toString() ?? '');
    if (date == null) return 'Appointment';
    return DateFormat('EEE, MMM d • h:mm a').format(date.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final next = _appointments.isEmpty ? null : _appointments.first;

    return Card(
      child: ExpansionTile(
        initiallyExpanded: false,
        maintainState: false,
        leading: const Icon(
          Icons.calendar_month_outlined,
          color: BriskersColors.appointments,
        ),
        title: const Text(
          'Appointments',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: _loading
            ? const Text('Loading appointments...')
            : next == null
                ? const Text('No upcoming appointments')
                : Text(_dateTime(next['starts_at'])),
        children: [
          const Divider(height: 1),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            )
          else if (_appointments.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('No confirmed or arrived appointments.'),
              ),
            )
          else
            ..._appointments.map((item) {
              final vehicle = '${item['vehicle'] ?? ''}'.trim();
              final title = '${item['title'] ?? ''}'.trim();
              final employee = '${item['employee'] ?? ''}'.trim();
              final status = _statusLabel(item['status']);
              final subtitle = <String>[
                if (vehicle.isNotEmpty) vehicle,
                if (title.isNotEmpty) title,
                if (employee.isNotEmpty) 'Assigned to $employee',
                if (status.isNotEmpty) status,
              ].join('\n');

              return ListTile(
                leading: const Icon(
                  Icons.event_available_outlined,
                  color: BriskersColors.appointments,
                ),
                title: Text(_dateTime(item['starts_at'])),
                subtitle: subtitle.isEmpty ? null : Text(subtitle),
                isThreeLine: subtitle.split('\n').length > 1,
              );
            }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
