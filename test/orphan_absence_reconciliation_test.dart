import 'dart:convert';
import 'dart:io';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/appointment_sync_service.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _AbsenceApi extends BriskersApi {
  _AbsenceApi({this.absent = true,this.fail = false});
  final bool absent;
  final bool fail;
  int queries=0;
  @override
  Future<bool> confirmOrphanMockAppointmentAbsent(
    String businessId,String appointmentId,
  ) async {
    queries++;
    if (fail) {
      throw StateError('Server offline / no receipt');
    }
    expect(businessId,'shop-a');
    expect(appointmentId,AppointmentSyncService.orphanMockAppointmentId);
    return absent;
  }
}

Future<void> seed(BriskersLocalDatabase db,{bool extra=false}) async {
  const id=AppointmentSyncService.orphanMockAppointmentId;
  await db.customStatement(
    """INSERT INTO local_appointments(
       id,business_id,customer_id,starts_at,ends_at,status,title,
       can_check_in,row_version,sync_state
       ) VALUES (?,'shop-a','missing-customer',100,200,
       'arrived','Orphan mock',0,7,'pending_delete')""",
    [id],
  );
  await db.customStatement(
    """INSERT INTO sync_outbox(
       business_id,entity_type,entity_id,operation,payload_json,
       base_row_version,state,attempt_count,created_at
       ) VALUES('shop-a','appointment_delete',?,'delete',?,
        7,'pending',0,100)""",
    [id,jsonEncode({'operation_id':'11111111-1111-4111-8111-111111111111',
                    'appointment_id':id})],
  );
  if(extra) {
    await db.customStatement(
      """INSERT INTO sync_outbox(business_id,entity_type,entity_id,operation,
         payload_json,state,attempt_count,created_at)
         VALUES('shop-a','appointment_edit',?,'update','{}','pending',1,100)""",
      [id],
    );
  }
  await db.customStatement(
    """INSERT INTO local_appointments(
      id,business_id,customer_id,starts_at,ends_at,status,title,row_version,
      sync_state) VALUES('real-appt','shop-a','real-customer',100,200,
      'confirmed','Keep intact',2,'synced')""",
  );
  await db.customStatement(
    """INSERT INTO sync_outbox(business_id,entity_type,entity_id,operation,
       payload_json,state,attempt_count,created_at)
       VALUES('shop-a','appointment_cancel','real-appt','cancel','{}',
       'pending',0,100)""",
  );
}

Future<int> count(BriskersLocalDatabase db,String sql) async =>
    (await db.customSelect(sql).getSingle()).read<int>('n');

void main() {
  test('owner receipt retires exactly tombstoned mock and no other record',() async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final api=_AbsenceApi();
    try {
      await seed(db);
      final sync=AppointmentSyncService(database:db,api:api);
      expect(await sync.reconcileAbsentOrphanMock('shop-a',isOwner:false),false);
      expect(api.queries,0);
      expect(await sync.reconcileAbsentOrphanMock('shop-a',isOwner:true),true);
      expect(api.queries,1);
      expect(await count(db,"SELECT count(*) n FROM local_appointments WHERE id='real-appt'"),1);
      expect(await count(db,"SELECT count(*) n FROM local_appointments WHERE id='93356a11-f16a-4939-aaec-db5593273de3'"),0);
      expect(await count(db,"SELECT count(*) n FROM sync_outbox WHERE entity_id='real-appt'"),1);
      expect(await count(db,"SELECT count(*) n FROM sync_outbox WHERE entity_type='appointment_delete'"),0);
      expect(await sync.reconcileAbsentOrphanMock('shop-a',isOwner:true),false);
    } finally {await db.close();}
  });

  test('server still has appointment: no data changed',() async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    try {
      await seed(db);
      final api=_AbsenceApi(absent:false);
      final sync=AppointmentSyncService(database:db,api:api);
      expect(await sync.reconcileAbsentOrphanMock('shop-a',isOwner:true),false);
      expect(await count(db,"SELECT count(*) n FROM sync_outbox WHERE entity_type='appointment_delete'"),1);
    } finally {await db.close();}
  });

  test('missing server receipt fails closed and keeps queue',() async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    try {
      await seed(db);
      final sync=AppointmentSyncService(database:db,api:_AbsenceApi(fail:true));
      await expectLater(
        sync.reconcileAbsentOrphanMock('shop-a',isOwner:true),
        throwsStateError,
      );
      expect(await count(db,"SELECT count(*) n FROM sync_outbox WHERE entity_type='appointment_delete'"),1);
    } finally {await db.close();}
  });

  test('unexpected extra queue prevents cleanup without querying server',() async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final api=_AbsenceApi();
    try {
      await seed(db,extra:true);
      final sync=AppointmentSyncService(database:db,api:api);
      expect(await sync.reconcileAbsentOrphanMock('shop-a',isOwner:true),false);
      expect(api.queries,0);
      expect(await count(db,"SELECT count(*) n FROM sync_outbox WHERE entity_id='93356a11-f16a-4939-aaec-db5593273de3'"),2);
    } finally {await db.close();}
  });

  test('source contract only permits this exact mock with an Owner receipt',() async {
    // CI test shell does not copy review-only migrations.
    final source = await File('lib/services/appointment_sync_service.dart')
        .readAsString();
    expect(source,contains('confirmOrphanMockAppointmentAbsent('));
    expect(source,contains("sync_state='pending_delete'"));
    final screen = await File('lib/screens/appointments_screen.dart')
        .readAsString();
    expect(screen,contains('reconcileAbsentOrphanMock('));
  });
}
