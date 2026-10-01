import 'package:flutter/material.dart';

import '../../services/briskers_api.dart';
import '../jobs/job_document_screen.dart';

class CustomerWarrantyHistorySection extends StatefulWidget {
  const CustomerWarrantyHistorySection({
    super.key,
    required this.businessId,
    required this.customerId,
  });

  final String businessId;
  final String customerId;

  @override
  State<CustomerWarrantyHistorySection> createState() =>
      _CustomerWarrantyHistorySectionState();
}

class _CustomerWarrantyHistorySectionState
    extends State<CustomerWarrantyHistorySection> {
  static const _api = BriskersApi();

  final TextEditingController _search = TextEditingController();

  bool _loadingPermission = true;
  bool _allowed = false;
  bool _isOwner = false;
  bool _searching = false;
  List<Map<String, dynamic>> _results = const [];
  String? _error;

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
        _allowed = permissions.contains('warranty.read');
        _isOwner = permissions.contains('records.delete');
        _loadingPermission = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _allowed = false;
        _loadingPermission = false;
      });
    }
  }

  Future<void> _runSearch() async {
    final query = _search.text.trim();
    if (query.length < 2 || _searching) return;

    setState(() {
      _searching = true;
      _error = null;
    });

    try {
      final rows = await _api.customerWarrantySearch(
        widget.businessId,
        widget.customerId,
        query,
      );
      if (!mounted) return;
      setState(() {
        _results = rows;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _openReceipt(
    Map<String, dynamic> attachment,
  ) async {
    try {
      final url = await _api.signedAttachmentUrl(
        attachment['bucket']?.toString() ?? 'briskers-private',
        attachment['key']?.toString() ?? '',
      );
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
                  minScale: 1,
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
                top: 6,
                right: 6,
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
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _openInvoice(
    Map<String, dynamic> result,
  ) async {
    final invoiceId = result['invoice_id']?.toString() ?? '';
    if (invoiceId.isEmpty) return;

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JobDocumentScreen(
          businessId: widget.businessId,
          documentId: invoiceId,
          isOwner: _isOwner,
        ),
      ),
    );
  }

  Widget _receiptTile(Map<String, dynamic> receipt) {
    final attachments = List<dynamic>.from(
      receipt['attachments'] ?? const <dynamic>[],
    ).map(
      (raw) => Map<String, dynamic>.from(raw as Map),
    ).toList();

    final matchedItems = List<dynamic>.from(
      receipt['matched_items'] ?? const <dynamic>[],
    ).map(
      (raw) => Map<String, dynamic>.from(raw as Map),
    ).toList();

    final vendor = receipt['vendor']?.toString() ?? 'Vendor';
    final vendorInvoice =
        receipt['vendor_invoice_number']?.toString().trim() ?? '';
    final date = receipt['transaction_date']?.toString().trim() ?? '';
    final names = matchedItems
        .map((item) => item['description']?.toString() ?? '')
        .where((value) => value.isNotEmpty)
        .join(', ');

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.receipt_long_outlined),
          const SizedBox(width: 10),
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
                Text(
                  <String>[
                    if (vendorInvoice.isNotEmpty)
                      'Vendor invoice $vendorInvoice',
                    if (date.isNotEmpty) date,
                    if (names.isNotEmpty) names,
                  ].join(' • '),
                ),
              ],
            ),
          ),
          if (attachments.isNotEmpty)
            IconButton(
              tooltip: 'View original receipt',
              onPressed: () => _openReceipt(attachments.first),
              icon: const Icon(Icons.zoom_in),
            ),
        ],
      ),
    );
  }

  Widget _resultCard(Map<String, dynamic> result) {
    final receipts = List<dynamic>.from(
      result['receipts'] ?? const <dynamic>[],
    ).map(
      (raw) => Map<String, dynamic>.from(raw as Map),
    ).toList();

    final name = result['line_name']?.toString() ?? 'Invoice item';
    final description =
        result['line_description']?.toString().trim() ?? '';
    final invoice = result['invoice_number']?.toString() ?? '';
    final date = result['invoice_date']?.toString() ?? '';
    final vehicle = result['vehicle']?.toString().trim() ?? '';
    final job = result['job_number']?.toString().trim() ?? '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  child: Icon(Icons.build_circle_outlined),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (description.isNotEmpty)
                        Text(description),
                      const SizedBox(height: 5),
                      Text(
                        <String>[
                          if (invoice.isNotEmpty) 'Invoice #$invoice',
                          if (date.isNotEmpty) date,
                          if (job.isNotEmpty) 'Job $job',
                          if (vehicle.isNotEmpty) vehicle,
                        ].join(' • '),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Open invoice',
                  onPressed: () => _openInvoice(result),
                  icon: const Icon(Icons.open_in_new),
                ),
              ],
            ),
            if (receipts.isEmpty)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Installed/billed item found. No purchase receipt is linked to this invoice item yet.',
                      ),
                    ),
                  ],
                ),
              )
            else
              ...receipts.map(_receiptTile),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingPermission || !_allowed) {
      return const SizedBox.shrink();
    }

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
          'Search installed customer invoice items by partial description',
        ),
        children: [
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _runSearch(),
              decoration: InputDecoration(
                labelText: 'Search part or item',
                hintText: 'Example: water, pump, filter',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Search',
                  onPressed: _searching ? null : _runSearch,
                  icon: _searching
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
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            )
          else if (_search.text.trim().length >= 2 &&
              !_searching &&
              _results.isEmpty)
            const Padding(
              padding: EdgeInsets.all(14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'No installed/billed invoice items match this search.',
                ),
              ),
            )
          else if (_results.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
              child: Column(
                children: _results.map(_resultCard).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
