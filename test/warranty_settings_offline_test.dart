import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_warranty_companies.dart';
import 'package:briskers_app/screens/settings/warranty_workflow_settings_screen.dart';
import 'package:briskers_app/widgets/briskers_dialog.dart';

void main() {
  testWidgets('Owner adds a company in Force Offline and can reopen it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await BriskersConnectionModeController.instance.setMode(BriskersConnectionMode.offline);
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final store = LocalWarrantyCompanies(database:db,canSync:()=>false);
    addTearDown(() async {
      await db.close();
      await BriskersConnectionModeController.instance.setMode(BriskersConnectionMode.auto);
    });
    tester.view.physicalSize=const Size(900,1600);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Future<void> settle() async {
      for (var i=0;i<20;i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds:10)));
        await tester.pump(const Duration(milliseconds:50));
      }
    }
    await tester.pumpWidget(MaterialApp(home:WarrantyWorkflowSettingsScreen(businessId:'shop',companies:store)));
    await settle();
    expect(find.textContaining('Network access is disabled'),findsNothing);
    await tester.tap(find.byTooltip('Add').first);
    await tester.pumpAndSettle();
    expect(find.byType(BriskersDialog),findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField).first).textCapitalization,TextCapitalization.words);
    await tester.enterText(find.byType(TextField).first,'endurance');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await settle();
    expect(find.text('Endurance'),findsOneWidget);
    await tester.tap(find.text('Endurance'));
    await tester.pumpAndSettle();
    expect(find.text('Edit warranty company'),findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle();
    expect(tester.takeException(),isNull);
  });
}
