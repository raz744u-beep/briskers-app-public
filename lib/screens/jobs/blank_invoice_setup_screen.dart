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
    this.kind = 'invoice',
    this.initialCustomerId,
    this.initialCustomerName,
    this.initialVehicles = const [],
    this.localCustomers,
    this.api,
  });

  final String businessId;
  final String kind;
  final String? initialCustomerId;
  final String? initialCustomerName;
  final List<dynamic> initialVehicles;
  // Injectable for deterministic offline-first picker regression tests.
  final LocalCustomerRepository? localCustomers;
  final BriskersApi? api;

  @override
  State<BlankInvoiceSetupScreen> createState() =>
      _BlankInvoiceSetupScreenState();
}

class _BlankInvoiceSetupScreenState extends State<BlankInvoiceSetupScreen> {
  BriskersApi get _api => widget.api ?? const BriskersApi();
  OfflineDocumentDraftService get _offlineDrafts => OfflineDocumentDraftService();
  LocalCustomerRepository get _localCustomers =>
      widget.localCustomers ?? LocalCustomerRepository();
  final TextEditingController _customerSearch = TextEditingController();
  Timer? _searchDebounce;
  int _searchGeneration = 0;
  bool _searchingCustomers = false;
  bool _checkingUnsyncedCustomers = false;
  bool _customerCacheIncomplete = false;

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
      // Some customer shortcuts supply an ID/name but not the vehicle list.
      // Required vehicle selection must not strand those shortcuts.
      if (_vehicles.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_loadVehicles(selected));
        });
      }
      _loading = false;
    } else {
      // Customer matches are only shown once a query is entered. Do not
      // load thousands of names before displaying the New Estimate form.
      _loading = false;
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
    // A new query invalidates all prior local and network search results.
    final generation = ++_searchGeneration;
    final term = _customerSearch.text.trim();
    setState(() {
      _customerId = null;
      _vehicleId = null;
      _vehicles = const [];
      _customers = const [];
      _searchingCustomers = term.isNotEmpty;
      _checkingUnsyncedCustomers = false;
      _customerCacheIncomplete = false;
      _error = null;
    });
    if (term.isEmpty) {
      return;
    }
    // Local SQLite is the search source. No arbitrary 350ms delay before the
    // FIRST local result and no network request in the first-frame path.
    // The short coalescing window prevents queueing a DB scan on each key.
    _searchDebounce = Timer(
      const Duration(milliseconds: 60),
      () => unawaited(_loadCustomers(generation, term)),
    );
  }

  Future<void> _loadCustomers(int generation, String term) async {
    try {
      final localMatches = await _localCustomers.customers(
        widget.businessId, search: term, limit: 50,
      );
      if (!mounted || generation != _searchGeneration ||
          term != _customerSearch.text.trim()) {
        return;
      }
      setState(() {
        _customers = localMatches;
        _searchingCustomers = false;
      });
      // An exact local zero is definitive only AFTER this shop's customer
      // bootstrap completed. When incomplete, show the usable local result
      // first and try the network independently; never await it for display.
      if (localMatches.isNotEmpty) {
        return;
      }
      bool bootstrapped = false;
      try {
        bootstrapped = await _localCustomers.hasBootstrap(widget.businessId);
      } catch (_) {
        // Missing local scope is not proof that no customer exists.
      }
      if (!mounted || generation != _searchGeneration ||
          term != _customerSearch.text.trim()) {
        return;
      }
      if (bootstrapped) {
        return;
      }
      setState(() {
        _customerCacheIncomplete = true;
        _checkingUnsyncedCustomers =
            !BriskersConnectionModeController.instance.forceOffline;
      });
      if (_checkingUnsyncedCustomers) {
        unawaited(_searchUnsyncedCustomers(generation, term));
      }
    } catch (_) {
      if (!mounted || generation != _searchGeneration) {
        return;
      }
      setState(() {
        _searchingCustomers = false;
        _customerCacheIncomplete = true;
        _error = 'Saved customer search is unavailable. Check local sync.';
      });
    }
  }

  Future<void> _searchUnsyncedCustomers(int generation, String term) async {
    try {
      final rows = await _api.customers(
        widget.businessId, search: term, limit: 50,
      );
      if (!mounted || generation != _searchGeneration ||
          term != _customerSearch.text.trim() ||
          BriskersConnectionModeController.instance.forceOffline) {
        return;
      }
      setState(() {
        _customers = rows;
        _checkingUnsyncedCustomers = false;
      });
    } catch (_) {
      if (!mounted || generation != _searchGeneration) {
        return;
      }
      // Local selection remains available. Remote outages are informational,
      // not a reason to hold the picker on a spinner.
      setState(() => _checkingUnsyncedCustomers = false);
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
      final localDetail = await _localCustomers.customerDetail(
        widget.businessId, customerId,
      );
      final detail = localDetail != null ||
              BriskersConnectionModeController.instance.forceOffline
          ? localDetail
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
    if (customerId == null || customerId.isEmpty) {
      setState(() => _error = 'Select a customer.');
      return;
    }
    if (_vehicleId == null || _vehicleId!.isEmpty ||
        !_vehicles.any((v) => v['id']?.toString() == _vehicleId)) {
      setState(() => _error = 'Select a vehicle before creating the document.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final isEstimate=widget.kind=='estimate';
      final invoiceId = isEstimate
          ? (BriskersConnectionModeController.instance.forceOffline
              ? await _offlineDrafts.createStandaloneEstimate(
                  widget.businessId,
                  customerId: customerId,
                  customerName: widget.initialCustomerName ??
                      _customers.where((row) => row['id']?.toString() == customerId)
                          .map((row) => row['display_name']?.toString() ??
                              row['name']?.toString() ?? 'Customer')
                          .firstOrNull ?? 'Customer',
                  vehicleId: _vehicleId,
                  vehicleLabel: _vehicles.where((v) =>
                      v['id']?.toString() == _vehicleId).map(_vehicleName).firstOrNull,
                )
              : await _api.createStandaloneEstimate(
                  widget.businessId,customerId:customerId,vehicleId:_vehicleId))
          : BriskersConnectionModeController.instance.forceOffline
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
        backgroundColor: (widget.kind=='estimate'
            ? BriskersColors.estimates : BriskersColors.invoices)
            .withValues(alpha:0.10),
        title: Text(widget.kind=='estimate' ? 'New Estimate' : 'New Invoice'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.kind=='estimate'
                ? 'Choose a customer and vehicle. Both are required before creating an estimate. The estimate does not create a Job until converted to an invoice.'
                : 'Choose a customer and vehicle. Both are required before adding parts, labor, and other invoice items.',
            style: const TextStyle(color: Color(0xFF667085)),
          ),
          const SizedBox(height: 16),
          if (widget.initialCustomerId == null) ...[
            TextField(
              controller: _customerSearch,
              enabled: !_saving,
              onChanged: _onCustomerSearch,
              decoration: InputDecoration(
                labelText: 'Customer',
                hintText: 'Start typing name, phone, or email',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _customerSearch.text.isEmpty ? null
                    : IconButton(
                        tooltip: 'Clear customer',
                        onPressed: () {
                          _customerSearch.clear();
                          _onCustomerSearch('');
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
            if (_searchingCustomers) const LinearProgressIndicator(),
            if (!_searchingCustomers && _customerId == null &&
                _customerSearch.text.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: _customers.isEmpty
                    ? Text(_checkingUnsyncedCustomers
                        ? 'Checking customers not yet downloaded…'
                        : _customerCacheIncomplete
                            ? 'No saved matches. Customer sync needs attention.'
                            : 'No matching customers.')
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _customers.length,
                        itemBuilder: (context, index) {
                          final customer = _customers[index];
                          final id = customer['id']?.toString() ?? '';
                          final name = customer['display_name']?.toString() ??
                              customer['name']?.toString() ?? 'Customer';
                          return ListTile(
                            title: Text(name),
                            onTap: _saving || id.isEmpty ? null : () {
                              setState(() {
                                _customerId = id;
                                _customerSearch.text = name;
                              });
                              _loadVehicles(id);
                            },
                          );
                        },
                      ),
              ),
          ] else
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Customer'),
              subtitle: Text(widget.initialCustomerName ?? 'Customer'),
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
          if (_customerId != null && _vehicles.isEmpty && !_loadingVehicles)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('No saved vehicle for this customer. Add the vehicle to the customer profile before creating this document.'),
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
              backgroundColor: widget.kind=='estimate'
                  ? BriskersColors.estimates : BriskersColors.invoices,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _saving || _loadingVehicles || _customerId == null ||
                    _vehicleId == null || _vehicleId!.isEmpty
                ? null : _create,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.receipt_long_outlined),
            label: Text(widget.kind=='estimate'
                ? 'Create Estimate & Add Items' : 'Create Invoice & Add Items'),
          ),
        ],
      ),
    );
  }
}
