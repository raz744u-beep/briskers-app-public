import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/document_copy_plan.dart';

void main() {
  final source = <String, dynamic>{
    'kind': 'invoice',
    'memo': 'Copied from INVOICE#2786\nMileage: 55625',
    'lines': <Map<String, dynamic>>[
      {'name': 'Oil Change', 'line_kind': 'item', 'quantity': 1,
       'unit_price': 160, 'tax_rate': 0.0925}
    ],
  };

  test('invoice copy excludes source reference notes by default', () {
    final copy = DocumentCopyPlan.prepare(source, customerId: 'customer-1',
      vehicleId: 'vehicle-1');
    expect(copy['memo'], isNull);
    expect(copy['lines'], hasLength(1));
    expect(copy['requires_new_job'], isTrue);
  });

  test('invoice copy includes original memo only with explicit opt in', () {
    final copy = DocumentCopyPlan.prepare(source, customerId: 'customer-1',
      vehicleId: 'vehicle-1', includeOriginalNotes: true);
    expect(copy['memo'], 'Copied from INVOICE#2786\nMileage: 55625');
  });

  test('estimate copies also exclude notes unless opted in', () {
    final copy = DocumentCopyPlan.prepare({
      ...source, 'kind': 'estimate',
    }, customerId: 'customer-1', vehicleId: null);
    expect(copy['memo'], isNull);
    expect(copy['requires_new_job'], isFalse);
  });
}
