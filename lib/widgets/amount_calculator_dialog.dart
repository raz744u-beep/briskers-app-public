import 'package:flutter/material.dart';

import '../core/amount_calculator.dart';
import '../core/briskers_colors.dart';

Future<int?> showAmountCalculator(
  BuildContext context, {
  String initial = '',
  int? balanceCents,
  bool allowNegative = false,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showDialog<int>(
    context: context,
    builder: (_) =>
        _AmountCalculatorDialog(
          initial: initial, balanceCents: balanceCents, allowNegative: allowNegative,
        ),
  );
}

class _AmountCalculatorDialog extends StatefulWidget {
  const _AmountCalculatorDialog({
    required this.initial,
    required this.balanceCents,
    required this.allowNegative,
  });

  final String initial;
  final int? balanceCents;
  final bool allowNegative;

  @override
  State<_AmountCalculatorDialog> createState() => _AmountCalculatorDialogState();
}

class _AmountCalculatorDialogState extends State<_AmountCalculatorDialog> {
  late final _input = TextEditingController.fromValue(
    TextEditingValue(
      text: widget.initial,
      selection: TextSelection(baseOffset: 0, extentOffset: widget.initial.length),
    ),
  );
  String? _error;

  int? _evaluate() {
    try {
      final result = AmountCalculator.cents(
        _input.text,
        balanceCents: widget.balanceCents,
        allowNegative: widget.allowNegative,
      );
      setState(() => _error = null);
      return result;
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return null;
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _press(String label) {
    if (label == '=') {
      final result = _evaluate();
      if (result != null) {
        final text = (result / 100).toStringAsFixed(2);
        _input.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
      return;
    }
    setState(() => _error = null);
    if (label == 'C') {
      _input.clear();
      return;
    }
    final selection = _input.selection;
    var start = selection.isValid ? selection.start : _input.text.length;
    final end = selection.isValid ? selection.end : _input.text.length;
    // An operator can continue a calculation from the selected starting
    // amount. Digits and the decimal point replace that selection.
    if (start == 0 &&
        end == _input.text.length &&
        const {'+', '−', '×', '÷', '%'}.contains(label)) {
      start = end;
    }
    if (label == '⌫' && start == end && start > 0) start--;
    final replacement = label == '⌫' ? '' : label;
    _input.value = TextEditingValue(
      text: _input.text.replaceRange(start, end, replacement),
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
  }

  Widget _key(String label, {int flex = 1}) {
    final color = switch (label) {
      '=' => BriskersColors.customerSave,
      'C' || '⌫' || '%' || '÷' || '×' || '−' || '+' => const Color(0xFFE5EFFA),
      _ => const Color(0xFFF1F5F9),
    };
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Semantics(
          label: switch (label) {
            'C' => 'Clear',
            '⌫' => 'Backspace',
            '=' => 'Equals',
            _ => null,
          },
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: color,
              foregroundColor: label == '=' ? Colors.white : BriskersColors.text,
              minimumSize: const Size(0, 44),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => _press(label),
            child: label == '⌫'
                ? const Icon(Icons.backspace_outlined, size: 19)
                : Text(label, style: const TextStyle(fontSize: 18)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    backgroundColor: BriskersColors.surface,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(gradient: BriskersColors.blueHeader),
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Amount calculator',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cancel',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.balanceCents case final balance?) ...[
                    Text(
                      'Current amount owed: \$${(balance / 100).toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const Text('Use +300 or -140 to adjust the balance.'),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: _input,
                    selectAllOnFocus: true,
                    onTapAlwaysCalled: true,
                    onTap: () => _input.selection = TextSelection(
                      baseOffset: 0,
                      extentOffset: _input.text.length,
                    ),
                    textAlign: TextAlign.end,
                    onChanged: (_) => setState(() => _error = null),
                    onSubmitted: (_) => _press('='),
                    decoration: InputDecoration(
                      labelText: 'Calculation',
                      hintText: '0.00',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      errorText: _error,
                      errorMaxLines: 2,
                      filled: true,
                      fillColor: const Color(0xFFF1F5F9),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final row in const [
                    ['C', '⌫', '%', '÷'],
                    ['7', '8', '9', '×'],
                    ['4', '5', '6', '−'],
                    ['1', '2', '3', '+'],
                  ])
                    Row(children: [for (final label in row) _key(label)]),
                  Row(children: [_key('0', flex: 2), _key('.'), _key('=')]),
                  const SizedBox(height: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: BriskersColors.confirm,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () {
                      final result = _evaluate();
                      if (result != null) Navigator.pop(context, result);
                    },
                    child: const Text('Use Amount'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
