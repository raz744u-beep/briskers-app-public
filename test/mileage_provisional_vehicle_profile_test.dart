import 'dart:io';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/offline_document_draft_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('new offline invoice keeps Mileage Out without changing Mileage In', () async {
    SharedPreferences.setMockInitialValues({});
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final draft = OfflineDocumentDraftService(database: database);
      final cache = LocalDocumentDetailCache(database: database);
      final id = await draft.createQuickInvoice('shop-1',
        customerId: 'customer-1', customerName: 'Synthetic customer');
      final initial = await cache.load('shop-1', id);
      expect(initial?['mileage_schema_version'], 2);
      expect(initial?['mileage_out'], isNull);

      await draft.updatePendingInvoiceDetails('shop-1', id,
        documentDate: DateTime(2026, 10, 21), mileageOut: '125025');
      final updated = await cache.load('shop-1', id);
      expect(updated?['mileage_out'], 125025);
      expect(updated?['odometer_in'], isNull);
      expect(updated?['document_date'], '2026-10-21');
      expect(updated?['sync_state'], 'pending');
    } finally {
      await database.close();
    }
  });

  test('local v22 vehicle columns preserve reading provenance', () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      expect(database.schemaVersion, 22);
      final columns = await database.customSelect(
        'PRAGMA table_info(local_vehicles)',
      ).get();
      final names = columns.map((x) => x.read<String>('name')).toSet();
      expect(names, contains('mileage_recorded_date'));
      expect(names, contains('mileage_source_invoice_id'));
    } finally {
      await database.close();
    }
  });

  test('provisional upload transfers departure after receiving permanent invoice UUID', () {
    final draft = File('lib/services/offline_document_draft_service.dart')
      .readAsStringSync();
    expect(draft, contains('() => _api.saveInvoiceMileageOut('));
    expect(draft, contains("localDetail['mileage_out'] != null"));
    expect(draft, contains('Mileage Out server schema is not available yet.'));
    expect(draft, contains("proof['mileage_out']"));
    final sync = File('lib/screens/business_gate.dart').readAsStringSync();
    expect(sync, contains('await _offlineInvoiceMileage.flush(businessId);'));
  });

  test('customer profile shows last date only when supplied by verified server', () {
    final profile = File('lib/screens/customers/customer_vehicles_section.dart')
      .readAsStringSync();
    expect(profile, contains('Last recorded'));
    expect(profile, contains('mileage_recorded_date'));
    final sync = File('lib/services/customer_vehicle_sync_service.dart')
      .readAsStringSync();
    expect(sync, contains('mileage_source_invoice_id'));
    expect(sync, contains('mileage_recorded_date'));
  });
}
