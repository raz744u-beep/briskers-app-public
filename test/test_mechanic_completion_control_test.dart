import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/core/shop_payroll_preview.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/test_payroll_credit_repository.dart';
import 'package:briskers_app/services/test_mechanic_completion_bridge.dart';
import 'package:briskers_app/widgets/test_mechanic_completion_control.dart';

void main() {
  testWidgets('TEST completion control persists only one mechanic completion',
      (tester) async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final credits = TestPayrollCreditRepository(database: db);
    await credits.seedSyntheticCredit(
      businessId: 'shop',
      credit: const ShopPayrollAllocation(
        id: 'portion-1', employeeId: 'mechanic',
        hoursHundredths: 125, rateCentsPerHour: 4000,
        completed: false, alreadyPaid: false,
      ),
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      TestMechanicCompletionControl(
        businessId: 'shop', employeeId: 'mechanic',
        allocationId: 'portion-1',
        bridge: TestMechanicCompletionBridge(credits: credits),
      ),
    )));
    await tester.tap(find.text('Mark TEST mechanic portion Done'));
    await tester.pumpAndSettle();
    expect(find.text('TEST mechanic portion marked Done.'), findsOneWidget);
    await tester.tap(find.text('Mark TEST mechanic portion Done'));
    await tester.pumpAndSettle();
    expect(find.text('No eligible unfinished TEST allocation found.'),
        findsOneWidget);
    expect(await credits.completedUnpaid(
      businessId: 'shop', employeeId: 'mechanic',
    ), hasLength(1));
  });
}
