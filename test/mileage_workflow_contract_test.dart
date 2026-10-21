import 'dart:io';

import 'package:briskers_app/core/mileage_workflow.dart';
import 'package:briskers_app/services/document_pdf_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registration and readings: missing stays missing, whole miles only', () {
    expect(MileageWorkflow.parse(null),isNull);
    expect(MileageWorkflow.parse(''),isNull);
    expect(MileageWorkflow.parse('0'),0);
    expect(MileageWorkflow.parse('125,010'),125010);
    expect(MileageWorkflow.parse('-1'),isNull);
    expect(MileageWorkflow.parse('NaN'),isNull);
    expect(MileageWorkflow.parse('125.5'),isNull);
    expect(MileageWorkflow.parse('10000000'),isNull);
  });

  test('PDF honors two explicit readings without fabricating a zero or out on estimates', () {
    expect(MileageWorkflow.printableReadings({
      'kind':'invoice','mileage_in':125010,'mileage_out':125025,
    }), [('Mileage In',125010),('Mileage Out',125025)]);
    expect(MileageWorkflow.printableReadings({
      'kind':'invoice','mileage_in':125010,
    }), [('Mileage In',125010)]);
    expect(MileageWorkflow.printableReadings({
      'kind':'invoice','mileage_out':125025,
    }), [('Mileage Out',125025)]);
    expect(MileageWorkflow.printableReadings({
      'kind':'estimate','mileage_in':125010,'mileage_out':125025,
    }), [('Mileage In',125010)]);
    expect(MileageWorkflow.printableReadings({
      'kind':'invoice','mileage_out':125025,'odometer_in':111111,
    }), [('Mileage Out',125025)]);
  });

  test('old imported invoices retain ambiguous Mileage, not a false Out', () {
    expect(MileageWorkflow.printableReadings({
      'kind':'invoice','odometer_in':89990,
    }), [('Mileage',89990)]);
    expect(MileageWorkflow.printableReadings({
      'kind':'invoice',
    }),isEmpty);
  });

  test('verified latest invoice only updates linked vehicle without regression', () {
    num? update(num? existing,num? outgoing,{bool complete=true,bool newest=true}) =>
       MileageWorkflow.currentVehicleMileageCandidate(
         previous:existing,mileageOut:outgoing,
         verifiedCompletedInvoice:complete,isLatestService:newest);
    expect(update(null,1001),1001);
    expect(update(1000,1100),1100);
    expect(update(1500,1100),isNull);
    expect(update(1000,null),isNull);
    expect(update(1000,1100,complete:false),isNull);
    expect(update(1000,1100,newest:false),isNull);
  });

  test('PDF uses centralized, historical-safe projection', () async {
    final src=await File('lib/services/document_pdf_service.dart').readAsString();
    expect(src,contains('MileageWorkflow.printableReadings(detail)'));
    expect(src, contains('for (final entry in odometerRows)'));
    expect(DocumentPdfService.fileName({'kind':'invoice','document_number':'6345'}),
        'Briskers-Invoice-6345.pdf');
  });
}
