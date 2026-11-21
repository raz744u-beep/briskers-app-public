import 'package:flutter/material.dart';
import '../core/amount_calculator.dart';

Future<int?> showAmountCalculator(BuildContext context, {
  String initial = '', int? balanceCents,
}) => showDialog<int>(context: context, builder: (_) =>
    _AmountCalculatorDialog(initial: initial, balanceCents: balanceCents));

class _AmountCalculatorDialog extends StatefulWidget {
  const _AmountCalculatorDialog({required this.initial, this.balanceCents});
  final String initial;
  final int? balanceCents;
  @override
  State<_AmountCalculatorDialog> createState() => _AmountCalculatorDialogState();
}

class _AmountCalculatorDialogState extends State<_AmountCalculatorDialog> {
  late final input = TextEditingController(text: widget.initial);
  String? error;
  int? evaluate() {
    try {
      final result = AmountCalculator.cents(input.text, balanceCents: widget.balanceCents);
      setState(() => error = null);
      return result;
    } on FormatException catch (e) {
      setState(() => error = e.message);
      return null;
    }
  }
  @override
  void dispose() { input.dispose(); super.dispose(); }
  void key(String value) {
    setState(() { error = null; });
    if (value == 'C') { input.clear(); return; }
    if (value == '⌫') {
      final end = input.selection.isValid ? input.selection.end : input.text.length;
      final start = input.selection.isValid ? input.selection.start : end;
      if (start != end || start > 0) {
        final from = start == end ? start - 1 : start;
        input.value = TextEditingValue(text: input.text.replaceRange(from, end, ''),
          selection: TextSelection.collapsed(offset: from));
      }
      return;
    }
    if (value == '=') {
      final result = evaluate();
      if (result != null) input.text = (result / 100).toStringAsFixed(2);
      return;
    }
    final selection = input.selection;
    final start = selection.isValid ? selection.start : input.text.length;
    final end = selection.isValid ? selection.end : input.text.length;
    input.value = TextEditingValue(text: input.text.replaceRange(start, end, value),
      selection: TextSelection.collapsed(offset: start + value.length));
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Amount calculator'),
    content: SizedBox(width: 300, child: SingleChildScrollView(child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        if (widget.balanceCents != null) Text(
          'Current amount owed: \$${(widget.balanceCents! / 100).toStringAsFixed(2)}\nUse +300 or -140 to adjust the balance.'),
        TextField(controller: input, keyboardType: TextInputType.text,
          decoration: InputDecoration(labelText: 'Calculation', errorText: error)),
        const SizedBox(height: 12),
        for (final row in const [
          ['C','⌫','%','÷'], ['7','8','9','×'], ['4','5','6','−'],
          ['1','2','3','+'], ['0','.','='],
        ]) Row(children: [for (final label in row) Expanded(child: Padding(
          padding: const EdgeInsets.all(2), child: OutlinedButton(
            style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () => key(label), child: Text(label)),
        ))]),
      ],
    ))),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () { final result = evaluate();
        if (result != null) Navigator.pop(context, result);
      }, child: const Text('Use Amount'))],
  );
}
