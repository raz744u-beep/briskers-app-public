import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Done but unpaid labor remains Owner-editable; paid coverage is locked',
      () async {
    final payroll = await File('lib/services/local_payroll_repository.dart')
        .readAsString();
    final ui = await File('lib/screens/payroll/owner_payroll_screen.dart')
        .readAsString();

    // The task's completed state alone must not disable its pencil.
    expect(ui, isNot(contains("onPressed: _busy || conflict || removed || state=='Done'")));
    expect(ui, contains('onPressed: _busy || conflict || removed'));

    // The Owner correction reuses the existing immutable allocation. Its
    // earned/credited minutes and estimates update atomically, without
    // recording a new payment or creating another credit.
    expect(payroll, contains('reviseCompletedUnpaid:true'));
    expect(payroll, contains('bool reviseCompletedUnpaid = false'));
    expect(payroll, contains('owner_corrected_completed_unpaid_hours'));
    expect(payroll, contains('LocalMechanicWorkCreditRepository(database: db).recordWork('));
    expect(payroll, contains('regular_payroll_actual_time(business_id,credit_id,minutes,revision)'));
    expect(payroll, contains('ON CONFLICT(business_id,task_id,employee_id) DO UPDATE SET minutes=excluded.minutes'));

    // Payment checks continue to guard the full operation, not just the UI.
    expect(payroll, contains('c.paid_operation_id IS NULL'));
    expect(payroll, contains('NOT EXISTS(SELECT 1 FROM regular_payroll_work_coverage w'));
    expect(payroll, contains('Completed labor requires the Owner correction action.'));
    expect(payroll, contains('Completed labor must retain positive credited time.'));
  });
}
