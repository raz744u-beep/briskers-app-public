import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_cleanup_safety.dart';

void main() {
  test('nested document references and uncertain payloads fail closed', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      await db.customStatement("INSERT INTO sync_outbox "
        "(business_id,entity_type,entity_id,operation,payload_json) "
        "VALUES ('shop','payment','operation','create',?)",
        [jsonEncode({'data': [{'invoice_id': 'deleted-doc'}]})]);
      await expectLater(LocalCleanupSafety.requireDocumentsRemovable(
        db, 'shop', {'deleted-doc'}), throwsStateError);
      await db.customStatement("UPDATE sync_outbox SET payload_json='unparseable'");
      await expectLater(LocalCleanupSafety.requireDocumentsRemovable(
        db, 'shop', {'deleted-doc'}), throwsStateError);
      expect((await db.customSelect('SELECT * FROM sync_outbox').get()).length, 1);
    } finally { await db.close(); }
  });

  test('pending deleted documents retained until reconciliation, other businesses unaffected', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      await db.customStatement("INSERT INTO local_documents "
        "(id,business_id,kind,sync_state) VALUES ('d','shop','invoice','pending')");
      await LocalCleanupSafety.requireDocumentsRemovable(db, 'other', {'d'});
      await expectLater(LocalCleanupSafety.requireDocumentsRemovable(db, 'shop', {'d'}),
        throwsStateError);
      await db.customStatement("UPDATE local_documents SET sync_state='synced'");
      await LocalCleanupSafety.requireDocumentsRemovable(db, 'shop', {'d'});
      expect((await db.customSelect('SELECT * FROM local_documents').get()).length, 1);
    } finally { await db.close(); }
  });
}
