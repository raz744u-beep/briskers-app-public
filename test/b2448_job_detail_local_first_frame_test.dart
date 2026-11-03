import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/job_detail_first_frame.dart';
import 'package:briskers_app/widgets/job_financial_status_card.dart';

void main() {
  test('authorized selected Jobs row retains correct vehicle and paid status before secondary local reads', () {
    final row = <String, dynamic>{
      'id': 'fixture-job-J7',
      'job_number': 'J-7',
      'customer_id': 'fixture-customer',
      'customer_name': 'Synthetic Customer',
      'vehicle_id': 'fixture-vehicle',
      'vehicle': '2013 BMW X5',
      'vehicle_vin': 'TESTVINONLY',
      'assigned_employee': 'Synthetic Mechanic',
      'assigned_employee_id': 'fixture-employee',
      'assigned_position': 'Mechanic',
      'status': 'completed',
      'payment_state': 'paid',
      'title': 'Fixture invoice',
      'planned_hours': 6,
    };
    final first = JobDetailFirstFrame.fromSelectedRow(
      row, expectedJobId: 'fixture-job-J7',
    )!;
    expect(first['vehicle'], '2013 BMW X5');
    expect(first['vehicle_vin'], 'TESTVINONLY');
    expect(first['customer_name'], 'Synthetic Customer');
    expect(first['job_number'], 'J-7');
    expect(savedJobFinancialStatus(first['payment_state']), 'Paid');
    expect((first['assignments'] as List).single['employee_name'],
        'Synthetic Mechanic');
    expect(first['_first_frame_only'], true);
    expect(first['capabilities'], isEmpty);
    expect(JobDetailFirstFrame.fromSelectedRow(row, expectedJobId: 'other'),
        isNull, reason: 'Never show a previous or different Job summary.');
  });

  testWidgets('Financial status is one compact line with fixed height and no delayed placeholder', (tester) async {
    Widget screen(String? value) => MaterialApp(
      home: Scaffold(
        body: Column(children: [
          JobFinancialStatusCard(status: value),
          const Text('First tile', key: ValueKey('first-tile')),
        ]),
      ),
    );
    await tester.pumpWidget(screen('Paid'));
    expect(find.text('Financial status'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('Checking payment status…'), findsNothing);
    expect(find.byType(ListTile), findsNothing,
        reason: 'A two-line ListTile would make this oversized again.');
    final card = find.byType(JobFinancialStatusCard);
    expect(tester.getSize(card).height, 50);
    final y = tester.getTopLeft(find.byKey(const ValueKey('first-tile'))).dy;
    await tester.pumpWidget(screen('Awaiting payment clearance'));
    expect(tester.getSize(card).height, 50);
    expect(tester.getTopLeft(find.byKey(const ValueKey('first-tile'))).dy, y);
    await tester.pumpWidget(screen(null));
    expect(find.text('Not verified'), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const ValueKey('first-tile'))).dy, y);
  });

  test('Job Detail uses authorized list preview immediately without granting editing permissions', () {
    final screen = File('lib/screens/jobs/job_detail_screen.dart')
        .readAsStringSync();
    final jobs = File('lib/services/local_job_repository.dart')
        .readAsStringSync();
    expect(screen, contains('JobDetailFirstFrame.fromSelectedRow('));
    expect(screen, contains('widget.initialJobSummary, expectedJobId: widget.jobId'));
    expect(screen, contains('_job = firstFrame;'));
    expect(screen, contains('_loading = false;'));
    expect(screen, contains("_job?['_first_frame_only'] != true"));
    expect(jobs, contains("'vehicle_vin': row.readNullable<String>('vehicle_vin')"));
    expect(jobs, contains("'customer_id': row.readNullable<String>('customer_id')"));
    expect(jobs, contains("'payment_state': row.readNullable<String>('payment_state')"));
    expect(screen, contains('documentsVerified = true;'));
    expect(screen, contains('_localJobs.saveVerifiedPaymentState('));
    expect(jobs, contains('Future<void> saveVerifiedPaymentState('));
    expect(jobs, contains("AND status = 'completed'"));
  });
}
