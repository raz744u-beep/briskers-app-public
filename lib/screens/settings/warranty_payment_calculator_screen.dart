import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/briskers_colors.dart';
import '../../core/briskers_i18n.dart';

class WarrantyPaymentCalculatorScreen extends StatefulWidget {
  const WarrantyPaymentCalculatorScreen({super.key});

  @override
  State<WarrantyPaymentCalculatorScreen> createState() =>
      _WarrantyPaymentCalculatorScreenState();
}

class _WarrantyPaymentCalculatorScreenState
    extends State<WarrantyPaymentCalculatorScreen> {
  final TextEditingController _approvedController = TextEditingController();
  final NumberFormat _currency = NumberFormat.currency(symbol: '\$');

  int _approvedCents = 0;
  int _baseCents = 0;
  int _surchargeCents = 0;
  int _finalCents = 0;

  @override
  void initState() {
    super.initState();
    _approvedController.addListener(_recalculate);
  }

  @override
  void dispose() {
    _approvedController
      ..removeListener(_recalculate)
      ..dispose();
    super.dispose();
  }

  void _recalculate() {
    final raw = _approvedController.text.replaceAll(',', '').trim();
    final approved = double.tryParse(raw) ?? 0;
    final approvedCents = approved > 0 ? (approved * 100).round() : 0;

    var baseCents = 0;
    var surchargeCents = 0;
    var finalCents = 0;

    if (approvedCents > 0) {
      baseCents = (approvedCents / 1.03).round();

      int totalFor(int cents) {
        final surcharge = (cents * 0.03).round();
        return cents + surcharge;
      }

      while (baseCents > 0 && totalFor(baseCents) > approvedCents) {
        baseCents -= 1;
      }

      while (totalFor(baseCents + 1) <= approvedCents) {
        baseCents += 1;
      }

      surchargeCents = (baseCents * 0.03).round();
      finalCents = baseCents + surchargeCents;
    }

    if (!mounted) return;
    setState(() {
      _approvedCents = approvedCents;
      _baseCents = baseCents;
      _surchargeCents = surchargeCents;
      _finalCents = finalCents;
    });
  }

  String _moneyFromCents(int cents) => _currency.format(cents / 100);

  Future<void> _copyAmount() async {
    if (_baseCents <= 0) return;

    final value = (_baseCents / 100).toStringAsFixed(2);
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr('warrantyAmountCopied'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasAmount = _approvedCents > 0;
    final difference = _approvedCents - _finalCents;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('warrantyPaymentCalculator')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        children: [
          Text(
            tr('approvedWarrantyPayment'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            tr('approvedWarrantyPaymentHelp'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _approvedController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                RegExp(r'^\d{0,8}(?:\.\d{0,2})?'),
              ),
            ],
            decoration: InputDecoration(
              labelText: tr('approvedTotal'),
              prefixText: '\$ ',
              border: const OutlineInputBorder(),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(
                  color: BriskersColors.invoices,
                  width: 2,
                ),
              ),
              suffixIcon: _approvedController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: tr('clear'),
                      onPressed: _approvedController.clear,
                      icon: const Icon(Icons.clear),
                    ),
            ),
            cursorColor: BriskersColors.invoices,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          if (hasAmount) ...[
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              decoration: BoxDecoration(
                color: BriskersColors.invoices.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: BriskersColors.invoices.withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    tr('runCardFor'),
                    style: const TextStyle(
                      color: BriskersColors.invoices,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _moneyFromCents(_baseCents),
                    style: const TextStyle(
                      color: BriskersColors.invoices,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: BriskersColors.invoices,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _copyAmount,
                    icon: const Icon(Icons.copy_outlined),
                    label: Text(tr('copyAmount')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _resultRow(
              tr('approvedTotal'),
              _moneyFromCents(_approvedCents),
            ),
            _resultRow(
              tr('threePercentSurcharge'),
              _moneyFromCents(_surchargeCents),
            ),
            _resultRow(
              tr('finalChargedTotal'),
              _moneyFromCents(_finalCents),
              emphasized: true,
            ),
            if (difference > 0)
              _resultRow(
                tr('underApprovedLimit'),
                _moneyFromCents(difference),
              ),
            const SizedBox(height: 18),
          ],
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F6F8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.calculate_outlined,
                  color: BriskersColors.invoices,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr('warrantyCalculatorFormulaHelp'),
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultRow(
    String label,
    String value, {
    bool emphasized = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight:
                    emphasized ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: emphasized ? 18 : 16,
              fontWeight: FontWeight.w900,
              color:
                  emphasized ? BriskersColors.invoices : const Color(0xFF182239),
            ),
          ),
        ],
      ),
    );
  }
}
