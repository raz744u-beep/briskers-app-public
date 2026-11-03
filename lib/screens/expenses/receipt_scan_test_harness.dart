import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/local_financial_cache.dart';
import 'expense_entry_screen.dart';

/// Entry point only for -DBRISKERS_RECEIPT_TEST=true builds.
/// Uses a unique business ID and separate Android application package.
class ReceiptScanTestHarness extends StatefulWidget {
  const ReceiptScanTestHarness({super.key});

  @override
  State<ReceiptScanTestHarness> createState() => _ReceiptScanTestHarnessState();
}

class _ReceiptScanTestHarnessState extends State<ReceiptScanTestHarness> {
  static const business = 'briskers-isolated-receipt-test-20261102';
  final _cache = LocalFinancialCache();
  List<Map<String, dynamic>> _rows = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
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

  Future<void> _scan() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => const ExpenseEntryScreen(
          businessId: business,
          autoScanReceipt: true,
        ),
      ),
    );
    await _reload();
  }

  Future<void> _open(Map<String, dynamic> row) async {
    final id = row['id']?.toString();
    if (id == null) return;
    final detail = await _cache.loadTransactionDetail(business, id);
    if (!mounted) return;
    final attachments = detail?['attachments'] is List
        ? detail!['attachments'] as List : <dynamic>[];
    final items = detail?['receipt_items'] is List
        ? detail!['receipt_items'] as List : <dynamic>[];
    await showModalBottomSheet<void>(
      context: context,
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
      title: 'Briskers Receipt TEST',
      debugShowCheckedModeBanner: true,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blueGrey),
      home: Scaffold(
        appBar: AppBar(title: const Text('Briskers Receipt TEST')),
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
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _scan,
                icon: const Icon(Icons.document_scanner_outlined),
                label: const Text('AI Scan Receipt'),
              ),
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
                    onTap: () => _open(row),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
