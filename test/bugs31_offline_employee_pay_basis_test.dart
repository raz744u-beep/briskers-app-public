import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Owner edits hourly and weekly pay locally without touching history', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    var owner = true;
    final repo = LocalPayrollRepository(db, business:'shop', owner:true,
      assertOwnerGrant: () {
        if (!owner) throw StateError('Owner signed out');
      });
    await repo.prepare();
    await repo.saveEmployeeCompensation(
      employee:'mechanic', name:'Synthetic Mechanic',rate:4000,weeklyBase:false);
    await repo.saveWeeklyDefaults('mechanic',0,4000,150,false);
    await repo.saveLocalPayBasis(employee:'mechanic',name:'Synthetic Mechanic',
      paymentType:'fixed_weekly',amountCents:80000);
    var staff=(await repo.employees()).single;
    var weekly=(await repo.weeklyDefaults('mechanic'))!;
    expect(staff['base_enabled'],1);
    expect(staff['rate'],0);
    expect(weekly['base_cents'],80000);
    expect(weekly['hourly_cents'],0);
    expect(weekly['add_labor'],0);
    expect(weekly['adjustment_cents'],150);
    await repo.saveLocalPayBasis(employee:'mechanic',name:'Synthetic Mechanic',
      paymentType:'hourly',amountCents:4500);
    staff=(await repo.employees()).single;
    weekly=(await repo.weeklyDefaults('mechanic'))!;
    expect(staff['base_enabled'],0);
    expect(staff['rate'],4500);
    expect(weekly['base_cents'],0);
    expect(weekly['hourly_cents'],4500);
    expect(weekly['add_labor'],1);
    expect(weekly['adjustment_cents'],150);
    expect(await repo.history('mechanic'),isEmpty);
    owner=false;
    await expectLater(repo.saveLocalPayBasis(
      employee:'mechanic',name:'Synthetic Mechanic',
      paymentType:'fixed_weekly',amountCents:90000),throwsStateError);
    expect((await db.customSelect(
      "SELECT rate FROM regular_payroll_employees WHERE business_id='shop'"
    ).getSingle()).read<int>('rate'),4500);
  });

  test('invalid payment type and amount cannot alter saved pay settings', () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo=LocalPayrollRepository(db,business:'shop',owner:true);
    await repo.prepare();
    for(final kind in ['weekly','none','other']) {
      await expectLater(repo.saveLocalPayBasis(
        employee:'m',name:'Synthetic',paymentType:kind,amountCents:100),
        throwsArgumentError);
    }
    await expectLater(repo.saveLocalPayBasis(
      employee:'m',name:'Synthetic',paymentType:'hourly',amountCents:-1),
      throwsArgumentError);
    expect(await repo.employees(),isEmpty);
  });
}
