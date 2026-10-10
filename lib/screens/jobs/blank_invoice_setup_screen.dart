import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/briskers_colors.dart';
import '../../services/briskers_api.dart';
import '../../core/connection_mode.dart';
import '../../services/offline_document_draft_service.dart';
import '../../services/local_customer_repository.dart';

class BlankInvoiceSetupScreen extends StatefulWidget {
  const BlankInvoiceSetupScreen({
    super.key,
    required this.businessId,
    this.initialCustomerId,
    this.initialCustomerName,
    this.initialVehicles = const [],
  });

  final String businessId;
  final String? initialCustomerId;
  final String? initialCustomerName;
  final List<dynamic> initialVehicles;

  @override
  State<BlankInvoiceSetupScreen> createState() =>
      _BlankInvoiceSetupScreenState();
}

class _BlankInvoiceSetupScreenState extends State<BlankInvoiceSetupScreen> {
  static const _api = BriskersApi();
  OfflineDocumentDraftService get _offlineDrafts => OfflineDocumentDraftService();
  LocalCustomerRepository get _localCustomers => LocalCustomerRepository();
  final TextEditingController _customerSearch = TextEditingController();
  Timer? _searchDebounce;
  int _searchGeneration = 0;
  int _customerDropdownVersion = 0;
  bool _searchingCustomers = false;

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
    final selected = widget.initialCustomerId;
    if (selected != null) {
      _customerId = selected;
      _customers = [
        <String, dynamic>{
          'id': selected,
          'display_name': widget.initialCustomerName ?? 'Customer',
        },
      ];
      _vehicles = widget.initialVehicles
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .toList();
      if (_vehicles.length == 1) {
        _vehicleId = _vehicles.first['id']?.toString();
      }
      _loading = false;
    } else {
      _loadCustomers();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _customerSearch.dispose();
    super.dispose();
  }

  void _onCustomerSearch(String _) {
    _searchDebounce?.cancel();
    // Discard responses from any prior query before the debounce fires.
    _searchGeneration++;
    setState(() {
      _customerDropdownVersion++;
      _customerId = null;
      _vehicleId = null;
      _vehicles = const [];
      _customers = const [];
      _searchingCustomers = true;
      _error = null;
    });
    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      _loadCustomers,
    );
  }

  Future<void> _loadCustomers() async {
    final generation = ++_searchGeneration;
    final term = _customerSearch.text.trim();
    try {
      final customers = BriskersConnectionModeController.instance.forceOffline
          ? await _localCustomers.customers(
              widget.businessId, search: term.isEmpty ? null : term,
            )
          : await _api.customers(
              widget.businessId,
              search: term.isEmpty ? null : term,
              limit: 75,
            );
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _customers = customers;
        _loading = false;
        _searchingCustomers = false;
      });
    } catch (error) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _loading = false;
        _searchingCustomers = false;
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
      final detail = BriskersConnectionModeController.instance.forceOffline
          ? await _localCustomers.customerDetail(widget.businessId, customerId)
          : await _api.customerDetail(widget.businessId, customerId);
      final vehicles = List<dynamic>.from(detail?['vehicles'] ?? const [])
          .whereType<Map>()
          .map((raw) => Map<String, dynamic>.from(raw))
          .toList();
      if (!mounted || _customerId != customerId) return;
      setState(() {
        _vehicles = vehicles;
        if (_vehicles.length == 1) {
          _vehicleId = _vehicles.first['id']?.toString();
        }
        _loadingVehicles = false;
      });
    } catch (error) {
      if (!mounted || _customerId != customerId) return;
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
      final invoiceId = BriskersConnectionModeController.instance.forceOffline
          ? await _offlineDrafts.createQuickInvoice(
              widget.businessId,
              customerId: customerId,
              customerName: widget.initialCustomerName ??
                  _customers.where((row) => row['id']?.toString() == customerId)
                      .map((row) => row['display_name']?.toString() ??
                          row['name']?.toString() ?? 'Customer')
                      .firstOrNull ?? 'Customer',
              vehicleId: _vehicleId,
              vehicleLabel: _vehicles.where((v) => v['id']?.toString() == _vehicleId)
                  .map(_vehicleName).firstOrNull,
            )
          : await _api.createQuickInvoice(
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
        title: const Text('New Invoice'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Choose a customer and optional vehicle. After creating the invoice, you can add parts, labor, and other items.',
            style: TextStyle(color: Color(0xFF667085)),
          ),
          const SizedBox(height: 16),
          if (widget.initialCustomerId == null)
          TextField(
            controller: _customerSearch,
            enabled: !_saving,
            onChanged: _onCustomerSearch,
            decoration: InputDecoration(
              labelText: 'Find customer',
              hintText: 'Search by name, phone or email',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _customerSearch.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _customerSearch.clear();
                        _onCustomerSearch('');
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          if (widget.initialCustomerId != null)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Customer'),
              subtitle: Text(widget.initialCustomerName ?? 'Customer'),
            ),
          if (widget.initialCustomerId == null && _searchingCustomers)
            const LinearProgressIndicator()
          else if (widget.initialCustomerId == null && _customers.isEmpty)
            const Text('No matching customers. Try another search.'),
          if (widget.initialCustomerId == null && !_searchingCustomers && _customers.isNotEmpty)
          DropdownButtonFormField<String>(
            key: ValueKey(_customerDropdownVersion),
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
              key: ValueKey(_customerId),
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
            label: const Text('Create Invoice & Add Items'),
          ),
        ],
      ),
    );
  }
}
