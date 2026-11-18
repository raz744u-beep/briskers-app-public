import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/local/local_database_provider.dart';
import 'package:briskers_app/screens/settings/diagnostics_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Owner inspects the invoice they enter instead of the old fixed J18 audit', (tester) async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    debugUseLocalDatabase(db);
    addTearDown(() async {
      debugUseLocalDatabase(null);
      await db.close();
    });
    await db.customStatement("INSERT INTO local_jobs(id,business_id,access_scope,job_number,title,status,customer_id) "
      "VALUES('dakota-job','shop','full','J-41','Original','completed','dakota'),"
      "('tyra-job','shop','full','J-41','Newer','open','tyra')");
    await db.customStatement("INSERT INTO local_documents(id,business_id,job_id,customer_id,kind,document_number,total) "
      "VALUES('dakota-invoice','shop','dakota-job','dakota','invoice','6360',554.24),"
      "('tyra-invoice','shop','tyra-job','tyra','invoice','6360',4894.21)");
    final before = (await db.customSelect('SELECT * FROM local_documents ORDER BY id').get()).map((r)=>r.data).toList();
    await tester.pumpWidget(const MaterialApp(home: DiagnosticsScreen(businessId:'shop',roleCode:'owner')));
    await tester.enterText(find.byType(TextField).first,'6360');
    tester.testTextInput.hide();
    final inspect = find.text('Inspect saved invoice links');
    await tester.ensureVisible(inspect);
    await tester.tap(inspect);
    await tester.pumpAndSettle();
    final report = tester.widget<SelectableText>(find.byType(SelectableText)).data!;
    expect(report,contains('READ ONLY — Invoice #6360'));
    expect(report,contains('Matching invoice-number references: 2'));
    expect(report,contains('dakota-invoice'));
    expect(report,contains('tyra-invoice'));
    expect(find.text('Inspect local J-18 link'),findsNothing);
    expect(find.text('Copy private report'),findsOneWidget);
    expect((await db.customSelect('SELECT * FROM local_documents ORDER BY id').get()).map((r)=>r.data).toList(),before);
  });

  testWidgets('non-Owner cannot access invoice audit controls', (tester) async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    debugUseLocalDatabase(db);
    addTearDown(() async {
      debugUseLocalDatabase(null);
      await db.close();
    });
    await tester.pumpWidget(const MaterialApp(home: DiagnosticsScreen(businessId:'shop',roleCode:'mechanic')));
    expect(find.byType(TextField),findsNothing);
    expect(find.text('Inspect saved invoice links'),findsNothing);
    expect(find.text('Diagnostics is restricted to the Owner / developer account.'),findsOneWidget);
  });
}
