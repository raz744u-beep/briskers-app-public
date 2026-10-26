import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/widgets/job_financial_status_card.dart';

Widget _screen(String? status, {bool offline = false}) => MaterialApp(
  home: Scaffold(
    body: Column(children: [
      JobFinancialStatusCard(status: status, offline: offline),
      const Text('Following job tiles', key: ValueKey('job-tiles-start')),
    ]),
  ),
);

void main() {
  test('first-frame status comes from the existing saved payment state, not a network spinner', () {
    expect(savedJobFinancialStatus('paid'), 'Paid');
    expect(savedJobFinancialStatus('PAID'), 'Paid');
    expect(savedJobFinancialStatus('awaiting_clearance'), 'Awaiting payment clearance');
    expect(savedJobFinancialStatus('awaiting_payment'), 'Awaiting payment');
    expect(savedJobFinancialStatus('invoice_needed'), 'Invoice needed');
    expect(savedJobFinancialStatus(null), isNull);
    expect(savedJobFinancialStatus(''), isNull);
    expect(savedJobFinancialStatus('bogus'), isNull);
  });

  testWidgets('completed paid Job paints the final label in the initial frame', (tester) async {
    await tester.pumpWidget(_screen(savedJobFinancialStatus('paid')));
    expect(find.text('Financial status'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('Checking payment status…'), findsNothing);
    expect(find.text('Payment status not verified offline'), findsNothing);
    final before = tester.getTopLeft(find.byKey(const ValueKey('job-tiles-start')));
    await tester.pumpWidget(_screen('Paid'));
    expect(tester.getTopLeft(find.byKey(const ValueKey('job-tiles-start'))).dy, before.dy);
  });
  testWidgets('completed Job financial card reserves identical height before and after payment verification', (tester) async {
    await tester.pumpWidget(_screen(null));
    expect(find.text('Financial status'), findsOneWidget);
    expect(find.text('Not verified'), findsOneWidget);
    expect(find.text('Paid'), findsNothing);
    final before = tester.getTopLeft(find.byKey(const ValueKey('job-tiles-start')));

    await tester.pumpWidget(_screen('Paid'));
    expect(find.text('Paid'), findsOneWidget);
    final after = tester.getTopLeft(find.byKey(const ValueKey('job-tiles-start')));
    expect(after.dy, before.dy,
        reason: 'Job tile positions must never move as remote payment totals arrive.');

    await tester.pumpWidget(_screen('Awaiting payment clearance'));
    expect(tester.getTopLeft(find.byKey(const ValueKey('job-tiles-start'))).dy,
        before.dy);
    await tester.pumpWidget(_screen('Invoice needed'));
    expect(tester.getTopLeft(find.byKey(const ValueKey('job-tiles-start'))).dy,
        before.dy);
  });

  testWidgets('unverified offline payment never silently presents Paid or Invoice needed', (tester) async {
    await tester.pumpWidget(_screen(null, offline: true));
    expect(find.text('Not verified'), findsOneWidget);
    expect(find.text('Paid'), findsNothing);
    expect(find.text('Invoice needed'), findsNothing);
  });

  test('Job Detail includes the placeholder for authorized completed jobs before online hydration', () {
    final source = File('lib/screens/jobs/job_detail_screen.dart').readAsStringSync();
    expect(source, contains("if (_canSeeFinancial &&\n              _job?['status']?.toString() == 'completed')"));
    expect(source, contains("savedJobFinancialStatus("));
    expect(source, contains("_job?['payment_state'] ?? widget.initialJobSummary?['payment_state']"));
    expect(source, contains('final status = _onlineReady ? (_completedPaymentLabel() ?? saved) : saved;'));
    expect(source, contains('return JobFinancialStatusCard('));
    expect(source, contains('offline: BriskersConnectionModeController.instance.forceOffline'));
    expect(source, contains("if (_job?['status']?.toString() != 'completed') return null;"));
    final repository = File('lib/services/local_job_repository.dart').readAsStringSync();
    final localDetail = repository.substring(
      repository.indexOf('Future<LocalJobDetailSnapshot?> jobDetail('),
      repository.indexOf('Map<String, dynamic> _jobListMap('),
    );
    expect(localDetail, contains("'payment_state': row.readNullable<String>('payment_state')"));
    expect(source, contains("row['kind']?.toString() == 'invoice'"));
    expect(source, contains('paid >= total - 0.005'));
  });
}
