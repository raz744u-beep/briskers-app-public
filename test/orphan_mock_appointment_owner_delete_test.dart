import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Variable;

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/appointment_sync_service.dart';
import 'package:briskers_app/services/local_appointment_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const mockId = AppointmentSyncService.orphanMockAppointmentId;

Future<void> seed(BriskersLocalDatabase db, {int? version = 7}) async {
  await db.customStatement(
    """INSERT INTO local_appointments(
       id,business_id,customer_id,vehicle_id,job_id,starts_at,ends_at,
       status,title,can_check_in,row_version,sync_state
     ) VALUES (?,?,?,?,?,100,200,'arrived','Old test',0,?,'pending')""",
    [mockId, 'shop-a', 'missing-customer', 'missing-vehicle',
     'missing-job', version],
  );
  await db.customStatement(
    """INSERT INTO sync_outbox(
       business_id,entity_type,entity_id,operation,payload_json,
       base_row_version,state,attempt_count,created_at
     ) VALUES (?,?,?,'update',?,?,'pending',24,100)""",
    ['shop-a','appointment_edit',mockId,
     jsonEncode({'appointment_id':mockId,'operation_id':'bad-old-key'}),
     version],
  );
}

Future<int> count(BriskersLocalDatabase db, String sql) async {
  final rows=await db.customSelect(sql).getSingle();
  return rows.read<int>('n');
}

void main() {
  test('owner cleanup atomically replaces ONLY orphan edit with UUID deletion',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final service = AppointmentSyncService(database: db);
    final repository = LocalAppointmentRepository(database: db);
    try {
      await seed(db);
      await db.customStatement(
        """INSERT INTO local_appointments(
          id,business_id,customer_id,starts_at,ends_at,status,title,
          row_version,sync_state
        ) VALUES('other','shop-a','real-customer',100,200,'confirmed',
          'Protect me',2,'synced')""",
      );
      await db.customStatement(
        """INSERT INTO sync_outbox(
          business_id,entity_type,entity_id,operation,payload_json,state,
          attempt_count,created_at
        ) VALUES('shop-a','appointment_cancel','other','cancel','{}',
          'pending',0,100)""",
      );
      await expectLater(
        service.queueDeleteVerifiedOrphanMock('shop-a', mockId,isOwner:false),
        throwsStateError,
      );
      expect(await count(db, "SELECT COUNT(*) n FROM sync_outbox"),2);
      await service.queueDeleteVerifiedOrphanMock('shop-a',mockId,isOwner:true);
      final q = await db.customSelect(
        "SELECT * FROM sync_outbox WHERE business_id='shop-a' AND entity_id=?",
        variables: [const Variable<String>(mockId)],
      ).getSingle();
      expect(q.read<String>('entity_type'),'appointment_delete');
      expect(q.read<String>('operation'),'delete');
      expect(q.read<int>('base_row_version'),7);
      final payload = jsonDecode(q.read<String>('payload_json'))
          as Map<String,dynamic>;
      expect(payload['appointment_id'], mockId);
      expect(payload['operation_id'],matches(RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      )));
      expect((await repository.appointments('shop-a'))
          .any((row)=>row['id']==mockId),false);
      expect(await count(db,
        "SELECT COUNT(*) n FROM sync_outbox WHERE entity_id='other'"),1);
      expect(await count(db,
        "SELECT COUNT(*) n FROM local_appointments WHERE id='other'"),1);
      expect(await count(db,
        "SELECT COUNT(*) n FROM sync_outbox WHERE entity_type='appointment_edit'"),0);
      await expectLater(
        service.queueDeleteVerifiedOrphanMock('shop-a',mockId,isOwner:true),
        throwsStateError,
      );
    } finally {
      await db.close();
    }
  });

  test('blocks linked real records and keeps edit untouched', () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final service=AppointmentSyncService(database:db);
    try {
      await seed(db);
      await db.customStatement(
        """INSERT INTO local_customers(
          id,business_id,display_name,sync_state
        ) VALUES('missing-customer','shop-a','Protected customer','synced')""",
      );
      await expectLater(
        service.queueDeleteVerifiedOrphanMock('shop-a',mockId,isOwner:true),
        throwsStateError,
      );
      expect(await count(db,
          "SELECT COUNT(*) n FROM sync_outbox WHERE entity_type='appointment_edit'"),1);
      expect(await count(db,
          "SELECT COUNT(*) n FROM sync_outbox WHERE entity_type='appointment_delete'"),0);
    } finally {
      await db.close();
    }
  });

  test('blocks missing row revision, extra queue and wrong record', () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final service=AppointmentSyncService(database:db);
    try {
      await seed(db,version:null);
      await expectLater(
        service.queueDeleteVerifiedOrphanMock('shop-a',mockId,isOwner:true),
        throwsStateError,
      );
      await db.customStatement(
        "UPDATE local_appointments SET row_version=4 WHERE id=?",[mockId],
      );
      await db.customStatement(
        """INSERT INTO sync_outbox(
        business_id,entity_type,entity_id,operation,payload_json,state,
        attempt_count,created_at) VALUES
        ('shop-a','appointment_checkin',?,'checkin','{}','pending',0,100)""",
        [mockId],
      );
      await expectLater(
        service.queueDeleteVerifiedOrphanMock('shop-a',mockId,isOwner:true),
        throwsStateError,
      );
      await expectLater(
        service.queueDeleteVerifiedOrphanMock('shop-a','other',isOwner:true),
        throwsStateError,
      );
      expect(await count(db,
        "SELECT COUNT(*) n FROM sync_outbox WHERE entity_id=?".replaceAll('?',"'$mockId'")),2);
    } finally {
      await db.close();
    }
  });

  test('UI exposes only the verified mock cleanup with owner confirmation', () async {
    // Kept in same test suite so UI guardrails cannot be dropped casually.
    final src = await File('lib/screens/appointments_screen.dart').readAsString();
    expect(src,contains("title: 'Delete orphan test appointment?'"));
    expect(src,contains('AppointmentSyncService.orphanMockAppointmentId'));
    expect(src,contains("case 'delete_orphan_mock':"));
    expect(src,contains("ValueKey('owner-orphan-appointment-cleanup')"));
    expect(src,contains("if (widget.roleCode == 'owner' && _hasOrphanMock)"));
    expect(src,contains('isOwner: true'));
  });
}
