import 'dart:io';

import 'package:briskers_app/services/finding_job_choice_policy.dart';
import 'package:briskers_app/widgets/vehicle_findings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _noop(Map<String, dynamic> finding) async {}

void main() {
  test('completed and closed Jobs are eligible only as historic resolutions', () {
    for (final status in ['completed', 'closed', 'Completed', ' CLOSED ']) {
      expect(
        findingJobChoice(status, resolving: true),
        FindingJobChoice.completedHistory,
      );
      expect(
        findingJobChoice(status, resolving: false),
        FindingJobChoice.unavailable,
      );
    }
    for (final status in ['in_progress', 'pending_approval', 'waiting_parts',
      'needs_recheck']) {
      expect(findingJobChoice(status, resolving: true),
          FindingJobChoice.active);
      expect(findingJobChoice(status, resolving: false),
          FindingJobChoice.active);
    }
    for (final status in ['cancelled', 'canceled', 'deleted', 'voided']) {
      expect(findingJobChoice(status, resolving: true),
          FindingJobChoice.unavailable);
    }
  });

  test('completed Job selection requires confirmation and scoped vehicle', () {
    final source = File(
      'lib/screens/customers/customer_vehicle_findings_section.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<String?> _chooseFindingJob(');
    final end = source.indexOf('Future<void> _changeFinding(', start);
    final picker = source.substring(start, end);
    expect(picker, contains('business_id=? AND customer_id=? AND vehicle_id=?'));
    expect(picker, contains("row['customer_id']?.toString() == widget.customerId"));
    expect(picker, contains("row['vehicle_id']?.toString() == vehicleId"));
    expect(picker, contains('_jobVisibility.filter(jobs)'));
    expect(picker, contains('FindingJobChoice.completedHistory'));
    expect(picker, contains('findingJobChoice(job[\'status\'], resolving: resolving)'));
    expect(picker, contains('Completed Jobs — historical repair'));
    expect(picker, contains("confirmed != true"));
    expect(picker, contains('Confirm resolved'));
    expect(picker, contains('It will NOT reopen the'));
    final addStart = source.indexOf('Future<void> _addFindingToJob(');
    final resolveStart = source.indexOf('Future<void> _resolveFinding(');
    expect(source.substring(addStart, resolveStart),
        contains('_chooseFindingJob(finding);'));
    expect(source.substring(resolveStart, resolveStart + 220),
        contains('_chooseFindingJob(finding, resolving: true)'));
  });

  test('resolution persists server historical link without marking In Job', () {
    final source = File('lib/services/vehicle_finding_actions_service.dart')
        .readAsStringSync();
    final resolveStart = source.indexOf('Future<Map<String, dynamic>> resolve(');
    final reopenStart = source.indexOf('Future<Map<String, dynamic>> reopen(',
        resolveStart);
    final resolve = source.substring(resolveStart, reopenStart);
    expect(resolve, contains("'resolved_job_id': jobId"));
    expect(resolve, contains("'include_on_invoice': false"));
    expect(resolve, isNot(contains("'repair_job_id': jobId")));
    expect(source, contains("server['resolved_job_id']?.toString() == jobId"));
    expect(source, contains("'resolved_job_number',"));
  });

  testWidgets('resolved history shows the Job number when server confirms it',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: VehicleFindings(
            findings: const [
              {
                'id': 'finding-1',
                'status': 'resolved',
                'resolved_job_id': 'job-1',
                'resolved_job_number': 'J-42',
                'body': 'Historical repair validated',
              },
            ],
            canManage: false,
            canEdit: false,
            canIncludeOnInvoice: false,
            onEdit: _noop,
            onAddPhotos: _noop,
            onAddToJob: _noop,
            onResolve: _noop,
            onReopen: _noop,
            onInvoiceChanged: (_, __) async {},
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('vehicle-findings-resolved')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Job J-42'), findsOneWidget);
    expect(find.text('Historical repair validated'), findsOneWidget);
  });
}
