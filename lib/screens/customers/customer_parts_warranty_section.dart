import 'package:flutter/material.dart';

import '../../services/briskers_api.dart';

class CustomerPartsWarrantySection extends StatefulWidget {
  const CustomerPartsWarrantySection({
    super.key,
    required this.businessId,
    required this.customerId,
    required this.vehicles,
  });

  final String businessId;
  final String customerId;
  final List<dynamic> vehicles;

  @override
  State<CustomerPartsWarrantySection> createState() =>
      _CustomerPartsWarrantySectionState();
}

class _CustomerPartsWarrantySectionState
    extends State<CustomerPartsWarrantySection> {
  static const _api = BriskersApi();

  final TextEditingController _search = TextEditingController();

  bool _checkingPermission = true;
  bool _allowed = false;
  bool _loading = false;
  String? _vehicleId;
  String? _error;
  List<Map<String, dynamic>> _results = const [];

  @override
  void initState() {
    super.initState();
    _loadPermission();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadPermission() async {
    try {
      final permissions = await _api.myPermissions(widget.businessId);
      if (!mounted) return;
      setState(() {
        _allowed = permissions.contains('invoices.read') &&
            permissions.contains('expenses.read');
        _checkingPermission = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _allowed = false;
        _checkingPermission = false;
      });
    }
  }

  Future<void> _runSearch() async {
    final query = _search.text.trim();
    if (query.length < 2 || _loading) {
      if (query.isNotEmpty && query.length < 2) {
        setState(() {
          _error = 'Enter at least 2 characters.';
        });
      }
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await _api.customerPartsWarrantySearch(
        widget.businessId,
        widget.customerId,
        query,
        vehicleId: _vehicleId,
      );
      if (!mounted) return;
      setState(() {
        _results = rows;
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

  String _vehicleLabel(Map<String, dynamic> vehicle) {
    return <String>[
      if (vehicle['year'] != null) vehicle['year'].toString(),
      vehicle['make']?.toString().trim() ?? '',
      vehicle['model']?.toString().trim() ?? '',
    ].where((value) => value.isNotEmpty).join(' ');
  }

  Future<void> _openReceipt(
    Map<String, dynamic> attachment,
  ) async {
    final bucket = attachment['bucket']?.toString() ?? '';
    final key = attachment['key']?.toString() ?? '';
    if (bucket.isEmpty || key.isEmpty) return;

    try {
      final url = await _api.signedAttachmentUrl(bucket, key);
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierColor: Colors.black87,
        builder: (dialogContext) => Dialog(
          insetPadding: const EdgeInsets.all(12),
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 0.7,
                  maxScale: 5,
                  child: Center(
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white70,
                        size: 56,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 6,
                top: 6,
                child: IconButton.filled(
                  onPressed: () => Navigator.pop(dialogContext),
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    }
  }

  Widget _resultCard(Map<String, dynamic> result) {
    final receiptLinks = List<dynamic>.from(
      result['receipt_links'] ?? const <dynamic>[],
    )
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .toList();

    final invoice = result['invoice_number']?.toString() ?? '';
    final invoiceDate = result['invoice_date']?.toString() ?? '';
    final vehicle = result['vehicle']?.toString().trim() ?? '';
    final jobNumber = result['job_number']?.toString().trim() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result['line_name']?.toString() ?? 'Invoice item',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            if ((result['line_description']?.toString().trim() ?? '')
                .isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(result['line_description'].toString()),
            ],
            const SizedBox(height: 8),
            Text(
              <String>[
                if (invoice.isNotEmpty) 'Invoice #$invoice',
                if (invoiceDate.isNotEmpty) invoiceDate,
                if (jobNumber.isNotEmpty) 'Job $jobNumber',
                if (vehicle.isNotEmpty) vehicle,
              ].join(' • '),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Divider(height: 22),
            if (receiptLinks.isEmpty)
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 19),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This item is on the customer invoice, but a vendor receipt has not been linked yet.',
                    ),
                  ),
                ],
              )
            else
              ...receiptLinks.map((receipt) {
                final vendor =
                    receipt['vendor']?.toString() ?? 'Vendor';
                final vendorInvoice =
                    receipt['vendor_invoice_number']?.toString() ?? '';
                final date =
                    receipt['receipt_date']?.toString() ?? '';
                final itemDescription =
                    receipt['receipt_item_description']?.toString() ?? '';
                final attachments = List<dynamic>.from(
                  receipt['attachments'] ?? const <dynamic>[],
                )
                    .whereType<Map>()
                    .map((raw) => Map<String, dynamic>.from(raw))
                    .toList();

                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.receipt_long_outlined),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              vendor,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (itemDescription.isNotEmpty)
                              Text(itemDescription),
                            Text(
                              <String>[
                                if (vendorInvoice.isNotEmpty)
                                  'Vendor invoice $vendorInvoice',
                                if (date.isNotEmpty) date,
                              ].join(' • '),
                            ),
                          ],
                        ),
                      ),
                      if (attachments.isNotEmpty)
                        TextButton.icon(
                          onPressed: () =>
                              _openReceipt(attachments.first),
                          icon: const Icon(Icons.visibility_outlined),
                          label: const Text('Receipt'),
                        ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingPermission || !_allowed) {
      return const SizedBox.shrink();
    }

    final vehicles = widget.vehicles
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .where((vehicle) =>
            (vehicle['id']?.toString() ?? '').isNotEmpty)
        .toList();

    return Card(
      child: ExpansionTile(
        initiallyExpanded: false,
        maintainState: true,
        leading: const Icon(Icons.manage_search_outlined),
        title: const Text(
          'Parts / Warranty History',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: const Text(
          'Search installed customer-invoice items by description',
        ),
        children: [
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
            child: Column(
              children: [
                TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _runSearch(),
                  decoration: InputDecoration(
                    labelText: 'Search invoice items',
                    hintText: 'water, filter, pump...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      tooltip: 'Search',
                      onPressed: _loading ? null : _runSearch,
                      icon: _loading
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.arrow_forward),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (vehicles.length > 1) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    initialValue: _vehicleId,
                    decoration: const InputDecoration(
                      labelText: 'Vehicle',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All vehicles'),
                      ),
                      ...vehicles.map(
                        (vehicle) => DropdownMenuItem<String?>(
                          value: vehicle['id'].toString(),
                          child: Text(
                            _vehicleLabel(vehicle).isEmpty
                                ? 'Vehicle'
                                : _vehicleLabel(vehicle),
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() => _vehicleId = value);
                    },
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
                if (_search.text.trim().length >= 2 &&
                    !_loading &&
                    _error == null &&
                    _results.isEmpty) ...[
                  const SizedBox(height: 14),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'No matching customer invoice items found.',
                    ),
                  ),
                ],
                if (_results.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  ..._results.map(_resultCard),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
