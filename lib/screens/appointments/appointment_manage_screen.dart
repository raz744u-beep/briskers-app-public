import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/briskers_colors.dart';
import '../../core/appointment_action_policy.dart';
import '../../core/connection_mode.dart';
import '../../services/appointment_sync_service.dart';
import '../../services/local_customer_repository.dart';
import '../../services/briskers_api.dart';

class AppointmentManageScreen extends StatefulWidget {
  const AppointmentManageScreen({
    super.key,
    required this.businessId,
    this.appointment,
    this.isOwner = false,
    this.localCustomers,
    this.api,
  });

  final String businessId;
  final Map<String, dynamic>? appointment;
  final bool isOwner;
  // Optional test seams; production always uses its local cache and API.
  final LocalCustomerRepository? localCustomers;
  final BriskersApi? api;

  @override
  State<AppointmentManageScreen> createState() =>
      _AppointmentManageScreenState();
}

class _AppointmentManageScreenState extends State<AppointmentManageScreen> {
  BriskersApi get _api => widget.api ?? const BriskersApi();
  late final AppointmentSyncService _sync = AppointmentSyncService();
  LocalCustomerRepository get _localCustomers =>
      widget.localCustomers ?? LocalCustomerRepository();
  bool get _pendingCreate => widget.appointment?['id']
          ?.toString().startsWith('local-appointment-') == true;
  // Existing appointments are always edited locally first in Auto mode too.
  bool get _offlineEditing => _editing;

  final _title = TextEditingController(text: 'Service appointment');
  final _description = TextEditingController();
  final _customerSearch = TextEditingController();
  Timer? _customerDebounce;
  int _customerSearchEpoch = 0;
  bool _customerSearching = false;
  bool _loadingVehicles = false;

  List<Map<String, dynamic>> _customers = const [];
  List<Map<String, dynamic>> _vehicles = const [];
  List<Map<String, dynamic>> _employees = const [];

  String? _customerId;
  String? _vehicleId;
  String? _employeeId;
  late DateTime _startsAt;
  int _durationMinutes = 60;
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
      _customerSearch.text = appointment['customer']?.toString() ??
          appointment['customer_name']?.toString() ?? '';
    }
    _load();
  }

  @override
  void dispose() {
    _customerDebounce?.cancel();
    _customerSearchEpoch++;
    _customerSearch.dispose();
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  // New appointment must open immediately. Never hydrate 2,799 customers
  // or wait for employee/network requests just to display the form.
  void _load() {
    final item = widget.appointment ?? const <String, dynamic>{};
    if (_employeeId != null) {
      _employees = [{
        'id': _employeeId,
        'name': item['mechanic'] ?? 'Assigned',
        'position_name': 'Employee',
      }];
    }
    if (_editing && item['job_id'] != null && _vehicleId != null) {
      _vehicles = [{
        'id': _vehicleId, 'year': item['vehicle_year'],
        'make': item['vehicle_make'], 'model': item['vehicle_model'],
      }];
    } else if (_customerId != null) {
      unawaited(_loadVehiclesForCustomer(_customerId!));
    }
    if (!BriskersConnectionModeController.instance.forceOffline) {
      unawaited(_loadEmployeesInBackground());
    }
  }

  Future<void> _loadEmployeesInBackground() async {
    try {
      final rows = List<Map<String, dynamic>>.from(
        await _api.assignableEmployees(widget.businessId)
            .timeout(const Duration(seconds: 8)),
      );
      if (!mounted) return;
      final selected = _employeeId;
      if (selected != null &&
          !rows.any((row) => row['id']?.toString() == selected)) {
        rows.addAll(_employees.where(
          (row) => row['id']?.toString() == selected));
      }
      setState(() => _employees = rows);
    } catch (_) {
      // The optional mechanic list may be unavailable; never block scheduling.
    }
  }

  void _onCustomerSearchChanged(String value) {
    _customerDebounce?.cancel();
    final generation = ++_customerSearchEpoch;
    final query = value.trim();
    setState(() {
      _customerId = null;
      _vehicleId = null;
      _vehicles = const [];
      _customers = const [];
      _customerSearching = query.isNotEmpty;
      _error = null;
    });
    if (query.isEmpty) return;
    _customerDebounce = Timer(const Duration(milliseconds: 60), () {
      unawaited(_searchCustomers(generation, query));
    });
  }

  Future<void> _searchCustomers(int generation, String query) async {
    bool current() => mounted && generation == _customerSearchEpoch &&
        _customerSearch.text.trim() == query && _customerId == null;
    try {
      // Limit results and never read the entire shop customer table.
      final local = await _localCustomers.customers(
        widget.businessId, search: query, limit: 40);
      if (!current()) return;
      setState(() {
        _customers = local;
        _customerSearching = false;
      });
      if (local.isNotEmpty ||
          BriskersConnectionModeController.instance.forceOffline) {
        return;
      }
      // A missing local result is definitive only after customer bootstrap.
      if (await _localCustomers.hasBootstrap(widget.businessId)) return;
      if (!current()) return;
      final remote = await _api.customers(
        widget.businessId, search: query, limit: 40)
          .timeout(const Duration(seconds: 8));
      if (!current() ||
          BriskersConnectionModeController.instance.forceOffline) {
        return;
      }
      setState(() => _customers = remote);
    } catch (_) {
      if (current()) setState(() => _customerSearching = false);
    }
  }

  void _selectCustomer(Map<String, dynamic> customer) {
    final id = customer['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final name = customer['display_name']?.toString() ??
        customer['name']?.toString() ?? 'Customer';
    _customerDebounce?.cancel();
    _customerSearchEpoch++;
    setState(() {
      _customerId = id;
      _customerSearch.text = name;
      _customers = const [];
      _customerSearching = false;
      _vehicleId = null;
      _vehicles = const [];
    });
    unawaited(_loadVehiclesForCustomer(id));
  }

  Future<void> _loadVehiclesForCustomer(String customerId) async {
    if (!mounted || _customerId != customerId) return;
    setState(() => _loadingVehicles = true);
    try {
      final local = await _localCustomers.customerDetail(
        widget.businessId, customerId);
      // Local-first: network fetch only when this customer's detail is missing.
      final detail = local ?? (BriskersConnectionModeController.instance.forceOffline
          ? null : await _api.customerDetail(widget.businessId, customerId)
              .timeout(const Duration(seconds: 8)));
      if (!mounted || _customerId != customerId) return;
      final vehicles = List<dynamic>.from(detail?['vehicles'] ?? const [])
          .whereType<Map>()
          .map((raw) => Map<String, dynamic>.from(raw)).toList();
      setState(() {
        _vehicles = vehicles;
        if (!vehicles.any((row) => row['id']?.toString() == _vehicleId)) {
          _vehicleId = vehicles.length == 1
              ? vehicles.single['id']?.toString() : null;
        }
      });
    } catch (_) {
      // Keep the form, customer selection and any saved vehicle usable.
    } finally {
      if (mounted && _customerId == customerId) {
        setState(() => _loadingVehicles = false);
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
    if (_editing && !AppointmentActionPolicy.canEdit(
      canManage: true,
      isOwner: widget.isOwner,
      linkedJob: widget.appointment?['job_id'] != null,
      status: widget.appointment?['status']?.toString() ?? '',
      conflict: widget.appointment?['sync_state'] == 'conflict',
    )) {
      setState(() => _error = 'This appointment cannot be edited with your permissions.');
      return;
    }
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
      if (!_editing) {
        await _sync.queueCreate(widget.businessId,
          customerId: customerId,vehicleId: _vehicleId,
          title: title,
          description: _description.text.trim().isEmpty
              ? null : _description.text.trim(),
          startsAt: _startsAt,endsAt: endsAt,employeeId: _employeeId,
        );
      } else if (_offlineEditing) {
        if (_pendingCreate && (customerId != widget.appointment!['customer_id']?.toString() ||
            _vehicleId != widget.appointment!['vehicle_id']?.toString())) {
          await _sync.reassignPendingCreate(widget.businessId,
            widget.appointment!['id'].toString(),
            customerId: customerId,vehicleId: _vehicleId);
        }
        await _sync.queueEdit(
          widget.businessId, widget.appointment!['id'].toString(),
          title: title,
          description: _description.text.trim().isEmpty ? null : _description.text.trim(),
          startsAt: _startsAt, endsAt: endsAt,
          employeeId: _employeeId,
          customerId: _pendingCreate ? null : customerId,
          vehicleId: _vehicleId,
          isOwner: widget.isOwner,
        );
      } else if (_editing) {
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
    return Scaffold(
      appBar: AppBar(
        backgroundColor: BriskersColors.appointments.withValues(alpha: 0.10),
        title: Text(_editing ? 'Edit appointment' : 'Add appointment'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_editing && widget.appointment?['job_id'] != null)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(_customerSearch.text.isEmpty
                  ? 'Customer' : _customerSearch.text),
              subtitle: const Text('Customer (linked to Job)'),
            )
          else ...[
            TextField(
              key: const ValueKey('appointment-customer-search'),
              controller: _customerSearch,
              onChanged: _onCustomerSearchChanged,
              decoration: InputDecoration(
                labelText: 'Customer',
                hintText: 'Search name, phone, or email',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _customerSearch.text.isEmpty ? null : IconButton(
                  key: const ValueKey('appointment-customer-clear'),
                  tooltip: 'Clear customer',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _customerSearch.clear();
                    _onCustomerSearchChanged('');
                  },
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            if (_customerSearching) const LinearProgressIndicator(),
            if (_customerId == null && _customerSearch.text.trim().isNotEmpty &&
                !_customerSearching)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 250),
                child: _customers.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('No matching saved customers.'),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _customers.length,
                        itemBuilder: (context, index) {
                          final customer = _customers[index];
                          final label = customer['display_name']?.toString() ??
                              customer['name']?.toString() ?? 'Customer';
                          return ListTile(
                            key: ValueKey('appointment-customer-$index'),
                            title: Text(label),
                            onTap: () => _selectCustomer(customer),
                          );
                        },
                      ),
              ),
          ],
          const SizedBox(height: 12),
          if (_loadingVehicles) const LinearProgressIndicator(),
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
            onChanged: _loadingVehicles ||
                    (_editing && widget.appointment?['job_id'] != null)
                ? null : (value) => setState(() => _vehicleId = value),
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
