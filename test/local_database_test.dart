import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';

void main() {
  test('upgrading old v18 install creates missing photo queue without wiping records',
      () async {
    final folder = await Directory.systemTemp.createTemp('briskers-schema-v18-');
    final file = File('${folder.path}/briskers.db');
    try {
      var db = BriskersLocalDatabase(NativeDatabase(file));
      await db.customStatement('''
        INSERT INTO local_customers
          (id, business_id, display_name)
        VALUES ('keep-customer', 'business-1', 'Preserved customer')
      ''');
      await db.customStatement('PRAGMA user_version = 18');
      await db.customStatement('DROP TABLE local_expense_iq_photos');
      await db.customStatement('DROP TABLE local_expense_iq_sync_settings');
      await db.close();

      db = BriskersLocalDatabase(NativeDatabase(file));
      final tables = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name LIKE 'local_expense_iq_%'",
      ).get();
      final names = tables.map((row)=>row.read<String>('name')).toSet();
      expect(names, containsAll([
        'local_expense_iq_photos',
        'local_expense_iq_sync_settings',
      ]));
      final customers = await db.customSelect(
        "SELECT COUNT(*) AS n FROM local_customers "
        "WHERE id='keep-customer'",
      ).getSingle();
      expect(customers.read<int>('n'), 1);
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), 19);
      await db.close();
    } finally {
      await folder.delete(recursive: true);
    }
  });

  test('opening v19 with missing queue tables repairs safely', () async {
    final folder = await Directory.systemTemp.createTemp('briskers-schema-v19-');
    final file = File('${folder.path}/briskers.db');
    try {
      var db = BriskersLocalDatabase(NativeDatabase(file));
      await db.customStatement('DROP TABLE local_expense_iq_photos');
      await db.customStatement('DROP TABLE local_expense_iq_sync_settings');
      await db.close();
      db = BriskersLocalDatabase(NativeDatabase(file));
      await db.customStatement('''
        INSERT INTO local_expense_iq_photos
          (business_id,transaction_id,photo_id,filename,updated_at)
        VALUES ('business-1','txn-1','p-1','p-1.jpg',1)
      ''');
      final count = await db.customSelect(
        'SELECT COUNT(*) AS n FROM local_expense_iq_photos',
      ).getSingle();
      expect(count.read<int>('n'), 1);
      await db.close();
    } finally {
      await folder.delete(recursive: true);
    }
  });

  test('local Briskers database opens and creates schema', () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());

    final row =
        await database.customSelect('SELECT 1 AS ready').getSingle();

    expect(row.read<int>('ready'), 1);

    final tables = await database.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table'",
    ).get();
    final names = tables.map((row) => row.read<String>('name')).toSet();
    expect(names, contains('local_finding_photos'));
    expect(names, contains('local_job_statuses'));
    expect(names, contains('local_customers'));
    expect(names, contains('local_vehicles'));
    expect(names, contains('local_customer_vehicles'));
    expect(names, contains('local_appointments'));
    expect(names, contains('local_kiosk_settings'));

    final appointmentColumns = await database.customSelect(
      'PRAGMA table_info(local_appointments)',
    ).get();
    final appointmentColumnNames = appointmentColumns
        .map((row) => row.read<String>('name'))
        .toSet();
    expect(
      appointmentColumnNames,
      contains('customer_phone_norm'),
    );

    await database.close();
  });
}
