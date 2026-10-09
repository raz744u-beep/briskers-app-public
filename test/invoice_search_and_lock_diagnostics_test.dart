import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/diagnostics_service.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('duplicate imported invoice numbers fail diagnostics', () async {
    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    await db.customStatement("""
      INSERT INTO local_documents
        (id, business_id, kind, document_number, status, total, sync_state)
      VALUES
        ('a','shop','invoice','6321','issued',100,'synced'),
        ('b','shop','invoice','I-6321','issued',100,'synced'),
        ('c','shop','invoice','63210','issued',100,'synced')
    """);
    final report = await BriskersDiagnosticsService(database: db).run('shop');
    final check = report.checks.firstWhere((c) => c.id == 'DOC-005');
    expect(check.level, BriskersDiagnosticLevel.fail);
    expect(check.details.join(' '), contains('6321 (2)'));
    await db.close();
  });


  test('distinct closed historical invoices sharing a number produce a warning',
      () async {
    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    await db.customStatement("""
      INSERT INTO local_documents
        (id, business_id, kind, document_number, document_date,
         status, closed_at, total, sync_state)
      VALUES
        ('legacy-one','shop-history','invoice','3203','2021-07-21',
         'issued',1790000000,1006.19,'synced'),
        ('legacy-two','shop-history','invoice','3203','2021-08-19',
         'issued',1790000000,344.14,'synced')
    """);
    final report = await BriskersDiagnosticsService(database: db)
        .run('shop-history');
    final check = report.checks.firstWhere((c) => c.id == 'DOC-005');
    expect(check.level, BriskersDiagnosticLevel.warning);
    expect(check.summary, contains('historical invoice'));
    expect(check.details.join(' '), contains('3203'));
    expect(check.details.join(' '), contains('2021-07-21'));
    await db.close();
  });

  test('open and closed invoices sharing a number remain a failure', () async {
    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    await db.customStatement("""
      INSERT INTO local_documents
        (id, business_id, kind, document_number, status, closed_at,
         total, sync_state)
      VALUES
        ('old','shop-open','invoice','3203','issued',
         1790000000,1006.19,'synced'),
        ('new','shop-open','invoice','3203','issued',
         NULL,344.14,'synced')
    """);
    final report = await BriskersDiagnosticsService(database: db)
        .run('shop-open');
    final check = report.checks.firstWhere((c) => c.id == 'DOC-005');
    expect(check.level, BriskersDiagnosticLevel.fail);
    expect(check.details.join(' '), contains('Active/unsynced collisions'));
    await db.close();
  });


  test('older cached invoices missing lock metadata warn instead of passing',
      () async {
    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    await db.customStatement("""
      INSERT INTO local_documents
        (id, business_id, kind, document_number, status, closed_at, total, sync_state)
      VALUES ('old-cache','shop-stale','invoice','3203','issued',
              1790000000,1006.19,'synced')
    """);
    await const LocalDocumentDetailCache().save('shop-stale','old-cache',{
      'id':'old-cache','kind':'invoice','total_amount':1006.19,
      'lines':<Map<String,dynamic>>[]
    });
    final report = await BriskersDiagnosticsService(database: db)
        .run('shop-stale',full:true);
    final check = report.checks.firstWhere((c) => c.id == 'DOC-006');
    expect(check.level, BriskersDiagnosticLevel.warning);
    expect(check.details.join(' '), contains('lack legacy edit-lock metadata'));
    await db.close();
  });

  test('closed imported invoice flagged as editable fails diagnostics', () async {
    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    await db.customStatement("""
      INSERT INTO local_documents
        (id, business_id, kind, document_number, status, closed_at, total, sync_state)
      VALUES ('d','shop-locked','invoice','6321','issued',1790000000,100,'synced')
    """);
    await const LocalDocumentDetailCache().save('shop-locked','d',{
      'id':'d','kind':'invoice','legacy_read_only':true,
      'legacy_editable':true,'closed_at':'2026-09-01','paid_amount':100
    });
    final report = await BriskersDiagnosticsService(database:db)
        .run('shop-locked',full:true);
    final check = report.checks.firstWhere((c) => c.id == 'DOC-006');
    expect(check.level, BriskersDiagnosticLevel.fail);
    await db.close();
  });
}
