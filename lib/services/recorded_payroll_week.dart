import 'dart:convert';

/// Read-only totals from recorded settlements and their frozen paid portions.
/// Current task hours, rates, and sync acknowledgment never establish a payout.
class RecordedPayrollWeek {
  RecordedPayrollWeek._(
    this.payments,
    this.work,
    this.paidMinutes,
    this.laborCents,
    this.baseCents,
    this.adjustmentCents,
    this.grossCents,
    this.repaymentCents,
    this.netCents,
  );

  final List<Map<String, dynamic>> payments, work;
  final int? paidMinutes, laborCents, baseCents, adjustmentCents;
  final int? grossCents, repaymentCents, netCents;
  bool get hasPayments => payments.isNotEmpty;

  static int? _integer(Object? value) => value is int ? value : null;
  static Map<dynamic, dynamic> _payload(Map<String, dynamic> payment) {
    final raw = payment['payload'];
    if (raw is Map) return raw;
    if (raw is String) {
      try {
        final value = jsonDecode(raw);
        if (value is Map) return value;
      } on FormatException {
        return const {};
      }
    }
    return const {};
  }

  static int? _sum(Iterable<int?> values) {
    var total = 0;
    for (final value in values) {
      if (value == null) return null;
      total += value;
    }
    return total;
  }

  factory RecordedPayrollWeek.fromHistory(
    List<Map<String, dynamic>> history, {
    required String employeeId,
    required DateTime week,
  }) {
    final monday = DateTime(
      week.year,
      week.month,
      week.day,
    ).subtract(Duration(days: week.weekday - 1));
    final weekKey = monday.toIso8601String().substring(0, 10);
    final byOperation = <String, Map<String, dynamic>>{};
    final reversed = <String>{};
    for (var i = 0; i < history.length; i++) {
      final payment = history[i];
      if (payment['employee_id'] != null &&
          payment['employee_id'] != employeeId) {
        continue;
      }
      final operation = payment['operation_id']?.toString();
      final key = operation == null || operation.isEmpty
          ? 'legacy-$i'
          : jsonEncode([payment['business_id'], operation]);
      if (payment['reversed_at'] != null) reversed.add(key);
      final prior = byOperation[key];
      if (prior == null ||
          (_integer(payment['amount_revision']) ?? 0) >
              (_integer(prior['amount_revision']) ?? 0)) {
        byOperation[key] = payment;
      }
    }
    final payments = [
      for (final entry in byOperation.entries)
        if (!reversed.contains(entry.key) && entry.value['week'] == weekKey)
          entry.value,
    ];
    final work = <Map<String, dynamic>>[];
    var workKnown = true;
    final bases = <int?>[];
    for (final payment in payments) {
      final raw = payment['work'];
      if (raw is! List) {
        workKnown = false;
      } else {
        final seen = <String>{};
        for (var i = 0; i < raw.length; i++) {
          final row = raw[i];
          if (row is! Map) {
            workKnown = false;
            continue;
          }
          final id = row['credit_id'] ?? row['id'];
          if (id != null && !seen.add(id.toString())) continue;
          work.add({
            ...Map<String, dynamic>.from(row),
            'operation_id': payment['operation_id'],
            'method': payment['method'] ?? row['method'],
            'verified_date': payment['verified_date'] ?? row['verified_date'],
          });
        }
      }
      bases.add(_integer(_payload(payment)['base']));
    }
    final minutes = workKnown
        ? _sum(work.map((r) => _integer(r['actual_minutes'])))
        : null;
    final labor = workKnown
        ? _sum(work.map((r) => _integer(r['gross_cents'])))
        : null;
    final base = _sum(bases);
    final gross = _sum(payments.map((p) => _integer(p['gross'])));
    final repayment = _sum(payments.map((p) => _integer(p['repayment'])));
    final net = _sum(payments.map((p) => _integer(p['net'])));
    // The effective ledger gross includes any saved receipt-amount correction.
    // The difference reconciles frozen labor/base to that actual recorded gross.
    final adjustment = gross != null && labor != null && base != null
        ? gross - labor - base
        : null;
    return RecordedPayrollWeek._(
      List.unmodifiable(payments),
      List.unmodifiable(work),
      minutes,
      labor,
      base,
      adjustment,
      gross,
      repayment,
      net,
    );
  }
}
