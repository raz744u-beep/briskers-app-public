import 'dart:convert';
import 'package:drift/native.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/offline_job_admin_service.dart';
import 'package:briskers_app/services/briskers_api.dart';

void main() {
  test('offline new Job persists with one queued stable-ID creation', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final service = OfflineJobAdminService(database: db);
      final jobId = await service.queueJobCreate('shop-1',
        customerId: 'customer-1',
        customerName: 'Test Customer',
        vehicleId: 'vehicle-1',
        vehicleLabel: '2011 Infiniti M37',
        title: 'Test repair',
        requestedWork: 'Diagnostics',
        plannedHours: 2);
      expect(jobId, matches(RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      final job = await db.customSelect(
        'SELECT sync_state,title,job_number,planned_hours FROM local_jobs '
        'WHERE business_id=? AND id=?',
        variables:[const Variable<String>('shop-1'),Variable<String>(jobId)],
      ).getSingle();
      expect(job.read<String>('sync_state'),'pending');
      expect(job.read<String>('title'),'Test repair');
      expect(job.read<String>('job_number'),'Pending sync');
      expect(job.read<double>('planned_hours'),2.0);
      final queue = await db.customSelect(
        "SELECT payload_json FROM sync_outbox "
        "WHERE entity_type='job_create' AND entity_id=?",
        variables:[Variable<String>(jobId)],
      ).get();
      expect(queue.length,1);
      final payload = Map<String,dynamic>.from(
        jsonDecode(queue.single.read<String>('payload_json')) as Map);
      expect(payload['operation_id'],'job-create-$jobId');
      expect(payload['job_id'],jobId);
      expect(payload['customer_id'],'customer-1');
    } finally {
      await db.close();
    }
  });

  test('uncertain server replay uses the same ID and one Job', () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final api=FakeJobApi()..failUpdateOnce=true;
    final service=OfflineJobAdminService(database:db,api:api);
    try {
      final jobId=await service.queueJobCreate('shop-1',
        customerId:'customer-1',customerName:'Test',
        title:'Offline created job');
      await service.flushCreates('shop-1');
      expect(api.createdIds,[jobId]);
      final retained=await db.customSelect(
        "SELECT id FROM sync_outbox WHERE entity_type='job_create'").get();
      expect(retained.length,1);
      await service.flushCreates('shop-1');
      expect(api.createdIds,[jobId]);
      final pending=await db.customSelect(
        "SELECT id FROM sync_outbox WHERE entity_type='job_create'").get();
      expect(pending,isEmpty);
    } finally { await db.close(); }
  });

  test('pending local-only customer cannot produce unresolvable Job', () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    try {
      await expectLater(
        OfflineJobAdminService(database:db).queueJobCreate('shop-1',
          customerId:'local-customer-123',
          customerName:'New Customer',title:'Repair'),
        throwsStateError,
      );
    } finally { await db.close(); }
  });
}

class FakeJobApi extends BriskersApi {
  final List<String> createdIds=[];
  bool failUpdateOnce=false;
  @override
  Future<String> createJob(String businessId, {
    required String customerId, String? vehicleId,
    required String title, String? description, String? id,
  }) async {
    if(id==null) throw StateError('Missing stable ID');
    if(!createdIds.contains(id)) createdIds.add(id);
    return id;
  }
  @override
  Future<void> updateJob(String businessId,String jobId,{
    required String customerId,String? vehicleId,required String title,
    String? requestedWork,required num plannedHours,
  }) async {
    if(failUpdateOnce) {
      failUpdateOnce=false;
      throw StateError('simulated transient network loss');
    }
  }
  @override
  Future<Map<String,dynamic>> jobDetail(String businessId,String jobId) async =>
      {'id':jobId,'customer_id':'customer-1'};
}
