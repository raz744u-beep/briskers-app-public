import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Payroll History follows original TEST four-metric visual baseline', () {
    final s = File('lib/screens/payroll/payroll_history_panel.dart')
        .readAsStringSync();
    final cardStart = s.indexOf('Widget _card(_RecordedWeek week)');
    final cardEnd = s.indexOf('Widget build(BuildContext context)', cardStart);
    expect(cardStart, greaterThanOrEqualTo(0));
    expect(cardEnd, greaterThan(cardStart));
    final card = s.substring(cardStart, cardEnd);
    expect(card, contains("_metric('Hours'"));
    expect(card, contains("_metric('Gross'"));
    expect(card, contains("_metric('Paid'"));
    expect(card, contains("_metric('Balance'"));
    expect(card, contains("Text('Paid portion'"));
    expect(card, isNot(contains("_metric('Debt repaid'")));
    expect(card, isNot(contains("_metric('Transferred'")));

    // Recorded verified pay cannot establish the outstanding balance of
    // unrecorded tasks in that week. Do not invent a zero outstanding amount.
    expect(card, contains("_metric('Balance', '—'"));
    expect(s, contains("Text('Total paid · ' + _period"));
  });

  test('verified gross and net transfer/debt are not conflated', () {
    final s = File('lib/screens/payroll/payroll_history_panel.dart')
        .readAsStringSync();
    expect(s, contains("final paid = weeks.fold<int>(0, (sum, week) => sum + week.gross)"));
    expect(s, contains("_metric('Debt repaid', _money(week.repaid)"));
    expect(s, contains("_metric('Transferred', _money(week.net)"));
    expect(s, contains("int get net => _sum('net')"));
    expect(s, contains("int get repaid => _sum('repayment')"));
  });
}
