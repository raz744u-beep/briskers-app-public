import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/services/customer_document_recency.dart';

void main() {
  test('recent customer documents use original business date, not sync timestamp', () {
    final rows = <Map<String, dynamic>>[
      {'id': 'old', 'type': 'invoice', 'number': 'I-6000',
        'document_date': '2025-08-04', 'server_updated_at': '2026-10-18T01:00:00Z'},
      {'id': 'new', 'type': 'invoice', 'number': 'I-6350',
        'document_date': '2026-10-17', 'server_updated_at': '2026-10-17T12:00:00Z'},
      {'id': 'estimate', 'type': 'estimate', 'number': 'E-2002',
        'document_date': '2026-10-16', 'server_updated_at': '2026-10-16T12:00:00Z'},
    ];
    rows.sort(compareCustomerDocumentRecency);
    expect(rows.map((r) => r['id']).toList(), ['new','estimate','old']);
  });

  test('same-day invoices and estimates use highest number first by kind', () {
    final rows = <Map<String, dynamic>>[
      {'id': 'i1', 'type': 'invoice', 'number': 'I-6349',
        'document_date': '2026-10-17'},
      {'id': 'i2', 'type': 'invoice', 'number': 'I-6350',
        'document_date': '2026-10-17'},
      {'id': 'e1', 'type': 'estimate', 'number': 'E-1999',
        'document_date': '2026-10-16'},
      {'id': 'e2', 'type': 'estimate', 'number': 'E-2002',
        'document_date': '2026-10-16'},
    ];
    rows.sort(compareCustomerDocumentRecency);
    expect(rows.map((r) => r['id']).toList(), ['i2','i1','e2','e1']);
  });

  test('un-numbered documents fall back to timestamps without crashing', () {
    final rows = <Map<String, dynamic>>[
      {'id': 'draft-older', 'type': 'invoice',
       'server_updated_at': '2026-10-14T10:00:00Z'},
      {'id': 'draft-newer', 'type': 'invoice',
       'server_updated_at': '2026-10-17T10:00:00Z'},
    ];
    rows.sort(compareCustomerDocumentRecency);
    expect(rows.first['id'], 'draft-newer');
  });
}
