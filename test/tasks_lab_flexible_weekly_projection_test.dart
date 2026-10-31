import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/tasks_lab/payroll_period_projection.dart';

void main() {
  final from = DateTime(2026, 10, 26);
  final until = DateTime(2026, 11, 2);

  test('weekly-base settlement appears without task-linked mechanic hours', () {
    final result = LabPayrollPeriodProjection.calculate(
      employeeId: 'secretary',
      from: from,
      until: until,
      hourlyRateCents: null,
      drafts: const [],
      payments: const [],
      taskPayments: const [],
      settlements: const [
        {'employee_id': 'secretary', 'week_key': '2026-10-26',
         'gross_cents': 60000},
      ],
    );
    expect(result.hours, isNull);
    expect(result.grossCents, 60000);
    expect(result.paidCents, 0);
    expect(result.balanceCents, 60000);
  });

  test('base-only settlement is included beside task-linked week', () {
    final result = LabPayrollPeriodProjection.calculate(
      employeeId: 'adam',
      from: from,
      until: DateTime(2026, 11, 9),
      hourlyRateCents: 2000,
      drafts: const [],
      payments: const [],
      taskPayments: const [
        {'employee_id': 'adam', 'week_key': '2026-10-26',
         'hours': 3.0},
      ],
      settlements: const [
        {'employee_id': 'adam', 'week_key': '2026-11-02',
         'gross_cents': 50000},
      ],
    );
    expect(result.hours, 3.0);
    expect(result.grossCents, 56000);
    expect(result.balanceCents, 56000);
  });
}
