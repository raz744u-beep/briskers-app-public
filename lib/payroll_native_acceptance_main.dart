import 'package:flutter/material.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'local/briskers_local_database.dart';
import 'services/integrated_test_payroll.dart';

/// Internal Android acceptance entry point, never the delivered application.
/// It uses the real native database and exact same payroll repository as the UI.
Future<String> verifyNativePayrollPersistence(BriskersLocalDatabase db) async {
  final r = IntegratedTestPayroll(db, business: 'android-acceptance-only');
  void check(bool condition, String message) {
    if (!condition) { throw StateError(message); }
  }
  await r.initializeEmployees();
  final previous = await r.history('chris');
  final phase = previous.isEmpty ? 'created' : 'reopened';
  if (previous.isEmpty) {
    await r.createJob('device-job', 'Android TEST car');
    await r.addLabor('device-job', 'labor', 'Device repair', 250);
    await r.assign('device-job/labor', 'chris');
    await r.assign('device-job/labor', 'kam');
    await r.updateWork('device-job/labor/chris', 'In Progress', 250, '2026-11-02');
    await r.updateWork('device-job/labor/chris', 'Done', 250, '2026-11-02');
    await r.addAdvance('chris', 3000);
    check(await r.verify(operation:'device-payment',employee:'chris',week:'2026-11-02',date:'2026-11-02',method:'Zelle',selected:await r.work(employee:'chris'),base:0,hourlyAdjustment:0,adjustmentReason:'',repayment:2000,confirmedNet:8000), 'First payment did not commit');
  }
  final history = await r.history('chris');
  check(history.length == 1, 'Payment missing or duplicated');
  check(history.single['gross'] == 10000 && history.single['repayment'] == 2000 && history.single['net'] == 8000, 'Payment totals changed');
  check(await r.advance('chris') == 1000, 'Advance balance changed');
  check((await r.jobs()).single['done'] == 0, 'Partial job incorrectly completed');
  check((await r.work(employee:'chris')).single['paid'] == 1, 'Paid credit lost');
  check((await r.work(employee:'kam')).single['state'] == 'Open', 'Other mechanic work changed');
  var rejected = false;
  try {
    await r.verify(operation:'duplicate-after-reboot',employee:'chris',week:'2026-11-02',date:'2026-11-02',method:'Zelle',selected:await r.work(employee:'chris'),base:0,hourlyAdjustment:0,adjustmentReason:'',repayment:0,confirmedNet:10000);
  } on StateError { rejected = true; }
  check(rejected, 'Duplicate payment was accepted');
  check((await r.history('chris')).length == 1, 'Duplicate payment created history');
  return phase;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home:Scaffold(body:Center(child:Text('Internal payroll acceptance — isolated TEST records')))));
  final db = BriskersLocalDatabase(driftDatabase(name:'payroll_device_acceptance'));
  try {
    final phase = await verifyNativePayrollPersistence(db);
    await db.close();
    debugPrint('PAYROLL_NATIVE_ACCEPTANCE_PASS phase=$phase gross=10000 repayment=2000 net=8000');
  } catch (error, stack) {
    debugPrint('PAYROLL_NATIVE_ACCEPTANCE_FAIL $error\n$stack');
    await db.close();
  }
}
