import 'dart:convert';
import 'dart:io';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/payroll_owner_ledger.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('first debt after wages, distinct repayment, adjustments, restart and canonical sharing', () async {
    final folder = await Directory.systemTemp.createTemp('synthetic-debt-');
    final file = File('${folder.path}/test.sqlite');
    var db = BriskersLocalDatabase(NativeDatabase(file));
    final replica = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(() async { await db.close(); await replica.close(); await folder.delete(recursive: true); });
    LocalPayrollRepository repository() => LocalPayrollRepository(db, business: 'test-shop', owner: true, deviceId: 'owner');
    var repo = repository();
    await repo.prepare();
    await repo.bindPaymentAuthority(writerDeviceId: 'owner', assertVerifiedPairing: () {});
    await repo.saveEmployeeCompensation(employee: 'test-employee', name: 'Synthetic mechanic', rate: 4000, weeklyBase: false);
    // Existing immutable wages are unrelated to debt initialization.
    await db.customStatement("INSERT INTO regular_payroll_payments VALUES('test-shop','prior-wages','test-employee','2026-11-09','{}',32000,0,32000,'Cash','2026-11-13')");
    final payments = jsonEncode(await repo.history('test-employee'));
    await repo.recordOpeningAdvance('test-employee', 160000);
    await expectLater(repo.recordOpeningAdvance('test-employee', 160000), throwsStateError);
    expect(await repo.advance('test-employee'), 160000);
    Future<void> repay() => repo.recordRepayment(employee: 'test-employee', operation: 'repayment-one', amount: 14000,
      date: '2026-11-20', method: 'Cash', note: 'Actual cash repayment');
    await repay(); await repay();
    expect(await repo.advance('test-employee'), 146000);
    expect(await repo.repaymentHistory('test-employee'), hasLength(1));
    Future<void> adjust() => repo.adjustAdvance(employee: 'test-employee', operation: 'correction-one',
      expectedCents: 146000, proposedCents: 132000, reason: 'Correct original debt; no money received');
    await adjust(); await adjust();
    expect(await repo.advance('test-employee'), 132000);
    expect(await repo.repaymentHistory('test-employee'), hasLength(1));
    expect(await repo.advanceAdjustments('test-employee'), hasLength(1));
    await expectLater(repo.adjustAdvance(employee: 'test-employee', operation: 'stale',
      expectedCents: 146000, proposedCents: 176000, reason: 'Stale form'), throwsStateError);
    await repo.adjustAdvance(employee: 'test-employee', operation: 'additional-loan',
      expectedCents: 132000, proposedCents: 162000, reason: 'Additional advance');
    expect(jsonEncode(await repo.history('test-employee')), payments);
    await db.close(); db = BriskersLocalDatabase(NativeDatabase(file)); repo = repository();
    expect(await repo.advance('test-employee'), 162000);
    expect(await repo.repaymentHistory('test-employee'), hasLength(1));
    final source = PayrollOwnerLedger(db, 'test-shop');
    final target = PayrollOwnerLedger(replica, 'test-shop');
    final snapshot = await source.export();
    await target.mergeSnapshot(snapshot, canonical: true);
    await target.mergeSnapshot(snapshot, canonical: true);
    final peer = LocalPayrollRepository(replica, business: 'test-shop', owner: true);
    expect(await peer.advance('test-employee'), 162000);
    expect(await peer.repaymentHistory('test-employee'), hasLength(1));
    expect(await peer.advanceAdjustments('test-employee'), hasLength(2));
    final denied = LocalPayrollRepository(db, business: 'test-shop', owner: false);
    await expectLater(denied.adjustAdvance(employee: 'test-employee', operation: 'denied',
      expectedCents: 162000, proposedCents: 0, reason: 'Denied'), throwsStateError);
    expect(jsonEncode(await repo.history('test-employee')), payments);
  });
}
