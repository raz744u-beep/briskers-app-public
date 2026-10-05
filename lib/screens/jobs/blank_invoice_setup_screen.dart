import 'package:flutter/material.dart';

import '../../core/briskers_colors.dart';
import '../../services/briskers_api.dart';

class BlankInvoiceSetupScreen extends StatefulWidget {
  const BlankInvoiceSetupScreen({
    super.key,
    required this.businessId,
  });

  final String businessId;

  @override
  State<BlankInvoiceSetupScreen> createState() =>
      _BlankInvoiceSetupScreenState();
}

class _BlankInvoiceSetupScreenState extends State<BlankInvoiceSetupScreen> {
  static const _api = BriskersApi();

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
        if (_vehicles.length == 1) {
          _vehicleId = _vehicles.first['id']?.toString();
        }
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

  String _vehicleName(Map<String, dynamic> vehicle) {
    return <String>[
      if (vehicle['year'] != null) vehicle['year'].toString(),
      vehicle['make']?.toString().trim() ?? '',
      vehicle['model']?.toString().trim() ?? '',
    ].where((part) => part.isNotEmpty).join(' ');
  }

  Future<void> _create() async {
    final customerId = _customerId;
    if (customerId == null) {
      setState(() => _error = 'Select a customer.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final invoiceId = await _api.createQuickInvoice(
        widget.businessId,
        customerId: customerId,
        vehicleId: _vehicleId,
      );
      if (!mounted) return;
      Navigator.pop<String>(context, invoiceId);
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
        backgroundColor: BriskersColors.invoices.withValues(alpha: 0.10),
        title: const Text('New Blank Invoice'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Create an invoice without an existing Job. Select the customer and, if applicable, a vehicle.',
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
            DropdownButtonFormField<String?>(
              initialValue: _vehicleId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Vehicle',
                prefixIcon: Icon(Icons.directions_car_outlined),
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
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _vehicleId = value),
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
              backgroundColor: BriskersColors.invoices,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _saving ? null : _create,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.receipt_long_outlined),
            label: const Text('Create Invoice'),
          ),
        ],
      ),
    );
  }
}
