import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/briskers_colors.dart';
import '../../services/briskers_api.dart';

class AppointmentManageScreen extends StatefulWidget {
  const AppointmentManageScreen({
    super.key,
    required this.businessId,
    this.appointment,
  });

  final String businessId;
  final Map<String, dynamic>? appointment;

  @override
  State<AppointmentManageScreen> createState() =>
      _AppointmentManageScreenState();
}

class _AppointmentManageScreenState extends State<AppointmentManageScreen> {
  static const _api = BriskersApi();

  final _title = TextEditingController(text: 'Service appointment');
  final _description = TextEditingController();

  List<Map<String, dynamic>> _customers = const [];
  List<Map<String, dynamic>> _vehicles = const [];
  List<Map<String, dynamic>> _employees = const [];

  String? _customerId;
  String? _vehicleId;
  String? _employeeId;
  late DateTime _startsAt;
  int _durationMinutes = 60;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.appointment != null;

  @override
  void initState() {
    super.initState();
    final appointment = widget.appointment;
    final parsedStart =
        DateTime.tryParse(appointment?['starts_at']?.toString() ?? '');
    final parsedEnd =
        DateTime.tryParse(appointment?['ends_at']?.toString() ?? '');
    final now = DateTime.now();
    _startsAt = parsedStart?.toLocal() ??
        DateTime(now.year, now.month, now.day, now.hour + 1);
    if (parsedStart != null && parsedEnd != null) {
      final minutes = parsedEnd.difference(parsedStart).inMinutes;
      if ([30, 60, 90, 120, 180].contains(minutes)) {
        _durationMinutes = minutes;
      }
    }
    if (appointment != null) {
      _customerId = appointment['customer_id']?.toString();
      _vehicleId = appointment['vehicle_id']?.toString();
      _employeeId = appointment['employee_id']?.toString();
      _title.text = appointment['title']?.toString() ?? 'Service appointment';
      _description.text = appointment['description']?.toString() ?? '';
    }
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<dynamic>([
        _api.customers(widget.businessId, limit: 100),
        _api.assignableEmployees(widget.businessId),
      ]);
      final customers = List<Map<String, dynamic>>.from(results[0] as List);
      final employees = List<Map<String, dynamic>>.from(results[1] as List);

      if (_editing &&
          _customerId != null &&
          !customers.any((c) => c['id']?.toString() == _customerId)) {
        customers.add({
          'id': _customerId,
          'display_name':
              widget.appointment?['customer']?.toString() ?? 'Customer',
        });
      }

      if (_customerId != null) {
        await _loadVehicles(_customerId!, updateState: false);
      }

      if (!mounted) return;
      setState(() {
        _customers = customers;
        _employees = employees;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadVehicles(
    String customerId, {
    bool updateState = true,
  }) async {
    try {
      final data = await _api.customerDetail(widget.businessId, customerId);
      final rows = List<dynamic>.from(data['vehicles'] ?? const [])
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
      if (!mounted) return;
      if (updateState) {
        setState(() {
          _vehicles = rows;
          if (!_vehicles.any((v) => v['id']?.toString() == _vehicleId)) {
            _vehicleId = null;
          }
        });
      } else {
        _vehicles = rows;
      }
    } catch (_) {
      if (updateState && mounted) {
        setState(() {
          _vehicles = const [];
          _vehicleId = null;
        });
      }
    }
  }

  String _vehicleName(Map<String, dynamic> vehicle) {
    return <String>[
      if (vehicle['year'] != null) '${vehicle['year']}',
      '${vehicle['make'] ?? ''}'.trim(),
      '${vehicle['model'] ?? ''}'.trim(),
    ].where((part) => part.isNotEmpty).join(' ');
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startsAt,
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) return;
    setState(() {
      _startsAt = DateTime(
        date.year,
        date.month,
        date.day,
        _startsAt.hour,
        _startsAt.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startsAt),
    );
    if (time == null || !mounted) return;
    setState(() {
      _startsAt = DateTime(
        _startsAt.year,
        _startsAt.month,
        _startsAt.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _save() async {
    final customerId = _customerId;
    final title = _title.text.trim();
    if (customerId == null) {
      setState(() => _error = 'Customer is required.');
      return;
    }
    if (title.isEmpty) {
      setState(() => _error = 'Appointment title is required.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final endsAt = _startsAt.add(Duration(minutes: _durationMinutes));
      if (_editing) {
        await _api.updateAppointment(
          widget.businessId,
          widget.appointment!['id'].toString(),
          customerId: customerId,
          vehicleId: _vehicleId,
          title: title,
          description:
              _description.text.trim().isEmpty ? null : _description.text.trim(),
          startsAt: _startsAt,
          endsAt: endsAt,
          employeeId: _employeeId,
        );
      } else {
        await _api.createAppointment(
          widget.businessId,
          customerId: customerId,
          vehicleId: _vehicleId,
          title: title,
          description:
              _description.text.trim().isEmpty ? null : _description.text.trim(),
          startsAt: _startsAt,
          endsAt: endsAt,
          employeeId: _employeeId,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: BriskersColors.appointments.withValues(alpha: 0.10),
        title: Text(_editing ? 'Edit appointment' : 'Add appointment'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _customerId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Customer',
              prefixIcon: Icon(Icons.person_outline),
            ),
            items: _customers
                .map(
                  (customer) => DropdownMenuItem<String>(
                    value: customer['id']?.toString(),
                    child: Text(
                      customer['display_name']?.toString() ??
                          customer['name']?.toString() ??
                          'Customer',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) async {
              setState(() {
                _customerId = value;
                _vehicleId = null;
                _vehicles = const [];
              });
              if (value != null) await _loadVehicles(value);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            key: ValueKey('vehicle-$_customerId-$_vehicleId'),
            initialValue: _vehicleId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Vehicle',
              prefixIcon: Icon(
                Icons.directions_car_outlined,
                color: BriskersColors.vehicles,
              ),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('No vehicle selected'),
              ),
              ..._vehicles.map(
                (vehicle) => DropdownMenuItem<String?>(
                  value: vehicle['id']?.toString(),
                  child: Text(
                    _vehicleName(vehicle),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: (value) => setState(() => _vehicleId = value),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Appointment title',
              prefixIcon: Icon(
                Icons.calendar_month_outlined,
                color: BriskersColors.appointments,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            minLines: 3,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Customer complaint / requested work',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(DateFormat('EEE, MMM d').format(_startsAt)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.schedule_outlined),
                  label: Text(DateFormat('h:mm a').format(_startsAt)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _employeeId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Planned mechanic (optional)',
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Unassigned'),
              ),
              ..._employees.map(
                (employee) => DropdownMenuItem<String?>(
                  value: employee['id']?.toString(),
                  child: Text(
                    '${employee['name'] ?? ''} — '
                    '${employee['position_name'] ?? 'Employee'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: (value) => setState(() => _employeeId = value),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: BriskersColors.appointments,
            ),
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(
              _saving
                  ? 'Saving...'
                  : (_editing ? 'Update appointment' : 'Save appointment'),
            ),
          ),
        ],
      ),
    );
  }
}
