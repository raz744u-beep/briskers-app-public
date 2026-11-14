import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'approved_tasks_ui.dart';

String payrollMoney(int cents) =>
    NumberFormat.simpleCurrency(locale: 'en_US').format(cents / 100);

/// Display-only arithmetic identical to the existing settlement's cumulative
/// minute rounding. This never creates or authorizes a payment.
int selectedLaborCents(Map<String, dynamic> row, double hours, {int? rate}) {
  final paid = row['paid_minutes'] as int? ?? 0;
  final minutes = (hours * 60).round();
  final cents =
      rate ??
      row['payment_rate_cents'] as int? ??
      row['rate_cents'] as int? ??
      0;
  return ((paid + minutes) * cents + 30) ~/ 60 - (paid * cents + 30) ~/ 60;
}

class LaborBalanceTiles extends StatelessWidget {
  const LaborBalanceTiles({
    super.key,
    required this.total,
    required this.paid,
    required this.remaining,
    this.totalLabel = 'Total',
    this.paidLabel = 'Paid',
    this.remainingLabel = 'Remaining',
  });
  final double total, paid, remaining;
  final String totalLabel, paidLabel, remainingLabel;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final item in [
        (totalLabel, total, const Color(0xFFE7F2FF), taskBlue),
        (paidLabel, paid, const Color(0xFFE4F7DE), taskGreen),
        (remainingLabel, remaining, const Color(0xFFFFEBD1), taskAmber),
      ])
        Expanded(
          child: Container(
            height: 88,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: item.$3,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    item.$1,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: item.$4,
                    ),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${item.$2.toStringAsFixed(2)} h',
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      color: item.$4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

class PayableHoursDialog extends StatefulWidget {
  const PayableHoursDialog({
    super.key,
    required this.task,
    required this.selected,
    required this.total,
    required this.paid,
    required this.remaining,
  });
  final Map<String, dynamic> task;
  final double selected, total, paid, remaining;
  @override
  State<PayableHoursDialog> createState() => _PayableHoursDialogState();
}

class _PayableHoursDialogState extends State<PayableHoursDialog> {
  late final input = TextEditingController(
    text: (double.parse(widget.selected.toStringAsFixed(2))>widget.remaining ? (widget.remaining*100).floor()/100 : widget.selected).toStringAsFixed(2),
  );
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = double.tryParse(input.text.trim());
    final valid =
        value != null &&
        value.isFinite &&
        value >= 0 &&
        value <= widget.remaining &&
        RegExp(r'^\d+(\.\d{0,2})?$').hasMatch(input.text.trim());
    return Dialog(
      backgroundColor:Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 470),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF174D91), taskNavy],
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.payments_outlined, color: Colors.white),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Edit Payable Hours',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close payable hours',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: taskCanvas,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${widget.task['job_number'] ?? 'Job'} · ${widget.task['customer_name'] ?? ''}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text('${widget.task['description'] ?? 'Labor'}'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    LaborBalanceTiles(
                      total: widget.total,
                      paid: widget.paid,
                      remaining: widget.remaining,
                      totalLabel: 'Total Hours',
                      paidLabel: 'Previously Paid',
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Hours to Pay This Week',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const Key('payable-hours-input'),
                      controller: input,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setState(() {}),
                      onTapAlwaysCalled: true,
                      onTap: () => input.selection = TextSelection(
                        baseOffset: 0,
                        extentOffset: input.text.length,
                      ),
                      decoration: InputDecoration(
                        suffixText: 'h',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        errorText: valid
                            ? null
                            : 'Enter 0.00 to ${widget.remaining.toStringAsFixed(2)} hours.',
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: taskGreen,
                            ),
                            onPressed: valid
                                ? () {final current=double.tryParse(input.text.trim());if(current!=null&&current.isFinite&&current>=0&&current<=widget.remaining&&RegExp(r'^\d+(\.\d{0,2})?$').hasMatch(input.text.trim()))Navigator.pop(context,current);}
                                : null,
                            icon: const Icon(Icons.check),
                            label: const Text('Save'),
                          ),
                        ),
                      ],
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
}

class WorkPayrollSummary extends StatefulWidget {
  const WorkPayrollSummary({
    super.key,
    required this.week,
    required this.rows,
    required this.payments,
    required this.loadDraft,
    required this.onReview,
    required this.revision,
  });
  final DateTime week;
  final List<Map<String, dynamic>> rows, payments;
  final Future<Map<String, dynamic>?> Function(DateTime) loadDraft;
  final VoidCallback onReview;
  final int revision;
  @override
  State<WorkPayrollSummary> createState() => _WorkPayrollSummaryState();
}

class _WorkPayrollSummaryState extends State<WorkPayrollSummary> {
  Map<String, dynamic>? draft;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant WorkPayrollSummary old) {
    super.didUpdateWidget(old);
    if (old.week != widget.week || old.revision != widget.revision) _load();
  }

  Future<void> _load() async {
    final token = ++generation;
    draft = null;
    try {
      final value = await widget.loadDraft(widget.week);
      if (mounted && token == generation) setState(() => draft = value);
    } catch (_) {
      if (mounted && token == generation) setState(() => draft = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final week = DateFormat('yyyy-MM-dd').format(widget.week);
    final payments = widget.payments.where((p) => p['week'] == week).toList();
    String state = 'Not calculated';
    double? hours;
    int? amount;
    if (payments.isNotEmpty) {
      state = 'Paid';
      hours =
          payments
              .expand((p) => (p['work'] as List? ?? []).whereType<Map>())
              .fold<int>(0, (n, w) => n + (w['actual_minutes'] as int? ?? 0)) /
          60;
      amount = payments.fold<int>(0, (n, p) => n + (p['net'] as int? ?? 0));
    } else if (draft != null) {
      final saved = draft!['hours'] as Map? ?? {};
      final byId = {for (final r in widget.rows) r['id']: r};
      final valid = saved.entries.every((e) {
        final r = byId[e.key];
        return r != null &&
            e.value is num &&
            (e.value as num).isFinite &&
            (e.value as num) >= 0 &&
            (e.value as num) * 60 <= (r['remaining_minutes'] as int? ?? 0) &&
            r['archived_labor'] != 1 &&
            r['assignment_conflict'] != 1 &&
            r['payroll_treatment'] != 'review';
      });
      if (valid) {
        state = 'Draft';
        hours = saved.values.fold<double>(
          0,
          (n, v) => n + (v as num).toDouble(),
        );
        amount =
            saved.entries.fold<int>(
              0,
              (n, e) =>
                  n +
                  selectedLaborCents(byId[e.key]!, (e.value as num).toDouble()),
            ) +
            (draft!['adjustment'] as int? ?? 0) -
            (draft!['repayment'] as int? ?? 0);
      }
    }
    return Card(
      key: const Key('work-payroll-summary'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.payments_outlined, color: taskGreen),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Payroll This Week',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                ),
                Text(
                  state,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: state == 'Paid' ? taskGreen : taskNavy,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (hours == null)
              const Text('No saved payroll calculation for this week.')
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${state == 'Paid' ? 'Recorded' : 'Selected'} hours: ${hours.toStringAsFixed(2)}',
                  ),
                  Text(
                    payrollMoney(amount!),
                    style: const TextStyle(
                      color: taskGreen,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: taskGreen),
              onPressed: widget.onReview,
              icon: const Icon(Icons.check),
              label: const Text('Review & Pay'),
            ),
          ],
        ),
      ),
    );
  }
}
