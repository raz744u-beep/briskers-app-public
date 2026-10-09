import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/diagnostics_service.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_invoice_status_styles_cache.dart';
import 'package:briskers_app/services/local_tax_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('full diagnostics catches closed invoices missing offline detail',
      () async {
    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    await db.customStatement(
      '''
      INSERT INTO local_documents (
        id, business_id, kind, document_number,
        status, closed_at, total, sync_state
      ) VALUES (
        'closed-1', 'shop-1', 'invoice', '5180',
        'issued', 1790000000, 1130.74, 'synced'
      )
      ''',
    );
    final report = await BriskersDiagnosticsService(
      database: db,
    ).run('shop-1', full: true);
    final coverage = report.checks.firstWhere(
      (check) => check.id == 'DOC-004',
    );
    expect(coverage.level, BriskersDiagnosticLevel.fail);
    expect(coverage.details.join(' '), contains('Closed invoices missing detail: 1'));
    expect(coverage.details.join(' '), contains('invoice #5180'));
    await db.close();
  });

  test('full diagnostics accepts closed invoices with cached detail',
      () async {
    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    await db.customStatement(
      '''
      INSERT INTO local_documents (
        id, business_id, kind, document_number,
        status, closed_at, total, sync_state
      ) VALUES (
        'closed-2', 'shop-2', 'invoice', '4199',
        'issued', 1790000000, 5710.27, 'synced'
      )
      ''',
    );
    await const LocalDocumentDetailCache().save('shop-2', 'closed-2', {
      'id': 'closed-2',
      'kind': 'invoice',
      'lines': <Map<String, dynamic>>[],
      'total_amount': 5710.27,
    });
    final report = await BriskersDiagnosticsService(
      database: db,
    ).run('shop-2', full: true);
    final coverage = report.checks.firstWhere(
      (check) => check.id == 'DOC-004',
    );
    expect(coverage.level, BriskersDiagnosticLevel.pass);
    expect(coverage.details.join(' '), contains('Cached and valid: 1 / 1'));
    await db.close();
  });

  test('diagnostics detect v18-style missing ExpenseIQ tables', () async {
    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').getSingle();
    await db.customStatement('DROP TABLE local_expense_iq_photos');
    await db.customStatement('DROP TABLE local_expense_iq_sync_settings');
    final report = await BriskersDiagnosticsService(
      database: db,
    ).run('business-1', full: false);
    final schema = report.checks.firstWhere((x) => x.id == 'DB-003');
    expect(schema.level, BriskersDiagnosticLevel.fail);
    expect(schema.details.join(' '), contains('local_expense_iq_photos'));
    final queue = report.checks.firstWhere((x) => x.id == 'PHOTOIQ-001');
    expect(queue.level, BriskersDiagnosticLevel.fail);
    await db.close();
  });

  test('diagnostics report ExpenseIQ queue counts and missing files', () async {
    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    await db.customStatement('''
      INSERT INTO local_expense_iq_photos
        (business_id,transaction_id,photo_id,filename,source_uri,state,updated_at)
      VALUES
        ('business-1','txn-1','p-1','p-1.jpg','content://expenseiq/p-1.jpg','pending',1),
        ('business-1','txn-2','p-2','p-2.jpg',NULL,'missing',1)
    ''');
    final report = await BriskersDiagnosticsService(
      database: db,
    ).run('business-1', full: true);
    final schema = report.checks.firstWhere((x) => x.id == 'DB-003');
    expect(schema.level, BriskersDiagnosticLevel.pass);
    final queue = report.checks.firstWhere((x) => x.id == 'PHOTOIQ-001');
    expect(queue.level, BriskersDiagnosticLevel.warning);
    expect(queue.details.join(' '), contains('Pending: 1'));
    expect(queue.details.join(' '), contains('unmatched: 1'));
    final integrity = report.checks.firstWhere((x) => x.id == 'PHOTOIQ-002');
    expect(integrity.level, BriskersDiagnosticLevel.pass);
    await db.close();
  });



  test('full diagnostics pass for a healthy local offline snapshot', () async {
    SharedPreferences.setMockInitialValues({});

    final database = BriskersLocalDatabase(NativeDatabase.memory());
    const businessId = 'business-1';
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

    for (final scope in const [
      'customers_vehicles',
      'appointments',
      'jobs',
      'catalog',
      'documents',
    ]) {
      await database.customStatement(
        '''
        INSERT INTO local_sync_states
          (business_id, scope, last_pull_at, bootstrapped)
        VALUES (?, ?, ?, 1)
        ''',
        [businessId, scope, now],
      );
    }

    await database.customStatement(
      '''
      INSERT INTO local_customers
        (id, business_id, display_name, sync_state)
      VALUES ('customer-1', ?, 'Customer One', 'synced')
      ''',
      [businessId],
    );
    await database.customStatement(
      '''
      INSERT INTO local_vehicles
        (id, business_id, year, make, model, sync_state)
      VALUES ('vehicle-1', ?, 2012, 'Hyundai', 'Equus', 'synced')
      ''',
      [businessId],
    );
    await database.customStatement(
      '''
      INSERT INTO local_jobs
        (id, business_id, access_scope, job_number, title, status,
         customer_id, customer_name, vehicle_id, vehicle_label, sync_state)
      VALUES ('job-1', ?, 'all', 'J-1', 'Oil leak', 'in_progress',
              'customer-1', 'Customer One', 'vehicle-1',
              '2012 Hyundai Equus', 'synced')
      ''',
      [businessId],
    );
    await database.customStatement(
      '''
      INSERT INTO local_documents
        (id, business_id, job_id, customer_id, kind, status,
         display_status_code, converted, total, sync_state)
      VALUES ('estimate-1', ?, 'job-1', 'customer-1', 'estimate',
              'draft', 'draft', 0, 10.98, 'synced')
      ''',
      [businessId],
    );

    const detailCache = LocalDocumentDetailCache();
    await detailCache.save(businessId, 'estimate-1', {
      'id': 'estimate-1',
      'kind': 'estimate',
      'status': 'draft',
      'job_id': 'job-1',
      'customer_id': 'customer-1',
      'vehicle_id': 'vehicle-1',
      'net_amount': 10,
      'tax_amount': 0.98,
      'total_amount': 10.98,
      'lines': [
        {
          'id': 'line-1',
          'net_amount': 10,
          'tax_amount': 0.98,
        },
      ],
    });

    final taxCache = LocalTaxSettingsCache();
    await taxCache.save(businessId, {'sales_tax_rate': 0.0975});
    final styleCache = LocalInvoiceStatusStylesCache();
    await styleCache.save(businessId, [
      {'code': 'open', 'name': 'Open'},
    ]);

    final report = await BriskersDiagnosticsService(
      database: database,
      detailCache: detailCache,
      taxSettingsCache: taxCache,
      invoiceStatusStylesCache: styleCache,
    ).run(businessId, full: true);

    expect(report.failed, 0);
    expect(
      report.checks.any(
        (check) =>
            check.id == 'DOC-001' &&
            check.level == BriskersDiagnosticLevel.pass,
      ),
      isTrue,
    );
    expect(
      report.checks.any(
        (check) =>
            check.id == 'REL-001' &&
            check.level == BriskersDiagnosticLevel.pass,
      ),
      isTrue,
    );

    await database.close();
  });

  test('diagnostics detect an orphaned local document job link', () async {
    SharedPreferences.setMockInitialValues({});

    final database = BriskersLocalDatabase(NativeDatabase.memory());
    const businessId = 'business-1';
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

    for (final scope in const [
      'customers_vehicles',
      'appointments',
      'jobs',
      'catalog',
      'documents',
    ]) {
      await database.customStatement(
        '''
        INSERT INTO local_sync_states
          (business_id, scope, last_pull_at, bootstrapped)
        VALUES (?, ?, ?, 1)
        ''',
        [businessId, scope, now],
      );
    }

    await database.customStatement(
      '''
      INSERT INTO local_customers
        (id, business_id, display_name, sync_state)
      VALUES ('customer-1', ?, 'Customer One', 'synced')
      ''',
      [businessId],
    );
    await database.customStatement(
      '''
      INSERT INTO local_documents
        (id, business_id, job_id, customer_id, kind, status,
         display_status_code, converted, total, sync_state)
      VALUES ('invoice-1', ?, 'missing-job', 'customer-1', 'invoice',
              'issued', 'open', 0, 100, 'synced')
      ''',
      [businessId],
    );

    final taxCache = LocalTaxSettingsCache();
    await taxCache.save(businessId, {'sales_tax_rate': 0.0975});
    final styleCache = LocalInvoiceStatusStylesCache();
    await styleCache.save(businessId, [
      {'code': 'open', 'name': 'Open'},
    ]);

    final report = await BriskersDiagnosticsService(
      database: database,
      taxSettingsCache: taxCache,
      invoiceStatusStylesCache: styleCache,
    ).run(businessId, full: false);

    final relationshipCheck =
        report.checks.firstWhere((check) => check.id == 'REL-001');
    expect(relationshipCheck.level, BriskersDiagnosticLevel.fail);

    await database.close();
  });
}
