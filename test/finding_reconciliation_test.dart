import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/offline_work_findings_service.dart';
import 'package:briskers_app/services/work_finding_merge.dart';

const businessId = 'test-business';
const vehicleId = 'test-vehicle';
const jobId = 'test-job-12';

Map<String, dynamic> serverFinding(String id, {int version = 1}) => {
  'id': id,
  'vehicle_id': vehicleId,
  'found_job_id': jobId,
  'body': 'Original finding note',
  'row_version': version,
  'status': 'open',
  'repair_job_id': null,
  'resolved_at': null,
  'include_on_invoice': true,
  'created_at': '2026-10-12T12:00:00Z',
  'updated_at': '2026-10-12T12:00:00Z',
  'can_edit': true,
  'can_delete': false,
  'attachments': <Map<String, dynamic>>[],
};

Map<String, dynamic> copy(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

class _FindingApi extends BriskersApi {
  final findings = <String, Map<String, dynamic>>{};
  final operations = <String, Map<String, dynamic>>{};
  final registrations = <String, Map<String, dynamic>>{};
  final createOperations = <String>[];
  final updateOperations = <String>[];
  final updateVersions = <int?>[];
  final photoOperations = <String>[];
  bool loseCreateReply = false;
  bool loseUpdateReply = false;
  bool wrongUpdateId = false;
  Map<String, dynamic>? createAcknowledgement;
  Map<String, dynamic>? updateAcknowledgement;
  int failedUploads = 0;
  int uploads = 0;
  Completer<void>? createStarted;
  Completer<void>? createRelease;
  Completer<void>? updateStarted;
  Completer<void>? updateRelease;

  List<Map<String, dynamic>> snapshot() => findings.values.map(copy).toList();

  @override
  Future<Map<String, dynamic>> syncCreateFinding(
    String businessId,
    String jobId, {
    required String operationId,
    required String body,
    bool includeOnInvoice = false,
  }) async {
    createOperations.add(operationId);
    if (createAcknowledgement != null) {
      return {'status': 'applied', 'finding': copy(createAcknowledgement!)};
    }
    final response = operations.putIfAbsent(operationId, () {
      final row = serverFinding('server-${findings.length + 1}')
        ..['body'] = body
        ..['include_on_invoice'] = includeOnInvoice;
      findings[row['id'].toString()] = row;
      return {'status': 'applied', 'finding': copy(row)};
    });
    if (createStarted != null && !createStarted!.isCompleted) {
      createStarted!.complete();
      await createRelease!.future;
    }
    if (loseCreateReply) {
      loseCreateReply = false;
      throw const SocketException('Response lost after server applied create');
    }
    return copy(response);
  }

  @override
  Future<Map<String, dynamic>> syncUpdateFinding(
    String businessId,
    String findingId, {
    required String operationId,
    required int? expectedRowVersion,
    required String body,
  }) async {
    updateOperations.add(operationId);
    updateVersions.add(expectedRowVersion);
    if (updateAcknowledgement != null) {
      return {'status': 'applied', 'finding': copy(updateAcknowledgement!)};
    }
    if (wrongUpdateId) {
      return {'status': 'applied', 'finding': serverFinding('wrong-finding')};
    }
    final response = operations.putIfAbsent(operationId, () {
      final existing = findings[findingId]!;
      if (existing['row_version'] != expectedRowVersion) {
        return {'status': 'conflict', 'server': copy(existing)};
      }
      final updated = copy(existing)
        ..['body'] = body
        ..['row_version'] = (expectedRowVersion ?? 0) + 1;
      findings[findingId] = updated;
      return {'status': 'applied', 'finding': copy(updated)};
    });
    if (updateStarted != null && !updateStarted!.isCompleted) {
      updateStarted!.complete();
      await updateRelease!.future;
    }
    if (loseUpdateReply) {
      loseUpdateReply = false;
      throw const SocketException('Response lost after server applied update');
    }
    return copy(response);
  }

  @override
  Future<Map<String, dynamic>> syncRegisterFindingPhoto(
    String businessId,
    String findingId, {
    required String operationId,
    required String filename,
    required String mimeType,
  }) async {
    expect(findingId, isNot(startsWith('local-finding-')));
    photoOperations.add(operationId);
    return copy(registrations.putIfAbsent(operationId, () {
      final id = 'attachment-${registrations.length + 1}';
      final registration = {
        'attachment_id': id,
        'bucket': 'test-bucket',
        'key': '$findingId/$id',
        'filename': filename,
        'mime_type': mimeType,
      };
      (findings[findingId]!['attachments'] as List).add(registration);
      return registration;
    }));
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
    expect(bytes, [1, 2, 3, 4]);
    uploads++;
    if (failedUploads > 0) {
      failedUploads--;
      throw const SocketException('Photo upload interrupted');
    }
  }
}

void main() {
  late Directory temp;
  late BriskersLocalDatabase database;
  late _FindingApi api;
  late OfflineWorkFindingsService service;

  OfflineWorkFindingsService makeService() => OfflineWorkFindingsService(
    database: database,
    api: api,
    mediaDirectoryProvider: () async => temp,
  );

  Future<List<Map<String, dynamic>>> local() =>
      service.loadLocalFindings(businessId, vehicleId);

  Future<Map<String, dynamic>> stagePhoto(String findingId) =>
      service.stageFindingPhoto(
        businessId, jobId, findingId,
        filename: 'finding.jpg', mimeType: 'image/jpeg',
        bytes: Uint8List.fromList([1, 2, 3, 4]),
      );

  Future<void> seed() => service.seedServerFindingsIfClean(
    businessId, vehicleId, api.snapshot(),
  );

  Future<void> expectEmptyOutbox() async {
    final rows = await database.customSelect('SELECT * FROM sync_outbox').get();
    expect(rows, isEmpty);
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('finding-reconciliation-');
    database = BriskersLocalDatabase(NativeDatabase(File('${temp.path}/cache.db')));
    api = _FindingApi();
    service = makeService();
  });

  tearDown(() async {
    await database.close();
    await temp.delete(recursive: true);
  });

  test('lost create reply, restart, edit, photo and retries reconcile once', () async {
    final created = await service.createLocalFinding(
      businessId, jobId, vehicleId: vehicleId,
      body: 'First note', includeOnInvoice: true,
    );
    final localId = created['id'].toString();
    final staged = await stagePhoto(localId);
    var display = await local();
    api.loseCreateReply = true;
    await service.flush(businessId);
    expect((await local()).single['sync_state'], 'pending');
    expect(api.findings, hasLength(1));

    await database.close();
    database = BriskersLocalDatabase(NativeDatabase(File('${temp.path}/cache.db')));
    service = makeService();
    await service.updateLocalFinding(
      businessId, jobId, localId, body: 'Edited after lost reply',
    );
    await service.flush(businessId);
    expect(api.createOperations, hasLength(2));
    expect(api.createOperations.toSet(), hasLength(1));
    expect(api.findings, hasLength(1));
    expect(api.findings.values.single['body'], 'Edited after lost reply');

    for (var retry = 0; retry < 4; retry++) {
      display = mergeWorkFindings(display, await local());
      expect(display, hasLength(1));
      expect(display.single['id'], 'server-1');
      expect(display.single['body'], 'Edited after lost reply');
      expect(display.single['include_on_invoice'], true);
      expect(display.single['attachments'], hasLength(1));
      await seed();
      await service.flush(businessId);
    }
    final attachment = ((await local()).single['attachments'] as List).single as Map;
    expect(attachment['attachment_id'], 'attachment-1');
    expect(attachment['upload_state'], 'synced');
    expect(attachment['local_file_path'], staged['local_file_path']);
    expect(await File(staged['local_file_path'].toString()).readAsBytes(), [1, 2, 3, 4]);
    expect(api.uploads, 1);
    await expectEmptyOutbox();
  });

  test('editing during create and concurrent service flushes preserves latest note', () async {
    final created = await service.createLocalFinding(
      businessId, jobId, vehicleId: vehicleId, body: 'First note',
    );
    api.createStarted = Completer<void>();
    api.createRelease = Completer<void>();
    final flush = service.flush(businessId);
    await api.createStarted!.future;
    await service.updateLocalFinding(
      businessId, jobId, created['id'].toString(), body: 'Saved during create',
    );
    final secondFlush = makeService().flush(businessId);
    api.createRelease!.complete();
    await Future.wait([flush, secondFlush]);
    expect(api.createOperations, hasLength(1));
    expect(api.updateOperations, hasLength(1));
    expect((await local()).single['body'], 'Saved during create');
    expect(api.findings.values.single['body'], 'Saved during create');
    expect((await local()).single['sync_state'], 'synced');
    await expectEmptyOutbox();
  });

  test('editing during update preserves notes, photos and repair assignment', () async {
    api.findings['server-1'] = serverFinding('server-1')
      ..['status'] = 'in_job'
      ..['repair_job_id'] = jobId;
    await seed();
    await stagePhoto('server-1');
    await service.updateLocalFinding(businessId, jobId, 'server-1', body: 'First edit');
    api.updateStarted = Completer<void>();
    api.updateRelease = Completer<void>();
    final flush = service.flush(businessId);
    await api.updateStarted!.future;
    await service.updateLocalFinding(businessId, jobId, 'server-1', body: 'Latest edit');
    api.updateRelease!.complete();
    await flush;
    expect(api.updateOperations.toSet(), hasLength(2));
    expect(api.updateVersions, [1, 2]);
    final finding = (await local()).single;
    expect(finding['body'], 'Latest edit');
    expect(finding['status'], 'in_job');
    expect(finding['repair_job_id'], jobId);
    expect(finding['attachments'], hasLength(1));
    expect(api.findings['server-1']!['body'], 'Latest edit');
    await expectEmptyOutbox();
  });

  test('lost update reply followed by another edit gets a new idempotency key', () async {
    api.findings['server-1'] = serverFinding('server-1');
    await seed();
    await service.updateLocalFinding(businessId, jobId, 'server-1', body: 'First edit');
    api.loseUpdateReply = true;
    await service.flush(businessId);
    await service.updateLocalFinding(businessId, jobId, 'server-1', body: 'Latest edit');
    await service.flush(businessId);
    expect(api.updateOperations, hasLength(3));
    expect(api.updateOperations[0], api.updateOperations[1]);
    expect(api.updateOperations[2], isNot(api.updateOperations[0]));
    expect(api.updateVersions, [1, 1, 2]);
    expect((await local()).single['body'], 'Latest edit');
    expect(api.findings['server-1']!['body'], 'Latest edit');
    await expectEmptyOutbox();
  });

  test('dirty finding preserves edit while independent repair metadata refreshes', () async {
    api.findings['dirty'] = serverFinding('dirty');
    api.findings['clean'] = serverFinding('clean');
    await seed();
    await service.updateLocalFinding(businessId, jobId, 'dirty', body: 'Offline note');
    final staged = await stagePhoto('dirty');
    api.findings['dirty'] = serverFinding('dirty', version: 2)
      ..['status'] = 'in_job'
      ..['repair_job_id'] = jobId
      ..['attachments'] = [{'attachment_id': 'remote-photo', 'bucket': 'test', 'key': 'remote.jpg'}];
    api.findings['clean'] = serverFinding('clean', version: 3)
      ..['status'] = 'resolved'
      ..['repair_job_id'] = jobId
      ..['resolved_at'] = '2026-10-13T00:00:00Z';
    api.findings['new'] = serverFinding('new');
    for (var refresh = 0; refresh < 3; refresh++) {
      await seed();
      final rows = {for (final row in await local()) row['id']: row};
      expect(rows, hasLength(3));
      expect(rows['dirty']!['body'], 'Offline note');
      expect(rows['dirty']!['row_version'], 2);
      expect(rows['dirty']!['sync_state'], 'pending');
      expect(rows['dirty']!['status'], 'in_job');
      expect(rows['dirty']!['repair_job_id'], jobId);
      expect(rows['dirty']!['attachments'], hasLength(2));
      expect(rows['clean']!['status'], 'resolved');
      expect(rows['clean']!['resolved_at'], isNotNull);
    }
    expect(await File(staged['local_file_path'].toString()).exists(), true);
    await service.flush(businessId);
    final dirty = (await local()).singleWhere((row) => row['id'] == 'dirty');
    expect(dirty['sync_state'], 'conflict');
    expect(dirty['body'], 'Offline note');
    await seed();
    expect((await local()).singleWhere((row) => row['id'] == 'dirty')['sync_state'], 'conflict');
  });

  test('photo retry reconciles a server attachment already seen by refresh', () async {
    final created = await service.createLocalFinding(
      businessId, jobId, vehicleId: vehicleId, body: 'Photo finding',
    );
    final staged = await stagePhoto(created['id'].toString());
    api.failedUploads = 1;
    await service.flush(businessId);
    final before = (await local()).single;
    expect(before['id'], 'server-1');
    expect((before['attachments'] as List).single['upload_state'], 'pending');
    await seed();
    await service.flush(businessId);
    final after = (await local()).single;
    final photos = after['attachments'] as List;
    expect(photos, hasLength(1));
    expect(photos.single['attachment_id'], 'attachment-1');
    expect(photos.single['upload_state'], 'synced');
    expect(photos.single['local_file_path'], staged['local_file_path']);
    expect(api.photoOperations.toSet(), hasLength(1));
    await expectEmptyOutbox();
  });

  test('older snapshot and malformed acknowledgement cannot erase cached note', () async {
    api.findings['server-1'] = serverFinding('server-1', version: 3)
      ..['body'] = 'Latest acknowledged note';
    await seed();
    await service.seedServerFindingsIfClean(
      businessId, vehicleId, [serverFinding('server-1')],
    );
    expect((await local()).single['body'], 'Latest acknowledged note');
    await service.updateLocalFinding(businessId, jobId, 'server-1', body: 'Pending note');
    api.wrongUpdateId = true;
    await service.flush(businessId);
    final row = (await local()).single;
    expect(row['id'], 'server-1');
    expect(row['body'], 'Pending note');
    expect(row['sync_state'], 'pending');
    final outbox = await database.customSelect('SELECT * FROM sync_outbox').get();
    expect(outbox, hasLength(1));
    expect(outbox.single.read<int>('attempt_count'), 1);
  });

  test('photo staging and an open edit follow a finding remapped during the picker', () async {
    final created = await service.createLocalFinding(
      businessId, jobId, vehicleId: vehicleId, body: 'Before picker',
    );
    final oldId = created['id'].toString();
    final stagingStarted = Completer<void>();
    final releaseStaging = Completer<void>();
    final delayed = OfflineWorkFindingsService(
      api: api, database: database,
      mediaDirectoryProvider: () async {
        stagingStarted.complete();
        await releaseStaging.future;
        return temp;
      },
    );
    final photo = delayed.stageFindingPhoto(
      businessId, jobId, oldId, filename: 'finding.jpg',
      mimeType: 'image/jpeg', bytes: Uint8List.fromList([1, 2, 3, 4]),
    );
    await stagingStarted.future;
    await service.flush(businessId);
    releaseStaging.complete();
    await photo;
    await makeService().updateLocalFinding(
      businessId, jobId, oldId, body: 'Saved from already-open editor',
    );
    final queued = await database.customSelect(
      "SELECT payload_json FROM sync_outbox WHERE entity_type='finding_photo'",
    ).getSingle();
    expect((jsonDecode(queued.read<String>('payload_json')) as Map)['finding_id'], 'server-1');
    await service.flush(businessId);
    final finding = (await local()).single;
    expect(finding['id'], 'server-1');
    expect(finding['body'], 'Saved from already-open editor');
    expect(finding['attachments'], hasLength(1));
    await expectEmptyOutbox();
  });

  for (final invalid in <String, Map<String, dynamic>>{
    'different vehicle': serverFinding('server-1')..['vehicle_id'] = 'other-vehicle',
    'different Job': serverFinding('server-1')..['found_job_id'] = 'other-job',
    'missing body': serverFinding('server-1')..remove('body'),
    'missing version': serverFinding('server-1')..remove('row_version'),
    'provisional ID': serverFinding('local-finding-invalid'),
  }.entries) {
    test('create acknowledgement with ${invalid.key} preserves draft and photo', () async {
      final created = await service.createLocalFinding(
        businessId, jobId, vehicleId: vehicleId, body: 'Preserve this note',
      );
      final oldId = created['id'].toString();
      await stagePhoto(oldId);
      api.createAcknowledgement = invalid.value;
      await service.flush(businessId);
      final finding = (await local()).single;
      expect(finding['id'], oldId);
      expect(finding['body'], 'Preserve this note');
      expect(finding['sync_state'], 'pending');
      expect(finding['attachments'], hasLength(1));
      final photos = await database.customSelect('SELECT finding_id FROM local_finding_photos').get();
      expect(photos.single.read<String>('finding_id'), oldId);
      final outbox = await database.customSelect('SELECT * FROM sync_outbox').get();
      expect(outbox, hasLength(2));
      expect(api.uploads, 0);
    });
  }

  for (final missing in ['body', 'row_version']) {
    test('update acknowledgement missing $missing does not retire the edit', () async {
      api.findings['server-1'] = serverFinding('server-1');
      await seed();
      await service.updateLocalFinding(businessId, jobId, 'server-1', body: 'Pending note');
      api.updateAcknowledgement = serverFinding('server-1')..remove(missing);
      await service.flush(businessId);
      expect((await local()).single['body'], 'Pending note');
      expect((await local()).single['sync_state'], 'pending');
      expect(await database.customSelect('SELECT * FROM sync_outbox').get(), hasLength(1));
    });
  }

  test('partial update acknowledgement retains known repair and photo fields', () async {
    api.findings['server-1'] = serverFinding('server-1')
      ..['status'] = 'in_job'
      ..['repair_job_id'] = jobId
      ..['attachments'] = [{'attachment_id': 'original-photo', 'bucket': 'test', 'key': 'original.jpg'}];
    await seed();
    await service.updateLocalFinding(businessId, jobId, 'server-1', body: 'Updated note');
    api.updateAcknowledgement = {'id': 'server-1', 'body': 'Updated note', 'row_version': 2};
    await service.flush(businessId);
    final finding = (await local()).single;
    expect(finding['status'], 'in_job');
    expect(finding['repair_job_id'], jobId);
    expect(finding['include_on_invoice'], true);
    expect(finding['attachments'], hasLength(1));
    expect(finding['body'], 'Updated note');
    expect(finding['sync_state'], 'synced');
    await expectEmptyOutbox();
  });


  test('out-of-order dirty refreshes retain latest metadata and original edit base after restart', () async {
    api.findings['server-1'] = serverFinding('server-1');
    await seed();
    await service.updateLocalFinding(businessId, jobId, 'server-1', body: 'Offline note');
    final staged = await stagePhoto('server-1');
    api.findings['server-1'] = serverFinding('server-1', version: 3)
      ..['body'] = 'Latest remote note'
      ..['status'] = 'resolved'
      ..['repair_job_id'] = jobId
      ..['resolved_at'] = '2026-10-13T00:00:00Z'
      ..['attachments'] = [{'attachment_id': 'latest-photo'}];
    await seed();
    await database.close();
    database = BriskersLocalDatabase(NativeDatabase(File('${temp.path}/cache.db')));
    service = makeService();
    await service.updateLocalFinding(businessId, jobId, 'server-1', body: 'Further offline note');
    final delayed = serverFinding('server-1', version: 2)
      ..['status'] = 'in_job'
      ..['attachments'] = [{'attachment_id': 'outdated-photo'}];
    for (var retry = 0; retry < 3; retry++) {
      await service.seedServerFindingsIfClean(businessId, vehicleId, [delayed]);
      final finding = (await local()).single;
      expect(finding['row_version'], 3);
      expect(finding['body'], 'Further offline note');
      expect(finding['status'], 'resolved');
      expect(finding['repair_job_id'], jobId);
      expect(finding['resolved_at'], isNotNull);
      expect((finding['attachments'] as List).map((photo) => photo['attachment_id']),
          containsAll(['latest-photo', staged['attachment_id']]));
      expect((finding['attachments'] as List).map((photo) => photo['attachment_id']),
          isNot(contains('outdated-photo')));
    }
    final queued = await database.customSelect(
      "SELECT * FROM sync_outbox WHERE entity_type='finding_update'",
    ).getSingle();
    expect(queued.read<int>('base_row_version'), 1);
    final payload = jsonDecode(queued.read<String>('payload_json')) as Map;
    expect((payload['latest_server_finding'] as Map)['row_version'], 3);
    expect((payload['latest_server_finding'] as Map)['body'], 'Latest remote note');
    await service.flush(businessId);
    expect(api.updateVersions, [1]);
    expect((await local()).single['sync_state'], 'conflict');
    expect((await local()).single['status'], 'resolved');
  });

  for (final editAgain in [false, true]) {
    test('delayed update acknowledgement retains newer repair/photos, later edit=$editAgain', () async {
      api.findings['server-1'] = serverFinding('server-1')
        ..['attachments'] = [{'attachment_id': 'old-photo'}];
      await seed();
      await service.updateLocalFinding(businessId, jobId, 'server-1', body: 'Acknowledged note');
      api.updateStarted = Completer<void>();
      api.updateRelease = Completer<void>();
      final flush = service.flush(businessId);
      await api.updateStarted!.future;
      api.findings['server-1'] = serverFinding('server-1', version: 3)
        ..['body'] = 'Later remote note'
        ..['status'] = 'resolved'
        ..['repair_job_id'] = jobId
        ..['resolved_at'] = '2026-10-13T00:00:00Z'
        ..['attachments'] = [{'attachment_id': 'latest-photo'}];
      await seed();
      if (editAgain) {
        await service.updateLocalFinding(businessId, jobId, 'server-1', body: 'Unsent newer note');
      }
      api.updateRelease!.complete();
      await flush;
      final finding = (await local()).single;
      expect(finding['row_version'], 3);
      expect(finding['status'], 'resolved');
      expect(finding['repair_job_id'], jobId);
      expect(finding['resolved_at'], isNotNull);
      expect((finding['attachments'] as List).map((photo) => photo['attachment_id']), ['latest-photo']);
      expect(api.findings['server-1']!['body'], 'Later remote note');
      if (editAgain) {
        expect(finding['body'], 'Unsent newer note');
        expect(finding['sync_state'], 'conflict');
        expect(api.updateVersions, [1, 2]);
        final queued = await database.customSelect('SELECT * FROM sync_outbox').getSingle();
        expect(queued.read<int>('base_row_version'), 2);
        expect(queued.read<String>('state'), 'conflict');
      } else {
        expect(finding['body'], 'Later remote note');
        expect(finding['sync_state'], 'synced');
        expect(api.updateVersions, [1]);
        await expectEmptyOutbox();
      }
    });
  }

  test('delayed create acknowledgement retains an already-observed canonical finding', () async {
    final created = await service.createLocalFinding(
      businessId, jobId, vehicleId: vehicleId, body: 'Acknowledged original note',
    );
    await stagePhoto(created['id'].toString());
    api.createStarted = Completer<void>();
    api.createRelease = Completer<void>();
    final flush = service.flush(businessId);
    await api.createStarted!.future;
    api.findings['server-1'] = serverFinding('server-1', version: 3)
      ..['body'] = 'Later remote note'
      ..['status'] = 'resolved'
      ..['repair_job_id'] = jobId
      ..['resolved_at'] = '2026-10-13T00:00:00Z'
      ..['attachments'] = [{'attachment_id': 'latest-photo'}];
    await seed();
    api.createRelease!.complete();
    await flush;
    final finding = (await local()).single;
    expect(finding['id'], 'server-1');
    expect(finding['row_version'], 3);
    expect(finding['body'], 'Later remote note');
    expect(finding['status'], 'resolved');
    expect(finding['repair_job_id'], jobId);
    expect(finding['attachments'], hasLength(2));
    expect(api.updateVersions, isEmpty);
    await expectEmptyOutbox();
  });

}
