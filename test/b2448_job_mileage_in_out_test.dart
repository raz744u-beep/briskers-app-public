import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/job_mileage_summary.dart';
import 'package:briskers_app/widgets/job_mileage_row.dart';

void main() {
  test('Mileage In shares the existing Job/pre-inspection intake reading', () {
    expect(JobMileageSummary.mileageIn({'odometer_in': 84250}, null), 84250);
    expect(JobMileageSummary.mileageIn(
      {'odometer_in': 84250}, {'odometer': 84266}), 84266);
    expect(JobMileageSummary.mileageIn({}, null), isNull);
    expect(JobMileageSummary.mileageIn({'odometer_in': 'invalid'}, null), isNull);
  });

  test('Mileage Out must be explicit v2 and scoped to the exact Job/vehicle', () {
    const invoice = {
      'kind': 'invoice',
      'job_id': 'fixture-job',
      'vehicle_id': 'fixture-car',
      'mileage_schema_version': 2,
      'mileage_out': 84312,
      'odometer_in': 84250,
    };
    num? read(Map<String, dynamic> v) =>
        JobMileageSummary.mileageOutFromInvoice(v,
          jobId: 'fixture-job', vehicleId: 'fixture-car');

    expect(read(invoice), 84312);
    expect(read({...invoice, 'job_id': 'other'}), isNull);
    expect(read({...invoice, 'vehicle_id': 'other'}), isNull);
    expect(read({...invoice, 'kind': 'estimate'}), isNull);
    expect(read({'kind': 'invoice', 'job_id': 'fixture-job',
       'vehicle_id': 'fixture-car', 'odometer_in': 84312}), isNull,
       reason: 'Ambiguous legacy odometer is not Mileage Out.');
    expect(read({...invoice, 'mileage_out': null}), isNull);
    expect(read({...invoice, 'mileage_out': -1}), isNull);
    expect(read({...invoice, 'mileage_out': 'invalid'}), isNull);
    expect(read({...invoice, 'mileage_out': 99999999}), isNull);
  });

  testWidgets('one compact Job mileage row shows both readings and never shifts lower tiles',
      (tester) async {
    var inTaps = 0;
    var outTaps = 0;
    Widget screen(num? incoming, num? outgoing) => MaterialApp(
      home: Scaffold(
        body: Column(children: [
          JobMileageRow(
            mileageIn: incoming,
            mileageOut: outgoing,
            onEditIn: () => inTaps++,
            onOpenOut: () => outTaps++,
          ),
          const Text('Job tiles', key: ValueKey('following-tiles')),
        ]),
      ),
    );
    await tester.pumpWidget(screen(84250, null));
    expect(find.text('Mi. In: 84,250'), findsOneWidget);
    expect(find.text('Mi. Out: —'), findsOneWidget);
    final before = tester.getTopLeft(find.byKey(const ValueKey('following-tiles'))).dy;
    await tester.pumpWidget(screen(84250, 84312));
    expect(find.text('Mi. Out: 84,312'), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const ValueKey('following-tiles'))).dy, before);
    await tester.tap(find.text('Mi. In: 84,250'));
    await tester.tap(find.text('Mi. Out: 84,312'));
    expect(inTaps, 1);
    expect(outTaps, 1);
    await tester.pumpWidget(screen(null, null));
    expect(find.text('Mi. In: —'), findsOneWidget);
    expect(find.text('Mi. Out: —'), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const ValueKey('following-tiles'))).dy, before);
  });

  test('Job Detail reuses existing mileage editors and caches, no new accounting storage', () {
    final detail = File('lib/screens/jobs/job_detail_screen.dart').readAsStringSync();
    final jobs = File('lib/services/local_job_repository.dart').readAsStringSync();
    final first = File('lib/services/job_detail_first_frame.dart').readAsStringSync();
    expect(detail, contains('child: JobMileageRow('));
    expect(detail, contains('JobMileageSummary.mileageIn(_job, _preInspection)'));
    expect(detail, contains('onEditIn: _canEditInspection && !_busy'));
    expect(detail, contains('onOpenOut: _canSeeFinancial && !_busy'));
    expect(detail, contains('JobMileageSummary.mileageOutFromInvoice('));
    expect(detail, contains('await _documentDetailCache.load('));
    expect(detail, contains('await _invoiceMileage.project('));
    expect(jobs, contains("'odometer_in': row.data['odometer_in']"));
    expect(first, contains("'odometer_in': row['odometer_in']"));
    expect(detail, contains('if (!_currentLoad(epoch)) return;'));
  });
}
