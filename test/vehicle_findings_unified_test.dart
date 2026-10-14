import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/customer_detail_cache.dart';
import 'package:briskers_app/services/offline_customer_detail_write_service.dart';
import 'package:briskers_app/services/offline_work_findings_service.dart';
import 'package:briskers_app/services/vehicle_finding_actions_service.dart';
import 'package:briskers_app/services/work_finding_merge.dart';
import 'package:briskers_app/widgets/vehicle_findings.dart';

// Synthetic fixture only: no credentials, Supabase, or live customer writes.
const business = 'fixture-shop';
const customer = 'fixture-customer-6334';
const vehicle = 'fixture-vehicle-6334';
const job = 'fixture-job-J12';

Map<String, dynamic> finding(String id, {String? foundJob = job}) => {
  'id': id,
  'vehicle_id': vehicle,
  'found_job_id': foundJob,
  'repair_job_id': null,
  'body': 'Synthetic finding $id',
  'status': 'open',
  'include_on_invoice': false,
  'resolved_at': null,
  'row_version': 1,
  'created_at': '2026-10-14T12:00:00Z',
  'can_edit': true,
  'can_delete': true,
  'attachments': <Map<String, dynamic>>[],
};
Map<String, dynamic> invoice({
  String jobId = job,
  String id = 'fixture-invoice-J12',
}) => {
  'id': id,
  'kind': 'invoice',
  'job_id': jobId,
  'vehicle_id': vehicle,
  'created_at': '2026-10-14T13:00:00Z',
  'memo': 'Keep this manual note.',
  'finding_notes': <Map<String, dynamic>>[],
  'total_amount': 450,
};

class _Api extends BriskersApi {
  _Api(List<Map<String, dynamic>> input)
    : rows = {
        for (final row in input)
          row['id'].toString(): Map<String, dynamic>.from(row),
      };
  final Map<String, Map<String, dynamic>> rows;
  int addCalls = 0;
  int createCalls = 0;
  bool loseCreateReply = false;
  final registrations = <String>[];
  int uploads = 0;
  bool loseUploadReply = false;
  bool loseAddReply = false;
  bool staleAcknowledgement = false;
  @override
  Future<String> createVehicleFindingForVehicle(
    String businessId,
    String customerId,
    String vehicleId, {
    required String body,
    bool includeOnInvoice = false,
  }) async {
    createCalls++;
    rows['fixture-customer-server'] = {
      ...finding('fixture-customer-server', foundJob: null),
      'body': body,
      'include_on_invoice': includeOnInvoice,
    };
    if (loseCreateReply) {
      loseCreateReply = false;
      throw StateError('Synthetic lost create reply');
    }
    return 'fixture-customer-server';
  }

  @override
  Future<Map<String, dynamic>> syncRegisterFindingPhoto(
    String businessId,
    String findingId, {
    required String operationId,
    required String filename,
    required String mimeType,
  }) async {
    registrations.add(operationId);
    return {
      'attachment_id': 'fixture-server-photo',
      'bucket': 'synthetic',
      'key': 'fixture-photo',
    };
  }

  @override
  Future<void> uploadRegisteredAttachment(
    String businessId, {
    required String bucket,
    required String key,
    required String attachmentId,
    required String mimeType,
    required Uint8List bytes,
    AttachmentReplayGuard? replayGuard,
  }) async {
    uploads++;
    if (loseUploadReply) {
      loseUploadReply = false;
      throw StateError('Synthetic lost upload reply');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> vehicleFindings(
    String businessId,
    String vehicleId, {
    bool includeResolved = true,
  }) async => rows.values.map(Map<String, dynamic>.from).toList();
  void patch(String id, Map<String, dynamic> value) {
    if (staleAcknowledgement) return;
    rows[id] = {
      ...rows[id]!,
      ...value,
      'row_version': (rows[id]!['row_version'] as int) + 1,
    };
  }

  @override
  Future<void> addVehicleFindingToJob(
    String businessId,
    String id,
    String jobId,
  ) async {
    addCalls++;
    patch(id, {
      'status': 'in_job',
      'repair_job_id': jobId,
      'resolved_at': null,
    });
    if (loseAddReply) {
      loseAddReply = false;
      throw StateError('Synthetic lost response');
    }
  }

  @override
  Future<void> removeVehicleFindingFromJob(
    String businessId,
    String id,
    String jobId,
  ) async =>
      patch(id, {'status': 'open', 'repair_job_id': null, 'resolved_at': null});
  @override
  Future<void> setVehicleFindingInvoiceFlag(
    String businessId,
    String id,
    bool include,
  ) async => patch(id, {'include_on_invoice': include});
  @override
  Future<void> resolveVehicleFinding(
    String businessId,
    String id,
    String jobId,
  ) async => patch(id, {
    'status': 'resolved',
    'repair_job_id': jobId,
    'resolved_at': '2026-10-14T14:00:00Z',
  });
  @override
  Future<void> reopenVehicleFinding(String businessId, String id) async =>
      patch(id, {'status': 'open', 'repair_job_id': null, 'resolved_at': null});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BriskersLocalDatabase db;
  late _Api api;
  late OfflineWorkFindingsService work;
  late VehicleFindingActionsService actions;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = BriskersLocalDatabase(NativeDatabase.memory());
    api = _Api([finding('fixture-f1'), finding('fixture-f2')]);
    work = OfflineWorkFindingsService(database: db, api: api);
    actions = VehicleFindingActionsService(database: db, api: api);
    await work.seedServerFindingsIfClean(
      business,
      vehicle,
      api.rows.values.toList(),
    );
  });
  tearDown(() async => db.close());

  test(
    'pending customer-created finding can be edited from Job before sync',
    () async {
      final customerWrites = OfflineCustomerDetailWriteService(
        database: db,
        api: api,
      );
      final created = await customerWrites.createFinding(
        business,
        customer,
        vehicle,
        body: 'Original customer finding',
        includeOnInvoice: false,
        photos: [],
      );
      await work.updateLocalFinding(
        business,
        job,
        created['id'].toString(),
        body: 'Edited from Job',
      );
      await customerWrites.flush(business);
      expect(api.createCalls, 1);
      expect(api.rows['fixture-customer-server']!['body'], 'Edited from Job');
      final rows = await work.loadLocalFindings(business, vehicle);
      expect(rows.where((row) => row['id'] == created['id']), isEmpty);
      expect(
        rows.where((row) => row['id'] == 'fixture-customer-server'),
        hasLength(1),
      );
    },
  );

  test(
    'ambiguous legacy customer create preserves finding and photos across restart without repeat',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'synthetic-customer-uncertain-',
      );
      final file = File('${directory.path}/fixture.sqlite');
      final photo = File('${directory.path}/photo.jpg');
      await photo.writeAsBytes([1, 2, 3]);
      var persisted = BriskersLocalDatabase(NativeDatabase(file));
      try {
        var customerWrites = OfflineCustomerDetailWriteService(
          database: persisted,
          api: api,
        );
        final created = await customerWrites.createFinding(
          business,
          customer,
          vehicle,
          body: 'Preserve uncertain local finding',
          includeOnInvoice: true,
          photos: [],
        );
        final id = created['id'].toString();
        await persisted.customStatement(
          "INSERT INTO local_finding_photos(id,business_id,finding_id,attachment_id,local_file_path,upload_state) VALUES('fixture-retained-photo',?,?,'fixture-retained-photo',?,'pending')",
          [business, id, photo.path],
        );
        await persisted.customStatement(
          "INSERT INTO sync_outbox(business_id,entity_type,entity_id,operation,payload_json,state,attempt_count,created_at) VALUES(?,'customer_finding_photo','fixture-retained-photo','upload',?,'pending',0,1)",
          [
            business,
            jsonEncode({
              'customer_id': customer,
              'finding_id': id,
              'local_file_path': photo.path,
              'filename': 'photo.jpg',
              'mime_type': 'image/jpeg',
            }),
          ],
        );
        api.loseCreateReply = true;
        await customerWrites.flush(business);
        await persisted.close();
        persisted = BriskersLocalDatabase(NativeDatabase(file));
        customerWrites = OfflineCustomerDetailWriteService(
          database: persisted,
          api: api,
        );
        await customerWrites.flush(business);
        expect(api.createCalls, 1);
        final local = (await OfflineWorkFindingsService(
          database: persisted,
          api: api,
        ).loadLocalFindings(business, vehicle)).single;
        expect(local['body'], 'Preserve uncertain local finding');
        expect(local['sync_state'], 'pending');
        expect(local['_finding_action_error'], isNotEmpty);
        expect(local['attachments'], hasLength(1));
        expect(await photo.readAsBytes(), [1, 2, 3]);
        expect(api.registrations, isEmpty);
      } finally {
        await persisted.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'customer photo retries reuse registered identity and preserve offline bytes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'synthetic-finding-photo-',
      );
      final file = File('${directory.path}/photo.jpg');
      await file.writeAsBytes([1, 2, 3, 4]);
      try {
        await db.customStatement(
          "INSERT INTO local_finding_photos(id,business_id,finding_id,attachment_id,local_file_path,upload_state) VALUES('fixture-local-photo',?,'fixture-f1','fixture-local-photo',?,'pending')",
          [business, file.path],
        );
        await db.customStatement(
          "INSERT INTO sync_outbox(business_id,entity_type,entity_id,operation,payload_json,state,attempt_count,created_at) VALUES(?,'customer_finding_photo','fixture-local-photo','upload',?,'pending',0,1)",
          [
            business,
            jsonEncode({
              'customer_id': customer,
              'finding_id': 'fixture-f1',
              'local_file_path': file.path,
              'filename': 'photo.jpg',
              'mime_type': 'image/jpeg',
            }),
          ],
        );
        api.loseUploadReply = true;
        final customerWrites = OfflineCustomerDetailWriteService(
          database: db,
          api: api,
        );
        await customerWrites.flush(business);
        await customerWrites.flush(business);
        expect(api.registrations, [
          'fixture-local-photo',
          'fixture-local-photo',
        ]);
        final photos = await db
            .customSelect(
              "SELECT id,local_file_path,upload_state FROM local_finding_photos WHERE finding_id='fixture-f1'",
            )
            .get();
        expect(photos, hasLength(1));
        expect(photos.single.read<String>('id'), 'fixture-server-photo');
        expect(photos.single.read<String>('upload_state'), 'synced');
        expect(
          await File(
            photos.single.read<String>('local_file_path'),
          ).readAsBytes(),
          [1, 2, 3, 4],
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'identity remap updates photo dependencies from either entrypoint',
    () async {
      for (final type in ['finding_photo', 'customer_finding_photo']) {
        await db.customStatement(
          "INSERT INTO sync_outbox(business_id,entity_type,entity_id,operation,payload_json,state,attempt_count,created_at) VALUES(?,?,?,'upload',?,'pending',0,1)",
          [
            business,
            type,
            'photo-$type',
            jsonEncode({
              'finding_id': 'local-finding-origin',
              'local_finding_id': 'local-finding-origin',
            }),
          ],
        );
      }
      await actions.remap(
        business,
        'local-finding-origin',
        'fixture-canonical',
      );
      final rows = await db
          .customSelect('SELECT entity_id,payload_json FROM sync_outbox')
          .get();
      expect(rows, hasLength(2));
      for (final row in rows) {
        final payload = jsonDecode(row.read<String>('payload_json')) as Map;
        expect(payload['finding_id'], 'fixture-canonical');
        expect(payload['local_finding_id'], 'fixture-canonical');
        expect(row.read<String>('entity_id'), startsWith('photo-'));
      }
    },
  );

  test(
    'offline resolve immediately updates vehicle counts 2 to 1 to 0',
    () async {
      Future<int> count() async => (await work.loadLocalFindings(
        business,
        vehicle,
      )).where((row) => row['status'] != 'resolved').length;
      expect(await count(), 2);
      await actions.resolve(business, finding('fixture-f1'), job);
      expect(await count(), 1);
      await actions.resolve(business, finding('fixture-f2'), job);
      expect(await count(), 0);
      expect(
        (await db
            .customSelect(
              "SELECT id FROM sync_outbox WHERE entity_type='finding_action'",
            )
            .get()),
        hasLength(2),
      );
    },
  );

  test(
    'duplicate Add to Job and duplicate resolve retain single action per transition',
    () async {
      await actions.addToJob(business, finding('fixture-f1'), job);
      await actions.addToJob(business, finding('fixture-f1'), job);
      expect(
        await db
            .customSelect(
              "SELECT id FROM sync_outbox WHERE entity_type='finding_action'",
            )
            .get(),
        hasLength(1),
      );
      await actions.resolve(business, finding('fixture-f1'), job);
      await actions.resolve(business, finding('fixture-f1'), job);
      expect(
        await db
            .customSelect(
              "SELECT id FROM sync_outbox WHERE entity_type='finding_action'",
            )
            .get(),
        hasLength(2),
      );
      expect(await work.loadLocalFindings(business, vehicle), hasLength(2));
    },
  );

  test(
    'stale higher-version server reads cannot overwrite queued selection or resolved state',
    () async {
      await actions.setInvoiceFlag(business, finding('fixture-f1'), true);
      await actions.resolve(business, finding('fixture-f1'), job);
      final stale = {...finding('fixture-f1'), 'row_version': 20};
      await work.seedServerFindingsIfClean(business, vehicle, [
        stale,
        finding('fixture-f2'),
      ]);
      final local = await work.loadLocalFindings(business, vehicle);
      final merged = mergeWorkFindings([
        {...stale, 'row_version': 21},
      ], local);
      final result = merged.firstWhere((row) => row['id'] == 'fixture-f1');
      expect(result['status'], 'resolved');
      expect(result['include_on_invoice'], true);
      expect(result['sync_state'], 'pending');
    },
  );

  test('stale acknowledgement retains queued desired state', () async {
    api.staleAcknowledgement = true;
    await actions.setInvoiceFlag(business, finding('fixture-f1'), true);
    await actions.flush(business);
    expect(
      await db
          .customSelect(
            "SELECT id FROM sync_outbox WHERE entity_type='finding_action'",
          )
          .get(),
      hasLength(1),
    );
    expect(
      (await work.loadLocalFindings(
        business,
        vehicle,
      )).firstWhere((r) => r['id'] == 'fixture-f1')['include_on_invoice'],
      true,
    );
  });

  test(
    'lost Add reply retries verification without repeating repair linkage',
    () async {
      api.loseAddReply = true;
      await actions.addToJob(business, finding('fixture-f1'), job);
      await actions.flush(business);
      expect(api.addCalls, 1);
      await actions.flush(business);
      expect(api.addCalls, 1);
      expect(
        await db
            .customSelect(
              "SELECT id FROM sync_outbox WHERE entity_type='finding_action'",
            )
            .get(),
        isEmpty,
      );
    },
  );

  test(
    'unverified previous attempt never repeats an unsafe repair mutation',
    () async {
      api.staleAcknowledgement = true;
      await actions.addToJob(business, finding('fixture-f1'), job);
      await actions.flush(business);
      await actions.flush(business);
      expect(api.addCalls, 1);
      expect(
        await db
            .customSelect(
              "SELECT id FROM sync_outbox WHERE entity_type='finding_action'",
            )
            .get(),
        hasLength(1),
      );
      expect(
        (await work.loadLocalFindings(
          business,
          vehicle,
        )).firstWhere((r) => r['id'] == 'fixture-f1')['status'],
        'in_job',
      );
    },
  );

  test(
    'explicit finding ID wins over a generated-note ID when deduplicating',
    () async {
      await actions.setInvoiceFlag(business, finding('fixture-f1'), true);
      final detail = {
        ...invoice(),
        'finding_notes': [
          {
            'id': 'separate-note-record',
            'finding_id': 'fixture-f1',
            'body': 'Old generated text',
          },
        ],
      };
      final projected = await actions.projectInvoiceNotes(business, detail);
      expect(projected['finding_notes'], hasLength(1));
      expect(
        (projected['finding_notes'] as List).single['finding_id'],
        'fixture-f1',
      );
    },
  );

  test(
    'confirmed resolved state cannot be resurrected by earlier server version',
    () async {
      final stale = finding('fixture-f1');
      await actions.resolve(business, stale, job);
      await actions.flush(business);
      await work.seedServerFindingsIfClean(business, vehicle, [
        stale,
        finding('fixture-f2'),
      ]);
      expect(
        (await work.loadLocalFindings(
          business,
          vehicle,
        )).firstWhere((r) => r['id'] == 'fixture-f1')['status'],
        'resolved',
      );
    },
  );

  test(
    'invoice inclusion is identity based and untoggle preserves identical manual memo',
    () async {
      await actions.setInvoiceFlag(business, finding('fixture-f1'), true);
      final input = {...invoice(), 'memo': finding('fixture-f1')['body']};
      final once = await actions.projectInvoiceNotes(business, input);
      final twice = await actions.projectInvoiceNotes(business, once);
      expect(twice['finding_notes'], hasLength(1));
      await actions.setInvoiceFlag(business, finding('fixture-f1'), false);
      final off = await actions.projectInvoiceNotes(business, twice);
      expect(off['finding_notes'], isEmpty);
      expect(off['memo'], finding('fixture-f1')['body']);
      expect(off['total_amount'], 450);
    },
  );

  test(
    'selection does not contaminate a different Job invoice on same vehicle',
    () async {
      await actions.setInvoiceFlag(business, finding('fixture-f1'), true);
      final other = await actions.projectInvoiceNotes(
        business,
        invoice(jobId: 'fixture-job-J19', id: 'fixture-invoice-J19'),
      );
      expect(other['finding_notes'], isEmpty);
    },
  );

  test(
    'unassigned selection remains pending until explicitly linked to a Job',
    () async {
      final independent = finding('fixture-unassigned', foundJob: null);
      await actions.cacheCustomerFinding(business, independent);
      await actions.setInvoiceFlag(business, independent, true);
      expect(
        (await actions.projectInvoiceNotes(
          business,
          invoice(),
        ))['finding_notes'],
        isEmpty,
      );
      expect(
        (await actions.projectInvoiceNotes(
          business,
          invoice(jobId: 'fixture-job-J19', id: 'fixture-invoice-J19'),
        ))['finding_notes'],
        isEmpty,
      );
      await actions.addToJob(business, independent, job);
      expect(
        (await actions.projectInvoiceNotes(
          business,
          invoice(),
        ))['finding_notes'],
        hasLength(1),
      );
    },
  );

  test(
    'historical closed invoices retain their existing generated notes',
    () async {
      await actions.setInvoiceFlag(business, finding('fixture-f1'), true);
      final closed = {
        ...invoice(),
        'closed_at': '2026-10-14T14:00:00Z',
        'finding_notes': [
          {'id': 'historic', 'body': 'Saved contribution'},
        ],
      };
      expect(await actions.projectInvoiceNotes(business, closed), closed);
    },
  );

  test(
    'only newest editable invoice receives a newly selected contribution',
    () async {
      await db.customStatement(
        "INSERT INTO local_documents(id,business_id,job_id,kind,status,created_at) VALUES('fixture-old',?,?,'invoice','issued',10),('fixture-new',?,?,'invoice','issued',20)",
        [business, job, business, job],
      );
      await actions.setInvoiceFlag(business, finding('fixture-f1'), true);
      final old = {
        ...invoice(id: 'fixture-old'),
        'created_at': '1970-01-01T00:00:10Z',
      };
      final current = {
        ...invoice(id: 'fixture-new'),
        'created_at': '1970-01-01T00:00:20Z',
      };
      expect(
        (await actions.projectInvoiceNotes(business, old))['finding_notes'],
        isEmpty,
      );
      expect(
        (await actions.projectInvoiceNotes(business, current))['finding_notes'],
        hasLength(1),
      );
    },
  );

  test(
    'customer-created finding has same identity in Job repository offline',
    () async {
      final customerWrites = OfflineCustomerDetailWriteService(
        database: db,
        api: api,
      );
      final created = await customerWrites.createFinding(
        business,
        customer,
        vehicle,
        body: 'Synthetic customer finding',
        includeOnInvoice: true,
        photos: [],
      );
      final jobRows = await work.loadLocalFindings(business, vehicle);
      expect(jobRows.where((row) => row['id'] == created['id']), hasLength(1));
      await actions.addToJob(business, created, job, customerId: customer);
      final cached =
          await const CustomerDetailCache().load(business, customer, 'findings')
              as List;
      expect((cached.single as Map)['status'], 'in_job');
      expect(
        (await work.loadLocalFindings(
          business,
          vehicle,
        )).where((row) => row['id'] == created['id']).single['status'],
        'in_job',
      );
    },
  );

  test(
    'selection survives a database restart and applies to an invoice created later',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'synthetic-6334-',
      );
      final file = File('${directory.path}/fixture.sqlite');
      var persisted = BriskersLocalDatabase(NativeDatabase(file));
      try {
        var service = VehicleFindingActionsService(
          database: persisted,
          api: api,
        );
        await service.cacheCustomerFinding(
          business,
          finding('fixture-persistent'),
        );
        await service.setInvoiceFlag(
          business,
          finding('fixture-persistent'),
          true,
        );
        await persisted.close();
        persisted = BriskersLocalDatabase(NativeDatabase(file));
        service = VehicleFindingActionsService(database: persisted, api: api);
        final later = await service.projectInvoiceNotes(business, invoice());
        expect(later['finding_notes'], hasLength(1));
        expect(
          (later['finding_notes'] as List).single['id'],
          'fixture-persistent',
        );
      } finally {
        await persisted.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'uncertain repair survives restart visibly pending without replaying mutation',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'synthetic-finding-uncertain-',
      );
      final file = File('${directory.path}/fixture.sqlite');
      var persisted = BriskersLocalDatabase(NativeDatabase(file));
      api.staleAcknowledgement = true;
      try {
        var service = VehicleFindingActionsService(
          database: persisted,
          api: api,
        );
        await service.cacheCustomerFinding(business, finding('fixture-f1'));
        await service.addToJob(business, finding('fixture-f1'), job);
        await service.flush(business);
        expect(api.addCalls, 1);
        await persisted.close();
        persisted = BriskersLocalDatabase(NativeDatabase(file));
        service = VehicleFindingActionsService(database: persisted, api: api);
        await service.flush(business);
        final rows = await OfflineWorkFindingsService(
          database: persisted,
          api: api,
        ).loadLocalFindings(business, vehicle);
        expect(rows.single['status'], 'in_job');
        expect(rows.single['sync_state'], 'pending');
        expect(rows.single['_finding_action_error'], isNotEmpty);
        expect(api.addCalls, 1);
      } finally {
        await persisted.close();
        await directory.delete(recursive: true);
      }
    },
  );

  testWidgets('shared interface surfaces unresolved sync verification', (
    tester,
  ) async {
    Future<void> action(Map<String, dynamic> row) async {}
    final row = {
      ...finding('fixture-f1'),
      'sync_state': 'pending',
      '_finding_action_error': 'Synthetic unverified change',
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VehicleFindings(
            findings: [row],
            onEdit: action,
            onAddPhotos: action,
            onAddToJob: action,
            onResolve: action,
            onReopen: action,
            onInvoiceChanged: (row, value) async {},
          ),
        ),
      ),
    );
    expect(
      find.text('Needs verification • saved on this device'),
      findsOneWidget,
    );
  });

  testWidgets(
    'shared interface deduplicates IDs and labels all three statuses',
    (tester) async {
      final rows = [
        finding('fixture-f1'),
        finding('fixture-f1'),
        {...finding('fixture-f2'), 'status': 'in_job', 'repair_job_id': job},
        {...finding('fixture-f3'), 'status': 'resolved'},
      ];
      Future<void> action(Map<String, dynamic> row) async {}
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VehicleFindings(
                findings: rows,
                jobId: job,
                onEdit: action,
                onAddPhotos: action,
                onAddToJob: action,
                onResolve: action,
                onReopen: action,
                onInvoiceChanged: (row, value) async {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('Open 1 • In Job 1 • Resolved 1'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('vehicle-finding-fixture-f1')),
        findsOneWidget,
      );
      expect(find.text('Add to Job'), findsOneWidget);
      expect(find.text('Include in Invoice Notes'), findsNWidgets(2));
      expect(find.text('Resolve'), findsNWidgets(2));
    },
  );
}
