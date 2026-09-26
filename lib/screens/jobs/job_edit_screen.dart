import 'package:flutter/material.dart';

import '../../core/briskers_colors.dart';
import '../../services/briskers_api.dart';

class JobEditScreen extends StatefulWidget {
  const JobEditScreen({
    super.key,
    required this.businessId,
    required this.job,
  });

  final String businessId;
  final Map<String, dynamic> job;

  @override
  State<JobEditScreen> createState() => _JobEditScreenState();
}

class _JobEditScreenState extends State<JobEditScreen> {
  static const _api = BriskersApi();

  late final TextEditingController _title;
  late final TextEditingController _requestedWork;
  late final TextEditingController _plannedHours;

  List<Map<String, dynamic>> _customers = const [];
  List<Map<String, dynamic>> _vehicles = const [];

  late String _customerId;
  String? _vehicleId;

  bool _loading = true;
  bool _loadingVehicles = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(
      text: widget.job['title']?.toString() ?? '',
    );
    _requestedWork = TextEditingController(
      text: widget.job['requested_work']?.toString() ?? '',
    );
    _plannedHours = TextEditingController(
      text: widget.job['planned_hours']?.toString() ?? '0',
    );
    _customerId = widget.job['customer_id']?.toString() ?? '';
    _vehicleId = widget.job['vehicle_id']?.toString();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _requestedWork.dispose();
    _plannedHours.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final customers = await _api.customers(
        widget.businessId,
        limit: 200,
      );
      final vehicles = await _vehiclesForCustomer(_customerId);

      if (!mounted) return;
      setState(() {
        _customers = customers;
        _vehicles = vehicles;
        _loading = false;
        _error = null;

        if (_vehicleId != null &&
            !_vehicles.any((vehicle) => vehicle['id']?.toString() == _vehicleId)) {
          _vehicleId = null;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<List<Map<String, dynamic>>> _vehiclesForCustomer(
    String customerId,
  ) async {
    final detail = await _api.customerDetail(
      widget.businessId,
      customerId,
    );
    return List<dynamic>.from(detail['vehicles'] ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
  }

  Future<void> _changeCustomer(String customerId) async {
    if (customerId == _customerId || _loadingVehicles) return;

    setState(() {
      _customerId = customerId;
      _vehicleId = null;
      _vehicles = const [];
      _loadingVehicles = true;
      _error = null;
    });

    try {
      final vehicles = await _vehiclesForCustomer(customerId);
      if (!mounted) return;
      setState(() {
        _vehicles = vehicles;
        _vehicleId =
            vehicles.length == 1 ? vehicles.first['id']?.toString() : null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loadingVehicles = false);
    }
  }

  String _customerName(Map<String, dynamic> customer) {
    return customer['display_name']?.toString().trim() ?? '';
  }

  String _vehicleName(Map<String, dynamic> vehicle) {
    final name = <String>[
      if (vehicle['year'] != null) vehicle['year'].toString(),
      vehicle['make']?.toString().trim() ?? '',
      vehicle['model']?.toString().trim() ?? '',
    ].where((part) => part.isNotEmpty).join(' ');

    final plate = vehicle['license_plate']?.toString().trim() ?? '';
    return plate.isEmpty ? name : '$name • $plate';
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final plannedHours = num.tryParse(_plannedHours.text.trim());

    if (_customerId.isEmpty) {
      setState(() => _error = 'Select a customer.');
      return;
    }
    if (title.isEmpty) {
      setState(() => _error = 'Job title is required.');
      return;
    }
    if (plannedHours == null || plannedHours < 0) {
      setState(() => _error = 'Enter a valid planned time.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _api.updateJob(
        widget.businessId,
        widget.job['id'].toString(),
        customerId: _customerId,
        vehicleId: _vehicleId,
        title: title,
        requestedWork: _requestedWork.text.trim().isEmpty
            ? null
            : _requestedWork.text.trim(),
        plannedHours: plannedHours,
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
    return Scaffold(
      appBar: AppBar(
        backgroundColor: BriskersColors.jobs.withValues(alpha: 0.10),
        title: const Text('Edit job'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _customers.any(
                    (customer) => customer['id']?.toString() == _customerId,
                  )
                      ? _customerId
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Customer',
                    prefixIcon: Icon(
                      Icons.person_outline,
                      color: BriskersColors.customers,
                    ),
                  ),
                  items: _customers
                      .map(
                        (customer) => DropdownMenuItem<String>(
                          value: customer['id']?.toString(),
                          child: Text(
                            _customerName(customer),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) _changeCustomer(value);
                        },
                ),
                const SizedBox(height: 12),
                if (_loadingVehicles)
                  const LinearProgressIndicator()
                else
                  DropdownButtonFormField<String?>(
                    key: ValueKey('vehicle-$_customerId'),
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
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _vehicleId = value),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _title,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Job title',
                    prefixIcon: Icon(
                      Icons.build_outlined,
                      color: BriskersColors.jobs,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _requestedWork,
                  enabled: !_saving,
                  minLines: 3,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Requested work / complaint',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _plannedHours,
                  enabled: !_saving,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Planned / assigned time',
                    suffixText: 'hours',
                    prefixIcon: Icon(
                      Icons.timer_outlined,
                      color: BriskersColors.jobs,
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: BriskersColors.jobs,
                  ),
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Saving...' : 'Save changes'),
                ),
              ],
            ),
    );
  }
}
