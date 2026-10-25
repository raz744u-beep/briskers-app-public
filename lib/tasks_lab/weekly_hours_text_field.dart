import 'package:flutter/material.dart';

/// An editable weekly TEST payroll quantity. Tapping the field selects its
/// entire current value, so typing replaces it without manual backspacing.
/// Reading or leaving the field untouched never changes saved hours.
class WeeklyHoursTextField extends StatefulWidget {
  const WeeklyHoursTextField({
    super.key,
    required this.initialHours,
    required this.enabled,
    required this.onChanged,
  });

  final String initialHours;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  State<WeeklyHoursTextField> createState() => _WeeklyHoursTextFieldState();
}

class _WeeklyHoursTextFieldState extends State<WeeklyHoursTextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialHours);
  }

  @override
  void didUpdateWidget(covariant WeeklyHoursTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialHours != widget.initialHours &&
        _controller.text != widget.initialHours) {
      _controller.value = TextEditingValue(
        text: widget.initialHours,
        selection: TextSelection.collapsed(offset: widget.initialHours.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: _controller,
    enabled: widget.enabled,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: const InputDecoration(
      labelText: 'Hours to credit this week',
      border: OutlineInputBorder(),
      helperText: 'Tap to replace hours; remainder carries forward'),
    onTap: () {
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    },
    onChanged: widget.onChanged,
  );
}
