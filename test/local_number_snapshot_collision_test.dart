import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/diagnostics_service.dart';
import 'package:briskers_app/services/local_document_sql_store.dart';
import 'package:briskers_app/services/local_document_repository.dart';
import 'package:briskers_app/services/local_number_allocator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const snapshot = {
    'id': 'dakota-invoice', 'kind': 'invoice', 'document_number': '6360',
    'customer_id': 'dakota', 'job_id': 'dakota-job', 'job_number': 'J-41',
    'document_date': '2026-11-02', 'closed_at': '2026-11-02T20:00:00Z',
    'total_amount': 554.24, 'paid_amount': 554.24,
    'payments': [{'id': 'dakota-payment', 'amount': 554.24}],
  };
  const key = 'briskers_document_detail_shop_dakota-invoice';
  late BriskersLocalDatabase db;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = BriskersLocalDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  Future<void> staleCounters() async {
    final allocator = LocalNumberAllocator(db);
    await allocator.setNextNumber('shop', 'invoice', 6360);
    await allocator.setNextNumber('shop', 'job', 41);
  }

  test('saved paid invoice outside list blocks invoice and job reuse after restart', () async {
    final dir = await Directory.systemTemp.createTemp('number-collision-');
    addTearDown(() => dir.delete(recursive: true));
    await db.close();
    db = BriskersLocalDatabase(NativeDatabase(File('${dir.path}/test.sqlite')));
    await staleCounters();
    final original = jsonEncode(snapshot);
    await LocalDocumentSqlStore.write(db, key, original);
    await db.customStatement("INSERT INTO local_documents(id,business_id,kind,document_number,status,total,sync_state) "
      "VALUES('dakota-invoice','shop','invoice','6360','closed',554.24,'synced')");
    await LocalDocumentRepository(database: db).replaceFromServer('shop', [], kind: 'invoice');
    await db.close();
    db = BriskersLocalDatabase(NativeDatabase(File('${dir.path}/test.sqlite')));
    final numbers = LocalNumberAllocator(db);
    expect(await numbers.allocate('shop', 'invoice', 'tyra-invoice'), 6361);
    expect(await numbers.allocate('shop', 'job', 'tyra-job'), 42);
    expect(await LocalDocumentSqlStore.read(db, key), original);
    expect(await db.customSelect('SELECT id FROM local_documents').get(), isEmpty);
  });

  test('legacy preference snapshot blocks explicit reuse, scoped to business', () async {
    SharedPreferences.setMockInitialValues({key: jsonEncode(snapshot)});
    await staleCounters();
    final numbers = LocalNumberAllocator(db);
    await expectLater(numbers.allocate('shop', 'invoice', 'tyra', requested: 6360), throwsStateError);
    await expectLater(numbers.allocate('shop', 'job', 'tyra-job', requested: 41), throwsStateError);
    expect(await numbers.allocate('other-shop', 'invoice', 'other', requested: 6360), 6360);
  });

  test('explicitly deleted snapshot permits approved number reuse', () async {
    SharedPreferences.setMockInitialValues({key: jsonEncode(snapshot)});
    await staleCounters();
    await LocalDocumentSqlStore.ensure(db);
    await db.customStatement('INSERT INTO local_document_detail_deleted VALUES (?)', [key]);
    final numbers = LocalNumberAllocator(db);
    expect(await numbers.allocate('shop', 'invoice', 'replacement', requested: 6360), 6360);
    expect(await numbers.allocate('shop', 'job', 'replacement-job', requested: 41), 41);
  });

  test('diagnostics detect current invoice colliding with a cache-only paid invoice', () async {
    await LocalDocumentSqlStore.write(db, key, jsonEncode(snapshot));
    await db.customStatement("INSERT INTO local_documents(id,business_id,kind,document_number,status,total,sync_state) "
      "VALUES('tyra','shop','invoice','6360','issued',4894.21,'pending')");
    final report = await BriskersDiagnosticsService(database: db).run('shop');
    final check = report.checks.firstWhere((c) => c.id == 'DOC-005');
    expect(check.level, BriskersDiagnosticLevel.fail);
    expect(check.details.join(' '), contains('6360 (2; dates:'));
    expect(check.details.join(' '), contains('customer dakota; job dakota-job'));
  });

  test('indexed and cached copies of the same invoice are counted once', () async {
    await LocalDocumentSqlStore.write(db, key, jsonEncode(snapshot));
    await db.customStatement("INSERT INTO local_documents(id,business_id,kind,document_number,status,total,sync_state) "
      "VALUES('dakota-invoice','shop','invoice','6360','closed',554.24,'synced')");
    final report = await BriskersDiagnosticsService(database: db).run('shop');
    expect(report.checks.firstWhere((c) => c.id == 'DOC-005').level, BriskersDiagnosticLevel.pass);
  });
}
