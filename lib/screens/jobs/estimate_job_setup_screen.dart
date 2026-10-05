import 'package:flutter/material.dart';

import '../../core/briskers_colors.dart';
import '../../services/briskers_api.dart';

class EstimateJobSetupScreen extends StatefulWidget {
  const EstimateJobSetupScreen({
    super.key,
    required this.businessId,
  });

  final String businessId;

  @override
  State<EstimateJobSetupScreen> createState() => _EstimateJobSetupScreenState();
}

class _EstimateJobSetupScreenState extends State<EstimateJobSetupScreen> {
  static const _api = BriskersApi();

  final TextEditingController _title = TextEditingController();

  List<Map<String, dynamic>> _customers = const [];
  List<Map<String, dynamic>> _vehicles = const [];
  String? _customerId;
  String? _vehicleId;
  bool _loading = true;
  bool _loadingVehicles = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    try {
      final customers = await _api.customers(widget.businessId, limit: 200);
      if (!mounted) return;
      setState(() {
        _customers = customers;
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

  Future<void> _loadVehicles(String customerId) async {
    setState(() {
      _loadingVehicles = true;
      _vehicles = const [];
      _vehicleId = null;
      _error = null;
    });

    try {
      final detail = await _api.customerDetail(widget.businessId, customerId);
      final vehicles = List<dynamic>.from(detail['vehicles'] ?? const [])
          .whereType<Map>()
          .map((raw) => Map<String, dynamic>.from(raw))
          .toList();
      if (!mounted) return;
      setState(() {
        _vehicles = vehicles;
        _loadingVehicles = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingVehicles = false;
        _error = error.toString();
      });
    }
  }

  String _customerName(String? customerId) {
    for (final customer in _customers) {
      if (customer['id']?.toString() == customerId) {
        return customer['display_name']?.toString() ??
            customer['name']?.toString() ??
            'Customer';
      }
    }
    return 'Customer';
  }

  String _vehicleName(Map<String, dynamic> vehicle) {
    return <String>[
      if (vehicle['year'] != null) vehicle['year'].toString(),
      vehicle['make']?.toString().trim() ?? '',
      vehicle['model']?.toString().trim() ?? '',
    ].where((part) => part.isNotEmpty).join(' ');
  }

  Future<void> _save() async {
    final customerId = _customerId;
    final vehicleId = _vehicleId;
    final title = _title.text.trim();

    if (customerId == null) {
      setState(() => _error = 'Select a customer.');
      return;
    }
    if (vehicleId == null) {
      setState(() => _error = 'Select a vehicle.');
      return;
    }
    if (title.isEmpty) {
      setState(() => _error = 'Enter a brief job title.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final jobId = await _api.createJob(
        widget.businessId,
        customerId: customerId,
        vehicleId: vehicleId,
        title: title,
        description: 'Estimate preparation',
      );

      try {
        await _api.changeJobStatus(
          widget.businessId,
          jobId,
          'pending_approval',
          note: 'Job created for estimate preparation.',
        );
      } catch (error) {
        throw Exception(
          'The job was created, but Briskers could not set it to Pending approval. $error',
        );
      }

      final vehicle = _vehicles.firstWhere(
        (item) => item['id']?.toString() == vehicleId,
        orElse: () => const <String, dynamic>{},
      );

      if (!mounted) return;
      Navigator.pop<Map<String, dynamic>>(
        context,
        {
          'id': jobId,
          'customer_name': _customerName(customerId),
          'vehicle': _vehicleName(vehicle),
          'vehicle_id': vehicleId,
          'title': title,
          'status': 'pending_approval',
        },
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
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
        backgroundColor: BriskersColors.estimates.withValues(alpha: 0.10),
        title: const Text('Create Job for Estimate'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'This creates a lightweight Job in Pending approval so the estimate stays linked to the customer and vehicle.',
            style: TextStyle(color: Color(0xFF667085)),
          ),
          const SizedBox(height: 16),
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
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: _saving
                ? null
                : (value) {
                    setState(() => _customerId = value);
                    if (value != null) _loadVehicles(value);
                  },
          ),
          const SizedBox(height: 12),
          if (_loadingVehicles)
            const LinearProgressIndicator()
          else
            DropdownButtonFormField<String>(
              initialValue: _vehicleId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Vehicle',
                prefixIcon: Icon(Icons.directions_car_outlined),
              ),
              items: _vehicles
                  .map(
                    (vehicle) => DropdownMenuItem<String>(
                      value: vehicle['id']?.toString(),
                      child: Text(
                        _vehicleName(vehicle),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _vehicleId = value),
            ),
          if (_customerId != null &&
              !_loadingVehicles &&
              _vehicles.isEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'This customer has no vehicle yet. Add the vehicle from Customers first.',
              style: TextStyle(color: Colors.orange),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            enabled: !_saving,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Brief job title',
              hintText: 'Example: Front suspension estimate',
              prefixIcon: Icon(Icons.edit_note_outlined),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 22),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: BriskersColors.estimates,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.arrow_forward),
            label: const Text('Create Job & Continue'),
          ),
        ],
      ),
    );
  }
}
