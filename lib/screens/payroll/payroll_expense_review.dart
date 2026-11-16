import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../local/briskers_local_database.dart';
import '../../services/device_owner_authorization.dart';
import '../../services/local_payroll_expense_review.dart';
import 'employee_work_review.dart';

Future<void> showPayrollExpenseReview(
  BuildContext context, {
  required BriskersLocalDatabase database,
  required String business,
  DateTime? week,
  String? employeeId,
}) async {
  final authority = DeviceOwnerAuthorization.instance;
  if (!await authority.canViewSavedOwnerPayroll(business) || !context.mounted) {
    return;
  }
  final identity = authority.currentIdentity();
  final today = DateTime.now();
  final selected =
      week ??
      await showDatePicker(
        context: context,
        helpText: 'Choose any day in the payroll week',
        initialDate: today,
        firstDate: DateTime(2000),
        lastDate: today.add(const Duration(days: 7)),
      );
  if (!context.mounted ||
      selected == null ||
      identity == null ||
      !identity.matches(authority.currentIdentity())) {
    return;
  }
  final monday = EmployeeWorkReview.monday(selected);
  final start = DateFormat('yyyy-MM-dd').format(monday);
  final currency = NumberFormat.simpleCurrency(locale: 'en_US');
  try {
    final rows = await LocalPayrollExpenseReview(
      database,
    ).forWeek(business, start, employeeId: employeeId);
    if (!context.mounted || !identity.matches(authority.currentIdentity())) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(
          'Payroll expenses · ${DateFormat.MMMd().format(monday)} week',
        ),
        content: SizedBox(
          width: 450,
          child: rows.isEmpty
              ? const Text(
                  'This phone has no verified payroll payments for this week.',
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final row in rows)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${row['employee']} · ${currency.format((row['net_cents'] as int) / 100)}',
                        ),
                        subtitle: Text(
                          '${row['payment_date']} · ${row['payment_method']}\n${row['status']}',
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Close'),
          ),
          if (rows.isNotEmpty)
            FilledButton(
              onPressed: () async {
                if (!identity.matches(authority.currentIdentity())) return;
                await Clipboard.setData(
                  ClipboardData(
                    text: const JsonEncoder.withIndent('  ').convert({
                      'report': 'Briskers payroll expense review',
                      'week_of': start,
                      'verified_payments': rows,
                    }),
                  ),
                );
                if (dialog.mounted) Navigator.pop(dialog);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Payroll report copied. Paste it into your conversation.',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Copy report'),
            ),
        ],
      ),
    );
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This phone could not read the saved payroll report.'),
        ),
      );
    }
  }
}
