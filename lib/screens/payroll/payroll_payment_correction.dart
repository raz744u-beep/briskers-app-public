import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/local_payroll_repository.dart';
import '../../services/payroll_lan_enrollment.dart';
import '../../services/payroll_lan_identity.dart';
import '../../services/payroll_owner_lease.dart';
import '../../widgets/owner_confirmation_dialog.dart';

enum PayrollPaymentAction { edit, delete }

class PayrollPaymentCorrection {
  const PayrollPaymentCorrection(
    this.payment,
    this.action,
    this.amount, {
    this.adjustmentReason,
  });

  final Map<String, dynamic> payment;
  final PayrollPaymentAction action;
  final int amount;
  final String? adjustmentReason;

  static Future<PayrollPaymentCorrection?> confirm(
    BuildContext context,
    Map<String, dynamic> payment,
    String employee,
    PayrollPaymentAction action, {
    bool editAmountPaid = false,
  }) async {
    final net = payment['net'] as int;
    final currency = NumberFormat.simpleCurrency();
    final receipt = '$employee · ${payment['verified_date']} · ${currency.format(net / 100)}';
    if (action == PayrollPaymentAction.delete) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (_) => OwnerConfirmationDialog(
          title: 'Delete payroll payment?',
          confirm: 'Delete',
          destructive: true,
          sections: [
            Text(receipt),
            const SizedBox(height: 12),
            const Text(
              'Delete this entry only if it was recorded in error. '
              'This restores the payroll balance and removes the expense '
              'from active totals. The entry stays in the audit history. '
              'Any money already transferred stays with the recipient.',
            ),
          ],
        ),
      );
      return accepted == true ? PayrollPaymentCorrection(payment, action, net) : null;
    }

    final originalAdjustment = payment['effective_adjustment'] as int?;
    final originalReason = payment['adjustment_reason'] as String? ?? '';
    final editAdjustment = originalAdjustment != null && !editAmountPaid;
    final initialAmount = editAmountPaid ? net : originalAdjustment ?? net;
    int? editedAmount = initialAmount;
    var reason = originalReason;
    final amountController = TextEditingController(
      text: (initialAmount / 100).toStringAsFixed(2),
    );
    final editRoute = DialogRoute<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialog, update) {
          final input = editedAmount;
          final revisedNet = input == null ? null : net + input - initialAmount;
          final validNet = revisedNet != null &&
              (revisedNet == net || (net > 0 && revisedNet > 0 && revisedNet <= 100000000));
          return OwnerConfirmationDialog(
            title: 'Edit recorded payroll',
            confirm: 'Review correction',
            canConfirm: validNet &&
                (input != initialAmount || reason.trim() != originalReason),
            sections: [
              Text(receipt),
              const SizedBox(height: 12),
              const Text('Correct what was recorded for this payment.'),
              TextField(
                controller: amountController,
                selectAllOnFocus: true,
                decoration: InputDecoration(
                  labelText: editAdjustment ? 'Pay adjustment (+/−)' : 'Amount paid',
                  prefixText: '\$',
                ),
                keyboardType: TextInputType.numberWithOptions(
                  decimal: true,
                  signed: editAdjustment,
                ),
                onChanged: (value) => update(() {
                  editedAmount = _parseCents(value);
                }),
              ),
              if (originalAdjustment != null)
                TextFormField(
                  initialValue: originalReason,
                  decoration: const InputDecoration(labelText: 'Adjustment reason'),
                  onChanged: (value) => update(() => reason = value),
                ),
              const SizedBox(height: 12),
              if (revisedNet case final int amount when validNet)
                Text('Corrected amount paid ${currency.format(amount / 100)}')
              else
                Text(net == 0
                    ? 'You can correct the reason for this zero-dollar payment.'
                    : 'Enter a value that gives a positive amount paid.'),
            ],
          );
        },
      ),
    );
    final review = await Navigator.of(context, rootNavigator: true).push(editRoute);
    unawaited(editRoute.completed.then<void>((_) => amountController.dispose()));
    if (review != true || !context.mounted) return null;
    final revisedNet = net + editedAmount! - initialAmount;
    final reviewedReason = reason.trim();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (_) => OwnerConfirmationDialog(
        title: 'Save payroll correction?',
        confirm: 'Save correction',
        sections: [
          Text(receipt),
          if (originalAdjustment != null)
            Text('Pay adjustment ${currency.format((originalAdjustment + revisedNet - net) / 100)}'),
          if (reviewedReason.isNotEmpty) Text(reviewedReason),
          const SizedBox(height: 12),
          Text(
            'Corrected amount paid ${currency.format(revisedNet / 100)}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          const Text('This updates the payroll record. Any money already transferred stays with the recipient.'),
        ],
      ),
    );
    return accepted == true
        ? PayrollPaymentCorrection(payment, action, revisedNet,
            adjustmentReason: originalAdjustment == null ? null : reviewedReason)
        : null;
  }

  static int? _parseCents(String value) {
    final match = RegExp(r'^([+-]?)([0-9]{0,9})(?:\.([0-9]{0,2}))?$')
        .firstMatch(value.trim());
    if (match == null) return null;
    final whole = match[2]!;
    final fraction = match[3] ?? '';
    if (whole.isEmpty && fraction.isEmpty) return null;
    final cents = (int.tryParse(whole) ?? 0) * 100 +
        int.parse(fraction.padRight(2, '0'));
    return match[1] == '-' ? -cents : cents;
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
        jsonEncode([action.name, operation, revision, amount, adjustmentReason]),
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
        adjustmentReason: adjustmentReason,
      );
    }
  }
}
