import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/widgets/job_compact_card.dart';

void main() {
  testWidgets('vehicle and description share the initial Job card frame',
      (tester) async {
    final savedJob = <String, dynamic>{
      'id': 'synthetic-job',
      'job_number': 'J-TEST',
      'customer_name': 'Synthetic Customer',
      'vehicle': '2013 BMW X5',
      'title': 'Replace the cooling system',
      'requested_work': 'Customer reports overheating',
      'status': 'in_progress',
      'status_color': '#2585D8',
      'planned_hours': 6,
      'assigned_employee': 'Synthetic Mechanic',
    };

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: JobCompactCard(
          job: savedJob,
          statusControl: const Text('In progress'),
          onOpen: () {},
        ),
      ),
    ));

    expect(find.text('2013 BMW X5'), findsOneWidget);
    expect(find.text('Replace the cooling system'), findsOneWidget);
    expect(find.text('No vehicle'), findsNothing);
    expect(find.text('No description'), findsNothing);
  });

  test('Jobs first paint prioritizes complete SQLite rows, not metadata or remote pull', () {
    final jobs = File('lib/screens/jobs_screen.dart').readAsStringSync();
    final begin = jobs.indexOf('Future<void> readSavedJobs({required bool online})');
    final end = jobs.indexOf('if (!mode.forceOnline || !refreshRemote)', begin);
    expect(begin, greaterThan(0));
    expect(end, greaterThan(begin));
    final load = jobs.substring(begin, end);
    final query = load.indexOf('final rows = await _localJobs.listJobs(');
    final filter = load.indexOf('final visibleRows = await visibility.filter(rows)');
    final render = load.indexOf('_rows = visibleRows;');
    final count = load.indexOf('_localJobs.jobCount(');
    final afterFrame = load.indexOf('WidgetsBinding.instance.addPostFrameCallback');
    expect(query, greaterThan(0));
    expect(filter, greaterThan(query));
    expect(render, greaterThan(filter));
    expect(afterFrame, greaterThan(render));
    expect(count, greaterThan(afterFrame));
    expect(jobs, contains('await WidgetsBinding.instance.endOfFrame;'));
    expect(jobs.indexOf('await WidgetsBinding.instance.endOfFrame;'),
        lessThan(jobs.indexOf('await _jobSync.pull(businessId);')));

    final card = File('lib/widgets/job_compact_card.dart').readAsStringSync();
    expect(card, contains("final vehicle = job['vehicle']?.toString().trim() ?? '';"));
    expect(card, contains('final description = title.isNotEmpty ? title : requested;'));
    final repo = File('lib/services/local_job_repository.dart').readAsStringSync();
    expect(repo, contains("'title': row.read<String>('title')"));
    expect(repo, contains("'requested_work': row.readNullable<String>('requested_work')"));
    expect(repo, contains("'vehicle': row.readNullable<String>('vehicle_label')"));
  });
}
