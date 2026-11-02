import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/integrated_test_payroll.dart';
import 'package:briskers_app/tasks_payroll_integrated_main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native SQLite work and payment persist across Android reboot',(tester) async {
    const reopen=bool.fromEnvironment('PAYROLL_REOPEN');
    final db=BriskersLocalDatabase(driftDatabase(name:'payroll_device_acceptance'));
    final r=IntegratedTestPayroll(db);
    try {
      await r.initializeEmployees();
      if(!reopen) {
        await r.createJob('device-job','Device TEST car');
        await r.addLabor('device-job','labor','Device repair',250);
        await r.assign('device-job/labor','chris');
        await r.assign('device-job/labor','kam');
        await r.updateWork('device-job/labor/chris','In Progress',250,'2026-11-02');
        await r.updateWork('device-job/labor/chris','Done',250,'2026-11-02');
        await r.addAdvance('chris',3000);
        final selected=(await r.work(employee:'chris'));
        expect(await r.verify(operation:'device-payment',employee:'chris',week:'2026-11-02',date:'2026-11-02',method:'Zelle',selected:selected,base:0,hourlyAdjustment:0,adjustmentReason:'',repayment:2000,confirmedNet:8000),isTrue);
      }
      final history=await r.history('chris');
      expect(history,hasLength(1));expect(history.single['gross'],10000);expect(history.single['repayment'],2000);expect(history.single['net'],8000);
      expect(await r.advance('chris'),1000);
      expect((await r.jobs()).single['done'],0);
      expect((await r.work(employee:'chris')).single['paid'],1);
      expect((await r.work(employee:'kam')).single['state'],'Open');
      await expectLater(r.verify(operation:'duplicate-after-reboot',employee:'chris',week:'2026-11-02',date:'2026-11-02',method:'Zelle',selected:await r.work(employee:'chris'),base:0,hourlyAdjustment:0,adjustmentReason:'',repayment:0,confirmedNet:10000),throwsStateError);
      await tester.pumpWidget(MaterialApp(home:IntegratedPayrollHome(repository:r)));
      await tester.pumpAndSettle();
      expect(find.text('Device TEST car'),findsOneWidget);
      await tester.tap(find.text('Employee / Payroll'));await tester.pumpAndSettle();
      await tester.tap(find.text('Reports'));await tester.pumpAndSettle();
      expect(find.text('2026-11-02 • \$80.00 • Zelle'),findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    } finally {await db.close();}
  });
}
