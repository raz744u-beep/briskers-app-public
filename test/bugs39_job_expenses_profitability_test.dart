import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/local/briskers_local_database.dart' show BriskersLocalDatabase;
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_document_sql_store.dart';
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:briskers_app/services/local_job_profitability.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/offline_financial_write_service.dart';

Map<String, dynamic> invoice({String id = 'invoice-6360', String kind = 'invoice'}) => {
  'id': id, 'business_id': 'shop', 'job_id': 'job-41',
  'kind': kind, 'status': 'closed', 'document_number': '6360',
  'total_amount': 1080, 'tax_amount': 80,
  'paid_amount': 1080, 'pending_payment': 0,
  'lines': [{'line_kind': 'labor', 'quantity': 4, 'net_amount': 400}],
  'payments': [{'id': 'original-customer-payment', 'amount': 1080, 'method': 'Cash'}],
};
Map<String, dynamic> expense(String id, num amount, {String? job = 'job-41'}) => {
  'id': id, 'business_id': 'shop', 'job_id': job,
  'direction': 'expense', 'amount': amount, 'status': 'posted',
  'transaction_date': '2026-11-18', 'counterparty': 'Parts supplier',
};
Map<String, dynamic> labor({int paid = 3000, int paidMinutes = 60,
  int minutes = 240, int rate = 3500}) => {
  'id': 'credit', 'business_id': 'shop', 'job_id': 'job-41',
  'actual_minutes': minutes, 'rate_cents': rate, 'completed': 1,
  'paid_cents': paid, 'paid_minutes': paidMinutes, 'source_active': 1,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await BriskersConnectionModeController.instance.setMode(BriskersConnectionMode.offline);
  });
  tearDown(() async {
    LocalDocumentDetailCache.sqliteWritesEnabled = false;
    await BriskersConnectionModeController.instance.setMode(BriskersConnectionMode.auto);
  });

  test('J-41 synthetic report excludes tax once, freezes paid cost and ignores customer receipts as revenue', () {
    final original = invoice();
    final before = jsonEncode(original);
    final report = LocalJobProfitability.fromRecords(
      business: 'shop', job: 'job-41',
      invoices: [original, original, invoice(kind: 'estimate')],
      expenses: [expense('parts', 250), expense('parts', 250),
        {...expense('payroll-whole-week', 900), 'payroll_operation_id': 'weekly'},
        {...expense('customer-money', 1080), 'direction': 'income'},
        expense('another-job', 1000, job: 'other-job')],
      labor: [labor(), labor()],
    );
    expect(report.revenueCents, 100000);
    expect(report.taxCents, 8000);
    expect(report.directCents, 25000);
    expect(report.laborCents, 13500);
    expect(report.profitCents, 61500);
    expect(report.margin, 61.5);
    expect(jsonEncode(original), before);
  });

  test('missing tax, hourly cost or invoice details remain unknown instead of fabricated zero profit', () {
    final missingTax = invoice()..remove('tax_amount');
    final report = LocalJobProfitability.fromRecords(
      business: 'shop', job: 'job-41', invoices: [missingTax],
      expenses: [], labor: [labor(paid: 0, paidMinutes: 0, rate: 0)],
    );
    expect(report.revenueCents, isNull);
    expect(report.laborCents, isNull);
    expect(report.profitCents, isNull);
    expect(report.issues, hasLength(2));
    final noLabor = LocalJobProfitability.fromRecords(
      business: 'shop', job: 'job-41', invoices: [invoice()],
      expenses: [], labor: [],
    );
    expect(noLabor.laborCents, isNull);
  });

  test('inactive historical duplicates, void expenses and other shops never inflate costs', () {
    final report = LocalJobProfitability.fromRecords(
      business: 'shop', job: 'job-41', invoices: [invoice()],
      expenses: [{...expense('voided', 1000), 'status': 'void'},
        {...expense('reversed', 1000), 'sync_state': 'reversed'},
        {...expense('other-shop', 1000), 'business_id': 'other'}],
      labor: [labor(paid: 14000, paidMinutes: 240, rate: 9999),
        {...labor(paid: 0, paidMinutes: 0), 'id': 'duplicate', 'duplicate_of_task_id': 'original'},
        {...labor(paid: 0, paidMinutes: 0), 'id': 'inactive', 'source_active': 0}],
    );
    expect(report.directCents, 0);
    expect(report.laborCents, 14000);
    expect(report.profitCents, 86000);
  });

  test('split allocations keep their job shares through acknowledgment and stale history', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final cache = LocalFinancialCache(database: db);
      await cache.saveLinkedExpenses('shop', [
        {...expense('split', 40), 'allocation_id': 'share-a'},
        {...expense('split', 60, job: 'other-job'), 'allocation_id': 'share-b'},
      ]);
      await cache.saveTransactions('shop', [{...expense('split', 100), 'sync_state': 'synced'}]);
      final selected = await cache.loadLinkedExpenses('shop', jobId: 'job-41');
      expect(selected, hasLength(1));
      expect(selected!.single['amount'], 40);
      expect((await cache.loadLinkedExpenses('shop', jobId: 'other-job'))!.single['amount'], 60);
      // An explicit pending reassignment is authoritative until synchronization.
      await cache.saveTransactions('shop', [{...expense('split', 125), 'sync_state': 'pending'}]);
      expect((await cache.loadLinkedExpenses('shop', jobId: 'job-41'))!.single['amount'], 125);
      expect(await cache.loadLinkedExpenses('shop', jobId: 'other-job'), isEmpty);
    } finally { await db.close(); }
  });

  test('invoice-only and acknowledged local expenses remain visible once; unlink and void are respected', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final cache = LocalFinancialCache(database: db);
      final saved = {...expense('local-expense', 100, job: null),
        'document_id': 'invoice-6360', 'sync_state': 'synced'};
      await cache.saveTransactions('shop', [saved]);
      var rows = await cache.loadLinkedExpenses('shop',
        jobId: 'job-41', documentIds: {'invoice-6360'});
      expect(rows, hasLength(1));
      await cache.saveLinkedExpenses('shop', [{...saved, 'allocation_id': 'server-allocation'}]);
      rows = await cache.loadLinkedExpenses('shop',
        jobId: 'job-41', documentIds: {'invoice-6360'});
      expect(rows, hasLength(1));
      await cache.saveTransactions('shop', [{...saved, 'document_id': null, 'sync_state': 'pending'}]);
      expect(await cache.loadLinkedExpenses('shop',
        jobId: 'job-41', documentIds: {'invoice-6360'}), isEmpty);
    } finally { await db.close(); }
  });

  test('Force Offline creates a linked expense and receipt, recalculates, and survives restart without new payments', () async {
    final directory = await Directory.systemTemp.createTemp('job-profitability');
    final file = File('${directory.path}/shop.sqlite');
    var db = BriskersLocalDatabase(NativeDatabase(file));
    try {
      await LocalPayrollRepository(db, business: 'shop', owner: true).prepare();
      await db.customStatement(
        "INSERT INTO local_jobs(id,business_id,access_scope,title,status,job_number) VALUES('job-41','shop','owner','Synthetic Tyra job','completed','J-41')");
      await db.customStatement(
        "INSERT INTO local_documents(id,business_id,job_id,kind,document_number,status,total) VALUES('invoice-6360','shop','job-41','invoice','6360','closed',1080)");
      final frozen = jsonEncode(invoice());
      LocalDocumentDetailCache.sqliteWritesEnabled = true;
      await LocalDocumentSqlStore.write(db, LocalDocumentDetailCache.key('shop', 'invoice-6360'), frozen);
      await db.customStatement(
        'INSERT INTO local_mechanic_work_credits_v1 '
        '(business_id,allocation_id,job_id,labor_line_id,task_id,employee_id,actual_minutes,rate_cents,completed,paid_operation_id,revision) '
        'VALUES(?,?,?,?,?,?,?,?,?,?,?)',
        ['shop','credit','job-41','labor','task','kam',240,9999,1,'weekly',1]);
      await db.customStatement(
        'INSERT INTO regular_payroll_payments VALUES(?,?,?,?,?,?,?,?,?,?)',
        ['shop','weekly','kam','2026-11-09','{}',14000,0,14000,'Cash','2026-11-13']);
      await db.customStatement(
        'INSERT INTO regular_payroll_work_coverage VALUES(?,?,?,?,?,?)',
        ['shop','credit','weekly',240,14000,jsonEncode({'actual_minutes':240,'gross_cents':14000})]);
      Future<String> protectedRecords() async => jsonEncode([
        for (final table in ['regular_payroll_payments','regular_payroll_work_coverage','local_documents'])
          (await db.customSelect('SELECT * FROM $table ORDER BY rowid').get()).map((r) => r.data).toList(),
        (await db.customSelect('SELECT payload_json FROM local_document_details').get()).map((r) => r.data).toList(),
      ]);
      final originalRecords = await protectedRecords();
      var report = await LocalJobProfitabilityRepository(db).load('shop','job-41',isOwner:true);
      expect(report.profitCents, 86000);
      final bytes = Uint8List.fromList([255,216,1,2,255,217]);
      final created = await OfflineFinancialWriteService(
        database: db, mediaDirectoryProvider: () async => directory,
      ).createLocalTransaction(
        'shop', direction:'expense', accountId:'checking', accountName:'Checking',
        categoryId:'parts', categoryName:'Parts', amount:250,
        date:DateTime(2026,11,18), jobId:'job-41', documentId:'invoice-6360',
        contextLabel:'Job J-41', counterpartyName:'Parts supplier',
        receipts:[{'filename':'receipt.jpg','mime_type':'image/jpeg','bytes':bytes}],
      );
      final attachment = (created['attachments'] as List).single as Map;
      final photo = File(attachment['local_file_path'] as String);
      expect(await photo.readAsBytes(), bytes);
      for (var retry = 0; retry < 3; retry++) {
        report = await LocalJobProfitabilityRepository(db).load('shop','job-41',isOwner:true);
        expect(report.revenueCents, 100000);
        expect(report.directCents, 25000);
        expect(report.laborCents, 14000);
        expect(report.profitCents, 61000);
        expect(report.expenses, hasLength(1));
      }
      expect(await protectedRecords(), originalRecords);
      final queued = (await db.customSelect('SELECT COUNT(*) AS n FROM sync_outbox').getSingle()).read<int>('n');
      await db.close();
      db = BriskersLocalDatabase(NativeDatabase(file));
      report = await LocalJobProfitabilityRepository(db).load('shop','job-41',isOwner:true);
      expect(report.profitCents, 61000);
      expect(report.expenses.single['id'], created['id']);
      expect(await protectedRecords(), originalRecords);
      expect((await db.customSelect('SELECT COUNT(*) AS n FROM sync_outbox').getSingle()).read<int>('n'), queued);
      expect(await photo.readAsBytes(), bytes);
      final cache = LocalFinancialCache(database: db);
      final rows = await cache.loadTransactions('shop');
      await cache.saveTransactions('shop', [for (final row in rows) {...row,'sync_state':'synced'}]);
      await cache.saveLinkedExpenses('shop', [{...created,'allocation_id':'server-allocation','sync_state':'synced'}]);
      report = await LocalJobProfitabilityRepository(db).load('shop','job-41',isOwner:true);
      expect(report.profitCents, 61000);
      expect(report.expenses, hasLength(1));
      expect(await protectedRecords(), originalRecords);
      await expectLater(LocalJobProfitabilityRepository(db).load('shop','job-41',isOwner:false), throwsStateError);
    } finally {
      await db.close();
      await directory.delete(recursive: true);
    }
  });
}
