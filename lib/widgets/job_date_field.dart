import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/briskers_colors.dart';

class JobDateField extends StatelessWidget {
  const JobDateField({super.key, required this.value, required this.onChanged});
  final DateTime value;
  final ValueChanged<DateTime>? onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onChanged == null
        ? null
        : () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: value,
              firstDate: DateTime(1900),
              lastDate: DateTime(2200),
            );
            if (picked != null) onChanged?.call(picked);
          },
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: 'Job Date',
        enabled: onChanged != null,
        prefixIcon: const Icon(
          Icons.calendar_today_outlined,
          color: BriskersColors.jobs,
        ),
      ),
      child: Text(DateFormat.yMMMd().format(value)),
    ),
  );
}
