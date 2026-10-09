import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/document_search.dart';

void main() {
  final invoices = <Map<String, dynamic>>[
    {
      'document_number': '6321',
      'customer_name': 'Alice',
      'job_number': 'MB-6011',
      'vehicle': 'Volvo XC90',
      'document_date': '2026-10-01',
    },
    {
      'document_number': '5321',
      'customer_name': '6321 Motors',
      'job_number': 'MB-6321',
      'vehicle': 'BMW 6321',
      'document_date': '2026-09-21',
    },
    {
      'document_number': '63210',
      'customer_name': 'Bob',
      'job_number': 'MB-6300',
    },
  ];
  test('numeric search matches only the exact invoice number', () {
    final result = invoices.where((row) => matchesDocumentSearch(row, '6321'));
    expect(result.map((row) => row['document_number']).toList(), ['6321']);
  });
  test('numeric document prefixes are equivalent, not partial', () {
    expect(normalizedDocumentNumber('I-006321'), BigInt.from(6321));
    expect(normalizedDocumentNumber('MB-6321'), BigInt.from(6321));
    expect(matchesDocumentSearch({'document_number': 'I-6321'}, '6321'), true);
    expect(matchesDocumentSearch({'document_number': '63210'}, '6321'), false);
  });
  test('customer and vehicle text search still works', () {
    expect(matchesDocumentSearch(invoices[1], 'motors'), true);
    expect(matchesDocumentSearch(invoices[0], 'volvo'), true);
    expect(matchesDocumentSearch(invoices[0], '6011'), false);
  });
  test('dates and status labels are not searched', () {
    expect(matchesDocumentSearch(invoices[0], '2026-10-01'), false);
    expect(matchesDocumentSearch({'document_number': '6321', 'display_status':'Paid'}, 'Paid'), false);
  });
}
