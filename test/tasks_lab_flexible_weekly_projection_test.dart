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
  test('known settlement remains visible when separate hours lack a rate', () {
    final result = LabPayrollPeriodProjection.calculate(
      employeeId: 'adam',
      from: DateTime(2026, 10, 26),
      until: DateTime(2026, 11, 9),
      hourlyRateCents: null,
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
    expect(result.grossCents, 50000);
    expect(result.balanceCents, isNull);
  });

  test('weekly payroll uses net transfer, not gross, as paid cash', () {
    final result = LabPayrollPeriodProjection.calculate(
      employeeId: 'secretary',
      from: from,
      until: until,
      hourlyRateCents: null,
      drafts: const [],
      payments: [
        {'employee_id': 'secretary', 'kind': 'pay',
         'paid_at': DateTime(2026, 10, 28).millisecondsSinceEpoch,
         'cents': 8500},
      ],
      taskPayments: const [],
      settlements: const [
        {'employee_id': 'secretary', 'week_key': '2026-10-26',
         'gross_cents': 10500},
      ],
    );
    expect(result.grossCents, 10500);
    expect(result.paidCents, 8500);
  });

  test('advance deduction settles wages without inflating cash paid', () {
    final result = LabPayrollPeriodProjection.calculate(
      employeeId: 'secretary',
      from: from,
      until: until,
      hourlyRateCents: null,
      drafts: const [],
      payments: [
        {'employee_id': 'secretary', 'kind': 'pay',
         'paid_at': DateTime(2026, 10, 28).millisecondsSinceEpoch,
         'cents': 8500},
      ],
      taskPayments: const [],
      settlements: const [
        {'employee_id': 'secretary', 'week_key': '2026-10-26',
         'gross_cents': 10500, 'debt_cents': 2000},
      ],
    );
    expect(result.grossCents, 10500);
    expect(result.paidCents, 8500);
    expect(result.balanceCents, 0);
  });

  test('paid total excludes repayment and nonpositive pay entries', () {
    final result = LabPayrollPeriodProjection.calculate(
      employeeId: 'chris',
      from: from,
      until: until,
      hourlyRateCents: 4000,
      drafts: const [],
      payments: [
        {'employee_id': 'chris', 'kind': 'pay',
         'paid_at': DateTime(2026, 10, 28).millisecondsSinceEpoch,
         'cents': 8500},
        {'employee_id': 'chris', 'kind': 'repayment',
         'paid_at': DateTime(2026, 10, 28).millisecondsSinceEpoch,
         'cents': 2000},
        {'employee_id': 'chris', 'kind': 'pay',
         'paid_at': DateTime(2026, 10, 28).millisecondsSinceEpoch,
         'cents': -500},
      ],
      taskPayments: const [
        {'employee_id': 'chris', 'week_key': '2026-10-26',
         'hours': 2.5},
      ],
    );
    expect(result.hours, 2.5);
    expect(result.grossCents, 10000);
    expect(result.paidCents, 8500);
    expect(result.balanceCents, 1500);
  });

}
