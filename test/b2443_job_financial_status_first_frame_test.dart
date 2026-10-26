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
  testWidgets('completed Job financial card reserves identical height before and after payment verification', (tester) async {
    await tester.pumpWidget(_screen(null));
    expect(find.text('Financial status'), findsOneWidget);
    expect(find.text('Checking payment status…'), findsOneWidget);
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
    expect(find.text('Payment status not verified offline'), findsOneWidget);
    expect(find.text('Paid'), findsNothing);
    expect(find.text('Invoice needed'), findsNothing);
  });

  test('Job Detail includes the placeholder for authorized completed jobs before online hydration', () {
    final source = File('lib/screens/jobs/job_detail_screen.dart').readAsStringSync();
    expect(source, contains("if (_canSeeFinancial &&\n              _job?['status']?.toString() == 'completed')"));
    expect(source, contains('final status = _onlineReady ? _completedPaymentLabel() : null;'));
    expect(source, contains('return JobFinancialStatusCard('));
    expect(source, contains('offline: BriskersConnectionModeController.instance.forceOffline'));
    expect(source, contains("if (_job?['status']?.toString() != 'completed') return null;"));
    expect(source, contains("row['kind']?.toString() == 'invoice'"));
    expect(source, contains('paid >= total - 0.005'));
  });
}
