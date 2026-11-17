import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../local/briskers_local_database.dart';
import '../../services/device_owner_authorization.dart';
import '../../services/local_payroll_expense_review.dart';
import '../../services/local_payroll_expense_recovery.dart';
import 'employee_work_review.dart';

Future<void> showPayrollExpenseReview(
  BuildContext context, {
  required BriskersLocalDatabase database,
  required String business,
  DateTime? week,
  String? employeeId,
  VoidCallback? onReconciled,
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
    final reconcile = await showDialog<bool>(
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
          if (onReconciled != null &&
              rows.any(
                (row) =>
                    row['status'] ==
                        'Verified payment with no linked expense' &&
                    (row['possible_expenses'] as List).isEmpty,
              ))
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Reconcile missing expenses'),
            ),
          if (rows.isNotEmpty)
            TextButton(
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
    if (reconcile != true ||
        !context.mounted ||
        !identity.matches(authority.currentIdentity())) {
      return;
    }
    final recovery = LocalPayrollExpenseRecovery(database);
    final preview = await recovery.preview(business, start);
    if (!context.mounted || !identity.matches(authority.currentIdentity())) {
      return;
    }
    if (preview.payouts.isEmpty ||
        preview.accountId == null ||
        preview.account == null ||
        preview.categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            preview.payouts.isEmpty
                ? 'There are no verified, unmatched expenses to add on this phone.'
                : 'Business Checking–9858 and the Payroll category must be saved on this phone.',
          ),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Add ${preview.payouts.length} payroll expenses?'),
        content: SizedBox(
          width: 450,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text('${preview.account} · Payroll'),
              for (final payout in preview.payouts)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${payout.employee} · ${currency.format(payout.cents / 100)}',
                  ),
                  subtitle: Text(
                    '${DateFormat.yMMMd().format(DateTime.parse(payout.date))} · ${payout.method}',
                  ),
                ),
              Text('Total ${currency.format(preview.totalCents / 100)}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Add expenses'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !context.mounted ||
        !identity.matches(authority.currentIdentity())) {
      return;
    }
    final grant = await authority.authority.authorizeSession(business);
    if (!context.mounted || !identity.matches(authority.currentIdentity())) {
      return;
    }
    final created = await recovery.reconcile(preview, grant);
    if (context.mounted) {
      onReconciled?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            created == 0
                ? 'The payroll expenses are already saved.'
                : 'Added $created payroll ${created == 1 ? 'expense' : 'expenses'}.',
          ),
        ),
      );
    }
  } on StateError catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message.toString())));
    }
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
