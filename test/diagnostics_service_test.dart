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
