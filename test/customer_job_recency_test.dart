import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/services/customer_job_recency.dart';

void main() {
  test('newest J-21 comes before historical MobileBiz jobs', () {
    final rows = <Map<String, dynamic>>[
      {'id': 'mb3452', 'number': 'MB-3452', 'created_at': '2022-08-15T10:00:00Z'},
      {'id': 'mb5241', 'number': 'MB-5241', 'created_at': '2024-05-11T12:00:00Z'},
      {'id': 'j21', 'number': 'J-21', 'created_at': '2026-10-17T12:00:00Z'},
    ];
    rows.sort(compareCustomerJobRecency);
    expect(rows.map((r) => r['id']).toList(), ['j21', 'mb5241', 'mb3452']);
  });

  test('do not sort different job number namespaces by numeric value', () {
    final rows = <Map<String, dynamic>>[
      {'id': 'legacy', 'number': 'MB-5241', 'created_at': '2026-09-05T12:00:00Z'},
      {'id': 'native', 'number': 'J-21', 'created_at': '2026-10-17T12:00:00Z'},
    ];
    rows.sort(compareCustomerJobRecency);
    expect(rows.first['id'], 'native');
  });

  test('same-day native jobs use number descending as a stable tie break', () {
    final rows = <Map<String, dynamic>>[
      {'id': 'a', 'number': 'J-20', 'created_at': '2026-10-17'},
      {'id': 'b', 'number': 'J-21', 'created_at': '2026-10-17'},
    ];
    rows.sort(compareCustomerJobRecency);
    expect(rows.first['number'], 'J-21');
  });

  test('non-numbered offline job has a safe timestamp fallback', () {
    final rows = <Map<String, dynamic>>[
      {'id': 'old', 'number': 'Pending sync', 'created_at': '2026-10-16'},
      {'id': 'new', 'number': 'Pending sync', 'created_at': '2026-10-17'},
    ];
    rows.sort(compareCustomerJobRecency);
    expect(rows.first['id'], 'new');
  });
}
