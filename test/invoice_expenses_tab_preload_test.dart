import 'dart:convert';
import 'dart:io';

import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/local/briskers_local_database.dart' show BriskersLocalDatabase;
import 'package:briskers_app/local/local_database_provider.dart';
import 'package:briskers_app/screens/jobs/job_document_screen.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_document_sql_store.dart';
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => throw StateError('Invoice expense tab must stay offline');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BriskersLocalDatabase db;
  late HttpOverrides? previous;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db=BriskersLocalDatabase(NativeDatabase.memory());
    debugUseLocalDatabase(db);
    LocalDocumentDetailCache.sqliteWritesEnabled=true;
    previous=HttpOverrides.current; HttpOverrides.global=_NoNetwork();
    await BriskersConnectionModeController.instance.setMode(BriskersConnectionMode.offline);
    await db.customStatement("INSERT INTO local_jobs(id,business_id,access_scope,job_number,title,status,customer_id) VALUES('job','shop','full','J-60','Repair','open','customer')");
    await db.customStatement("INSERT INTO local_documents(id,business_id,job_id,customer_id,kind,document_number,status,total) VALUES('invoice','shop','job','customer','invoice','6380','issued',100)");
    await LocalDocumentSqlStore.write(db,LocalDocumentDetailCache.key('shop','invoice'),jsonEncode({
      'id':'invoice','business_id':'shop','kind':'invoice','job_id':'job','job_number':'J-60',
      'document_number':'6380','status':'issued','customer_name':'Saved customer',
      'total_amount':100,'paid_amount':0,'pending_payment':0,'document_date':'2026-11-17',
      'lines':[{'id':'line','name':'Repair','quantity':1,'unit_price':100,'net_amount':100,'line_kind':'part'}],
    }));
  });
  tearDown(() async {
    debugUseLocalDatabase(null); await db.close();
    HttpOverrides.global=previous;
    LocalDocumentDetailCache.sqliteWritesEnabled=false;
    await BriskersConnectionModeController.instance.setMode(BriskersConnectionMode.auto);
  });

  Future<void> settle(WidgetTester tester) async {
    for(var i=0;i<16;i++) {
      await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:25)));
      await tester.pump(const Duration(milliseconds:100));
    }
  }

  for(final populated in [false,true]) {
    testWidgets('invoice primes ${populated ? 'saved' : 'empty'} expenses before first tab visit', (tester) async {
      tester.view.physicalSize=const Size(412,915); tester.view.devicePixelRatio=1;
      addTearDown(tester.view.reset);
      await tester.runAsync(()=>LocalFinancialCache(database:db).saveLinkedExpenses('shop',[
        if(populated) {'id':'expense','business_id':'shop','job_id':'job','direction':'expense',
          'amount':25,'vendor':'Saved parts supplier','transaction_date':'2026-11-17','status':'posted'},
      ]));
      await tester.pumpWidget(const MaterialApp(home:JobDocumentScreen(
        businessId:'shop',documentId:'invoice',isOwner:true,canManageExpenses:true,roleCode:'owner')));
      await settle(tester);
      expect(find.text('6380'),findsWidgets);
      await tester.tap(find.text('Expenses').first);
      // Drain only animation frames, without letting SQLite finish a fresh read.
      await tester.pump(); await tester.pump(const Duration(milliseconds:300));
      expect(find.byType(CircularProgressIndicator).hitTestable(),findsNothing);
      expect(find.text(populated ? 'Saved parts supplier' : 'No expenses linked to this invoice or job.').hitTestable(),findsOneWidget);
      expect(tester.takeException(),isNull);
      await tester.pumpWidget(const SizedBox.shrink()); await settle(tester);
    });
  }
}
