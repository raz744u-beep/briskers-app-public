// ignore_for_file: prefer_interpolation_to_compose_strings, use_null_aware_elements, curly_braces_in_flow_control_structures
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/local_financial_cache.dart';
import 'expense_entry_screen.dart';

/// Entry point only for -DBRISKERS_RECEIPT_TEST=true builds.
/// Uses a unique business ID and separate Android application package.
class ReceiptScanTestHarness extends StatefulWidget {
  const ReceiptScanTestHarness({
    super.key,
    this.testEditorBuilder,
    this.testOnlySkipDatabase = false,
  });

  /// Test seam: keep navigation behavior real, mock only the destination.
  final Widget Function(ImageSource source)? testEditorBuilder;
  final bool testOnlySkipDatabase;

  @override
  State<ReceiptScanTestHarness> createState() => _ReceiptScanTestHarnessState();
}

class _ReceiptScanTestHarnessState extends State<ReceiptScanTestHarness> {
  static const business = 'briskers-isolated-receipt-test-20261102';
  // Injected by the isolated Actions workflow. Must be visible to distinguish
  // an installed old TEST build from a newer, differently signed APK.
  static const buildCommit = String.fromEnvironment(
    'BRISKERS_SOURCE', defaultValue: 'unidentified');

  final _cache = LocalFinancialCache();
  List<Map<String, dynamic>> _rows = const [];
  String? _error;
  bool _openingScanner = false;
  bool _scanChoicesVisible = false;
  int _scanTapCount = 0;
  String _scanStage = 'Ready';


  @override
  void initState() {
    super.initState();
    if (!widget.testOnlySkipDatabase) _reload();
  }

  Future<void> _reload() async {
    try {
      final rows = await _cache.loadTransactions(business, direction: 'expense');
      if (mounted) setState(() {
        _rows = rows;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  void _showScanChoices() {
    if (_openingScanner) return;
    // This must update the screen synchronously, before any platform plugin
    // or Navigator call. It is a visible proof that the button received a tap.
    setState(() {
      _scanTapCount++;
      _scanChoicesVisible = true;
      _scanStage = 'Button tap #$_scanTapCount received — select a photo source';
      _error = null;
    });
  }

  Future<void> _scan(ImageSource source, BuildContext routeContext) async {
    if (_openingScanner) return;
    setState(() {
      _openingScanner = true;
      _scanStage = source == ImageSource.camera
          ? 'Opening the receipt camera…'
          : 'Opening the receipt gallery…';
      _error = null;
    });
    try {
      // The State context is above the MaterialApp. Use a context created
      // inside its home Builder so Navigator.of finds the actual app route.
      await Navigator.of(routeContext).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => widget.testEditorBuilder?.call(source) ??
              ExpenseEntryScreen(
                businessId: business,
                autoScanReceipt: true,
                initialReceiptSource: source,
              ),
        ),
      );
      if (!mounted) return;
      setState(() => _scanStage = 'Returned from receipt editor');
      if (!widget.testOnlySkipDatabase) await _reload();
    } catch (error, stack) {
      debugPrint('Receipt test navigation failed: $error\n$stack');
      if (mounted) {
        setState(() {
          _scanStage = 'Could not open receipt editor';
          _error = 'Receipt navigation: $error';
        });
      }
    } finally {
      if (mounted) setState(() => _openingScanner = false);
    }
  }

  Future<void> _open(Map<String, dynamic> row, BuildContext routeContext) async {
    final id = row['id']?.toString();
    if (id == null) return;
    final detail = await _cache.loadTransactionDetail(business, id);
    if (!mounted || !routeContext.mounted) return;
    final attachments = detail?['attachments'] is List
        ? detail!['attachments'] as List : <dynamic>[];
    final items = detail?['receipt_items'] is List
        ? detail!['receipt_items'] as List : <dynamic>[];
    await showModalBottomSheet<void>(
      context: routeContext,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: .8,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            const Text('Saved locally (isolated TEST)',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Text('Description: ' + (detail?['remarks']?.toString() ?? '')),
            const SizedBox(height: 8),
            Text('Amount: ' + (detail?['amount']?.toString() ?? '')),
            const SizedBox(height: 8),
            Text('Vendor: ' + (detail?['counterparty']?.toString() ?? '')),
            const SizedBox(height: 8),
            Text('Invoice: ' +
              (detail?['receipt_details'] is Map
                ? (detail!['receipt_details']['vendor_invoice_number']?.toString() ?? '')
                : '')),
            const SizedBox(height: 8),
            Text('Stored parts: ' + items.length.toString()),
            for (final raw in items)
              if (raw is Map)
                ListTile(
                  title: Text(raw['description']?.toString() ?? ''),
                  subtitle: Text('SKU: ' + (raw['sku']?.toString() ?? '') +
                    ' • Qty: ' + (raw['quantity']?.toString() ?? '') +
                    ' • Unit: ' + (raw['unit_price']?.toString() ?? '')),
                ),
            const SizedBox(height: 12),
            Text('Original photos: ' + attachments.length.toString()),
            for (final raw in attachments)
              if (raw is Map && raw['local_file_path'] is String)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Image.file(
                    File(raw['local_file_path'] as String),
                    height: 250,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                      const Text('Photo unavailable; verify local file'),
                  ),
                ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Briskers Receipt TEST 3',
      debugShowCheckedModeBanner: true,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blueGrey),
      home: Builder(builder: (routeContext) => Scaffold(
        appBar: AppBar(title: const Text('Briskers Receipt TEST 3')),
        body: RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Isolated synthetic test database. Supabase synchronization '
                'is disabled for this APK even when Wi-Fi is on. '
                'Your installed shop app and its invoices are untouched.',
              ),
              const SizedBox(height: 12),
              const Text('Installed TEST build: $buildCommit',
                style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _openingScanner ? null : _showScanChoices,
                icon: _openingScanner
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.document_scanner_outlined),
                label: Text(_openingScanner
                    ? 'Opening receipt editor…' : 'AI Scan Receipt'),
              ),
              const SizedBox(height: 8),
              Text('Scanner status: $_scanStage'),
              if (_scanChoicesVisible) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Scan receipt offline',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _openingScanner
                              ? null : () => _scan(ImageSource.camera, routeContext),
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('Take receipt photo'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _openingScanner
                              ? null : () => _scan(ImageSource.gallery, routeContext),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Choose from gallery'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Text('Saved local expenses: ' + _rows.length.toString(),
                style: const TextStyle(fontWeight: FontWeight.w800)),
              if (_error != null) Text(_error!),
              if (_rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text('No TEST expenses saved. Scan a receipt first.'),
                ),
              for (final row in _rows)
                Card(
                  child: ListTile(
                    title: Text(row['counterparty']?.toString() ?? 'Expense'),
                    subtitle: Text(row['remarks']?.toString() ?? ''),
                    trailing: Text(row['amount']?.toString() ?? ''),
                    onTap: () => _open(row, routeContext),
                  ),
                ),
            ],
          ),
        ),
      )),
    );
  }
}
