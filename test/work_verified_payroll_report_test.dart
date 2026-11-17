import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'paid Work summaries use saved payroll weeks and immutable coverage',
    () async {
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = LocalPayrollRepository(db, business: 'shop', owner: true);
      await repo.prepare();
      for (final (business, employee, reference, week, paidOn, rate) in [
        ('shop', 'chris', 'friday', '2026-11-09', '2026-11-13', 55000),
        ('shop', 'chris', 'sunday', '2026-11-09', '2026-11-15', 32000),
        ('shop', 'chris', 'reversed', '2026-11-09', '2026-11-13', 10000),
        ('shop', 'chris', 'earlier', '2026-11-02', '2026-11-09', 4000),
        ('shop', 'kam', 'different', '2026-11-09', '2026-11-13', 56000),
        ('other', 'chris', 'different', '2026-11-09', '2026-11-13', 20000),
      ]) {
        await db.customStatement(
          'INSERT INTO regular_payroll_payments VALUES(?,?,?,?,?,?,?,?,?,?)',
          [
            business,
            reference,
            employee,
            week,
            '{}',
            rate,
            0,
            rate,
            'Zelle',
            paidOn,
          ],
        );
      }
      for (final (ref, credit, minutes, cents) in [
        ('friday', 'first-credit', 480, 32000),
        ('friday', 'second-credit', 300, 23000),
        ('sunday', 'j56-credit', 480, 32000),
        ('reversed', 'other-credit', 150, 10000),
        ('earlier', 'earlier-credit', 60, 4000),
      ]) {
        // Old receipts can have no actual_minutes in the display snapshot.
        await db.customStatement(
          'INSERT INTO regular_payroll_work_coverage VALUES(?,?,?,?,?,?)',
          ['shop', credit, ref, minutes, cents, '{}'],
        );
      }
      await db.customStatement(
        'INSERT INTO regular_payroll_reversals_v1 VALUES(?,?,?,?,?)',
        ['shop', 'reversed', 'owner', 'Fixture reversal', '2026-11-14'],
      );
      final before = await db
          .customSelect(
            'SELECT * FROM regular_payroll_payments ORDER BY business_id,operation_id',
          )
          .get();
      final weeks = await repo.verifiedPayrollWeeks('chris');
      expect(weeks, {
        '2026-11-02': (minutes: 60, netCents: 4000),
        '2026-11-09': (minutes: 1260, netCents: 87000),
      });
      expect(weeks['2026-11-16'], isNull);
      expect(
        (await db
                .customSelect(
                  'SELECT * FROM regular_payroll_payments ORDER BY business_id,operation_id',
                )
                .get())
            .map((row) => row.data),
        before.map((row) => row.data),
      );
    },
  );
}
