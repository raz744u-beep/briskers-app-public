import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/local/briskers_local_database.dart' show BriskersLocalDatabase;
import 'package:briskers_app/local/local_database_provider.dart';
import 'package:briskers_app/screens/expenses_screen.dart';
import 'package:briskers_app/services/expense_filter_preferences.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Expense date choice survives screen destruction and cold preferences offline', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final mode = BriskersConnectionModeController.instance;
    await mode.setMode(BriskersConnectionMode.offline);
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    debugUseLocalDatabase(db);
    addTearDown(() async {
      debugUseLocalDatabase(null);
      await db.close();
      await mode.setMode(BriskersConnectionMode.auto);
    });
    Future<void> drain() async {
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 20));
      }
    }
    const screen = MaterialApp(home: ExpensesScreen(businessId: 'shop', roleCode: 'secretary'));
    await tester.pumpWidget(screen);
    await drain();
    await tester.tap(find.text('All Time'));
    await drain();
    await tester.tap(find.text('Last 30 days'));
    await drain();
    expect((await ExpenseFilterPreferences.load('shop', 'secretary')).dateRange, '30d');
    await tester.pumpWidget(const SizedBox.shrink());
    await drain();
    final prefs = await SharedPreferences.getInstance();
    final disk = {for (final key in prefs.getKeys()) key: prefs.get(key)!};
    SharedPreferences.setMockInitialValues(disk);
    await tester.pumpWidget(screen);
    await drain();
    expect(find.text('30 days'), findsOneWidget);
    expect(find.text('All Time'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await drain();
  });
}
