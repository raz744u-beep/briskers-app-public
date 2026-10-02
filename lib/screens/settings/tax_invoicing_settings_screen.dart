import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/briskers_api.dart';

class TaxInvoicingSettingsScreen extends StatefulWidget {
  const TaxInvoicingSettingsScreen({
    super.key,
    required this.businessId,
  });

  final String businessId;

  @override
  State<TaxInvoicingSettingsScreen> createState() =>
      _TaxInvoicingSettingsScreenState();
}

class _TaxInvoicingSettingsScreenState
    extends State<TaxInvoicingSettingsScreen> {
  static const _api = BriskersApi();

  final _taxPercent = TextEditingController();
  final _warrantyMessage = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _taxPercent.dispose();
    _warrantyMessage.dispose();
    super.dispose();
  }

  String _percentText(Object? raw) {
    final rate = num.tryParse(raw?.toString() ?? '') ?? 0;
    var text = (rate * 100).toStringAsFixed(3);
    while (text.contains('.') && text.endsWith('0')) {
      text = text.substring(0, text.length - 1);
    }
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
    return text;
  }

  Future<void> _load() async {
    try {
      final data = await _api.taxSettings(widget.businessId);
      if (!mounted) return;
      setState(() {
        _taxPercent.text = _percentText(data['sales_tax_rate']);
        _warrantyMessage.text =
            data['invoice_warranty_message']?.toString() ?? '';
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _save() async {
    final percent = num.tryParse(_taxPercent.text.trim());
    if (percent == null || percent < 0 || percent > 100) {
      setState(() => _error = 'Enter a tax rate from 0 to 100%.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _api.updateTaxSettings(
        widget.businessId,
        salesTaxRate: percent / 100,
        invoiceWarrantyMessage: _warrantyMessage.text.trim().isEmpty
            ? null
            : _warrantyMessage.text.trim(),
      );
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoicing settings saved.')),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Taxes & Invoicing')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Shop sales tax rate',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'This default rate is applied automatically to catalog items marked Taxable. Non-taxable items stay at 0%.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _taxPercent,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Sales tax rate',
                    suffixText: '%',
                    border: OutlineInputBorder(),
                    helperText: 'Example: 9.45',
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Invoice warranty message',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Optional. This text appears in the full-width Warranty Information section on customer invoices and estimates.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _warrantyMessage,
                  minLines: 4,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Warranty message',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Save invoicing settings'),
                ),
              ],
            ),
    );
  }
}
