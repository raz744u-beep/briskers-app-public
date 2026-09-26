import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/briskers_colors.dart';
import '../../services/briskers_api.dart';

class AppointmentCreateScreen extends StatefulWidget {
  const AppointmentCreateScreen({
    super.key,
    required this.businessId,
    required this.customerId,
    required this.customerName,
    required this.vehicles,
  });

  final String businessId;
  final String customerId;
  final String customerName;
  final List<dynamic> vehicles;

  @override
  State<AppointmentCreateScreen> createState() =>
      _AppointmentCreateScreenState();
}

class _AppointmentCreateScreenState extends State<AppointmentCreateScreen> {
  static const _api = BriskersApi();

  final _title = TextEditingController(text: 'Service appointment');
  final _description = TextEditingController();

  List<Map<String, dynamic>> _employees = const [];
  String? _vehicleId;
  String? _employeeId;
  DateTime _startsAt = _nextHour();
  int _durationMinutes = 60;
  bool _loadingEmployees = true;
  bool _saving = false;
  String? _error;

  static DateTime _nextHour() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, now.hour + 1);
  }

  @override
  void initState() {
    super.initState();
    if (widget.vehicles.length == 1) {
      final only = Map<String, dynamic>.from(widget.vehicles.first as Map);
      _vehicleId = only['id']?.toString();
    }
    _loadEmployees();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    try {
      final rows = await _api.assignableEmployees(widget.businessId);
      if (!mounted) return;
      setState(() {
        _employees = rows;
        _loadingEmployees = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingEmployees = false);
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
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
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
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Appointment title is required.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _api.createAppointment(
        widget.businessId,
        customerId: widget.customerId,
        vehicleId: _vehicleId,
        title: title,
        description:
            _description.text.trim().isEmpty ? null : _description.text.trim(),
        startsAt: _startsAt,
        endsAt: _startsAt.add(Duration(minutes: _durationMinutes)),
        employeeId: _employeeId,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehicles = widget.vehicles
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: BriskersColors.appointments.withValues(alpha: 0.10),
        title: const Text('Schedule appointment'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: BriskersColors.customers.withValues(alpha: 0.08),
            child: ListTile(
              leading: const Icon(
                Icons.person_outline,
                color: BriskersColors.customers,
              ),
              title: Text(
                widget.customerName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Customer'),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
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
              ...vehicles.map(
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
                  icon: const Icon(
                    Icons.event_outlined,
                    color: BriskersColors.appointments,
                  ),
                  label: Text(DateFormat('EEE, MMM d').format(_startsAt)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(
                    Icons.schedule_outlined,
                    color: BriskersColors.appointments,
                  ),
                  label: Text(DateFormat('h:mm a').format(_startsAt)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _durationMinutes,
            decoration: const InputDecoration(
              labelText: 'Appointment length',
            ),
            items: const [
              DropdownMenuItem(value: 30, child: Text('30 minutes')),
              DropdownMenuItem(value: 60, child: Text('1 hour')),
              DropdownMenuItem(value: 90, child: Text('1.5 hours')),
              DropdownMenuItem(value: 120, child: Text('2 hours')),
              DropdownMenuItem(value: 180, child: Text('3 hours')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _durationMinutes = value);
            },
          ),
          const SizedBox(height: 12),
          if (_loadingEmployees)
            const LinearProgressIndicator()
          else
            DropdownButtonFormField<String?>(
              initialValue: _employeeId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Planned mechanic (optional)',
                helperText:
                    'If selected, the mechanic carries over when the car checks in.',
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
                : const Icon(Icons.event_available_outlined),
            label: Text(_saving ? 'Scheduling...' : 'Schedule appointment'),
          ),
        ],
      ),
    );
  }
}
