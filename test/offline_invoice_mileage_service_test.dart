import 'dart:convert';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/offline_invoice_mileage_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Mileage Out is durable, scoped, and does not touch Mileage In', () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final svc=OfflineInvoiceMileageService(database:db);
      const id='11111111-1111-4111-8111-111111111111';
      await svc.queue('shop-a',id,expectedVersion:4,mileageOut:125025);
      final reopened=OfflineInvoiceMileageService(database:db);
      final actual=await reopened.project('shop-a',id,{
        'id':id,'kind':'invoice','mileage_schema_version':2,
        'mileage_in':125010,'mileage_out':null,
      });
      expect(actual['mileage_in'],125010);
      expect(actual['mileage_out'],125025);
      expect(actual['mileage_out_sync_state'],'pending');
      final other=await reopened.project('shop-b',id,{
        'kind':'invoice','mileage_schema_version':2,'mileage_out':null,
      });
      expect(other['mileage_out'],isNull);
      final legacy=await reopened.project('shop-a',id,{
        'kind':'invoice','odometer_in':125010,
      });
      expect(legacy.containsKey('mileage_out'),false);
      final queue=await db.customSelect(
        "SELECT entity_type,base_row_version,payload_json FROM sync_outbox "
        "WHERE business_id='shop-a'").getSingle();
      expect(queue.read<String>('entity_type'),'invoice_mileage_out');
      expect(queue.read<int>('base_row_version'),4);
      expect((jsonDecode(queue.read<String>('payload_json')) as Map)
          ['mileage_out'],125025);
    } finally { await db.close(); }
  });

  test('unattempted edits coalesce; attempted edit cannot be silently changed', () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final svc=OfflineInvoiceMileageService(database:db);
      const id='22222222-2222-4222-8222-222222222222';
      await svc.queue('shop-a',id,expectedVersion:3,mileageOut:30100);
      await svc.queue('shop-a',id,expectedVersion:3,mileageOut:30115);
      final before=await db.customSelect(
        "SELECT id,payload_json FROM sync_outbox WHERE business_id='shop-a'",
      ).getSingle();
      expect((jsonDecode(before.read<String>('payload_json')) as Map)
          ['mileage_out'],30115);
      await db.customStatement(
        "UPDATE sync_outbox SET attempt_count=1 WHERE id=?",
        [before.read<int>('id')],
      );
      await expectLater(svc.queue('shop-a',id,
          expectedVersion:3,mileageOut:30120),throwsStateError);
      expect((await db.customSelect(
          "SELECT count(*) AS n FROM sync_outbox").getSingle()).read<int>('n'),1);
      await svc.queue('shop-a',id,expectedVersion:3,mileageOut:30115);
    } finally { await db.close(); }
  });

  test('refuses provisional IDs and invalid odometers', () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final svc=OfflineInvoiceMileageService(database:db);
      await expectLater(svc.queue('shop-a','local-invoice-temp',
          expectedVersion:1,mileageOut:100),throwsStateError);
      await expectLater(svc.queue('shop-a','doc-1',
          expectedVersion:0,mileageOut:100),throwsStateError);
      await expectLater(svc.queue('shop-a','doc-1',
          expectedVersion:1,mileageOut:-5),throwsArgumentError);
    } finally { await db.close(); }
  });
}
