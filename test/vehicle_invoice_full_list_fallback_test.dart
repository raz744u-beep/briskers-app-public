import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/vehicle_invoice_repair_search.dart';

void main() {
  test('invoice rows are never hidden just because their repair details are empty', () {
    final invoice = <String, dynamic>{
      'id': 'legacy-6543',
      'kind': 'invoice',
      'document_number': '6543',
      'document_date': '2020-11-15',
      'vehicle_id': 'car-a',
      'lines': <Map<String, dynamic>>[],
    };
    final records = VehicleInvoiceRepairSearch.forVehicle(
      [invoice], vehicleId: 'car-a');
    expect(records, hasLength(1));
    expect(VehicleInvoiceRepairSearch.summary(records.single),
      'Description unavailable');
  });

  test('all individual repair lines can be shown under one invoice', () {
    final invoice = <String, dynamic>{
      'lines': [
        {'name': 'Labor', 'description': 'Left rear wheel speed sensor'},
        {'name': 'Water Pump', 'description': 'Replace coolant pump'},
        {'name': 'Thermostat', 'description': 'Replace thermostat'},
      ],
    };
    final repairs = VehicleInvoiceRepairSearch.repairDescriptions(invoice);
    expect(repairs, hasLength(3));
    expect(repairs[0], contains('wheel speed sensor'));
    expect(repairs[1], contains('Water Pump'));
    expect(repairs[2], contains('Thermostat'));
  });

  test('customer history includes browse-all, expandable repairs, unmatched group', () {
    final src = File(
      'lib/screens/customers/customer_service_history_section.dart'
    ).readAsStringSync();
    expect(src, contains('repair-history-expand-'));
    expect(src, contains('for (final repair in repairs)'));
    expect(src, contains('Unmatched customer invoices'));
    expect(src, contains('Vehicle not confirmed'));
    expect(src, contains('Open invoice to view repairs'));
  });
}
