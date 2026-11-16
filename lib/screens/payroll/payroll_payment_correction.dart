import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../services/local_payroll_repository.dart';
import '../../services/payroll_lan_enrollment.dart';
import '../../services/payroll_lan_identity.dart';
import '../../services/payroll_owner_lease.dart';
import '../../widgets/owner_confirmation_dialog.dart';

enum PayrollPaymentAction { edit, delete }

class PayrollPaymentCorrection {
  const PayrollPaymentCorrection(this.payment, this.action, this.amount);

  final Map<String, dynamic> payment;
  final PayrollPaymentAction action;
  final int amount;

  static Future<PayrollPaymentCorrection?> confirm(
    BuildContext context,
    Map<String, dynamic> payment,
    String employee,
    PayrollPaymentAction action,
  ) async {
    final deleting = action == PayrollPaymentAction.delete;
    final net = payment['net'] as int;
    final money = NumberFormat.simpleCurrency().format(net / 100);
    int? amount;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialog, update) => OwnerConfirmationDialog(
          title: deleting ? 'Delete payroll payment?' : 'Edit payroll payment',
          confirm: deleting ? 'Delete' : 'Save',
          destructive: deleting,
          canConfirm: deleting || (amount != null && amount != net),
          sections: [
            Text('$employee · ${payment['verified_date']} · $money'),
            const SizedBox(height: 12),
            if (deleting)
              const Text(
                'Delete this entry only if it was recorded in error. '
                'This restores the payroll balance and removes the expense '
                'from active totals. The entry stays in the audit history. '
                'Any money already transferred stays with the recipient.',
              )
            else ...[
              const Text(
                'Enter the amount actually transferred. The linked expense will update with it.',
              ),
              TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Amount paid',
                  prefixText: '\$',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                onChanged: (input) => update(() {
                  final match = RegExp(
                    r'^([0-9]{1,7})(?:\.([0-9]{0,2}))?$',
                  ).firstMatch(input);
                  final cents = match == null
                      ? 0
                      : int.parse(match[1]!) * 100 +
                            int.parse((match[2] ?? '').padRight(2, '0'));
                  amount = cents > 0 && cents <= 100000000 ? cents : null;
                }),
              ),
            ],
          ],
        ),
      ),
    );
    return accepted == true
        ? PayrollPaymentCorrection(payment, action, amount ?? net)
        : null;
  }

  Future<void> apply(
    String business,
    String actor,
    Future<LocalPayrollRepository> Function(String operation) openLedger,
  ) async {
    final employee = payment['employee_id'] as String;
    final identity = await PayrollLanIdentity.load();
    if (await PayrollLanEnrollment(identity).ownerPeer(business, employee) !=
        null) {
      throw StateError(
        'This employee has a paired payroll device. Review both ledgers before changing this entry.',
      );
    }
    final operation = payment['operation_id'] as String;
    final revision = payment['amount_revision'] as int? ?? 0;
    final ledger = await openLedger(
      await PayrollOwnerLease.digest(
        '${action.name}:$operation:$revision:$amount',
      ),
    );
    if (action == PayrollPaymentAction.delete) {
      await ledger.reversePayment(
        operation: operation,
        employee: employee,
        actorId: actor,
        expectedRevision: revision,
        reason: 'Owner deleted an incorrectly recorded payment.',
      );
    } else {
      await ledger.editPaymentAmount(
        operation: operation,
        employee: employee,
        actorId: actor,
        expectedRevision: revision,
        net: amount,
      );
    }
  }
}
