import 'dart:convert';
import 'dart:io';
import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/services/local_estimate_number.dart';
import 'package:briskers_app/services/document_pdf_service.dart';
import 'package:briskers_app/services/email_draft_templates.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/offline_document_draft_service.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_document_repository.dart';
import 'package:briskers_app/services/local_repair_groups.dart';

class _StandaloneApi extends BriskersApi {
  final List<String> operationIds = [];
  var detailAttempts = 0;
  bool invalidServerPositions = false;
  late String syncedNumber;
  late String syncedDate;
  late List<Map<String, dynamic>> syncedLines;
  String? syncedMemo;
  @override
  Future<String> syncOfflineStandaloneEstimate(
    String businessId, {
    required String customerId,
    String? vehicleId,
    required String operationId,
    required String publicNumber,
    required String documentDate,
    required List<Map<String, dynamic>> lines,
    String? memo,
  }) async {
    operationIds.add(operationId);
    syncedNumber = publicNumber;
    syncedDate = documentDate;
    // Simulate the quote stored by the idempotent server create; only
    // server-assigned row IDs change. The response must not be a stale,
    // incomplete hard-coded line now that replay verifies every field.
    syncedLines = [
      for (final line in lines)
        <String, dynamic>{...line, 'id': 'server-line',
          'position': invalidServerPositions ? 0 : line['position']},
    ];
    syncedMemo = memo;
    expect(customerId, 'customer-id');
    expect(lines, hasLength(1));
    expect(lines.single['name'], 'Labor');
    expect(memo, 'Price subject to inspection');
    return operationId;
  }

  @override
  Future<Map<String, dynamic>> documentDetail(
    String businessId,
    String documentId,
  ) async {
    detailAttempts++;
    if (detailAttempts == 1) throw StateError('Simulated dropped response');
    return {
      'id': documentId,
      'kind': 'estimate',
      'document_number': syncedNumber,
      'job_id': null,
      'status': 'draft',
      'customer_id': 'customer-id',
      'customer_name': 'Test Customer',
      // Idempotent create returns the date it originally committed.
      'document_date': syncedDate,
      'row_version': 2,
      'net_amount': 220,
      'tax_amount': 0,
      'total_amount': 220,
      'origin': 'native',
      'legacy_read_only': false,
      'memo': syncedMemo,
      'lines': syncedLines,
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('standalone offline estimate uses no Job and idempotent upload', () async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('estimate-restart');
    final file = File('${directory.path}/local.sqlite');
    final mode = BriskersConnectionModeController.instance;
    await mode.setMode(BriskersConnectionMode.offline);
    var db = BriskersLocalDatabase(NativeDatabase(file));
    final api = _StandaloneApi();
    var cache = LocalDocumentDetailCache(database: db);
    var drafts = OfflineDocumentDraftService(
      database: db,
      api: api,
      cache: cache,
    );
    addTearDown(() async {
      await db.close();
      await directory.delete(recursive: true);
      LocalDocumentDetailCache.sqliteWritesEnabled = false;
      await mode.setMode(BriskersConnectionMode.auto);
    });
    await LocalDocumentDetailCache.initialize(db);
    final localId = await drafts.createStandaloneEstimate(
      'shop',
      customerId: 'customer-id',
      customerName: 'Test Customer',
    );
    expect(localId, startsWith('local-estimate-'));
    final number = await LocalEstimateNumber.stored(db, 'shop', localId);
    expect(number, 'E-1');
    expect((await cache.load('shop', localId))?['document_number'], number);
    expect(
      DocumentPdfService.fileName((await cache.load('shop', localId))!),
      'Briskers-Estimate-$number.pdf',
    );
    expect((await cache.load('shop', localId))?['job_id'], isNull);
    final templates = await EmailDraftTemplates.load('shop');
    expect(
      templates.render(templates.subject, estimate: true, number: number!),
      'Estimate #$number - Briskers Foreign Car Repair',
    );
    final jobs = await db
        .customSelect("SELECT id FROM local_jobs WHERE business_id='shop'")
        .get();
    expect(jobs, isEmpty);
    await drafts.addLine(
      'shop',
      localId,
      name: 'Labor',
      lineKind: 'labor',
      quantity: 4.4,
      unitPrice: 50,
      taxRate: 0,
    );
    await drafts.saveMemo('shop', localId, 'Price subject to inspection');
    await drafts.flush('shop');
    expect(api.operationIds, isEmpty);
    // Reproduce the legacy index and cached detail, then restart in Force Offline.
    await db.customStatement(
      'UPDATE local_documents SET document_number=NULL WHERE id=?',
      [localId],
    );
    await db.customStatement(
      "UPDATE local_document_details SET payload_json=json_set(payload_json,'\$.document_number',null) WHERE cache_key=?",
      [LocalDocumentDetailCache.key('shop', localId)],
    );
    await db.close();
    db = BriskersLocalDatabase(NativeDatabase(file));
    await LocalDocumentDetailCache.initialize(db);
    cache = LocalDocumentDetailCache(database: db);
    drafts = OfflineDocumentDraftService(database: db, api: api, cache: cache);
    expect((await cache.load('shop', localId))?['document_number'], number);
    expect(
      (await LocalDocumentRepository(
        database: db,
      ).listByKind('shop', kind: 'estimate')).single['document_number'],
      number,
    );
    await mode.setMode(BriskersConnectionMode.auto);
    await drafts.flush('shop');
    final retry = await db
        .customSelect("SELECT state FROM sync_outbox WHERE business_id='shop'")
        .get();
    expect(retry, hasLength(1));
    await drafts.flush('shop');
    expect(api.operationIds, hasLength(2));
    expect(api.operationIds.first, api.operationIds.last);
    final details = await cache.load('shop', localId);
    expect(
      details?['_server_document_id'],
      api.operationIds.singleOrNull ?? api.operationIds.first,
    );
    expect(details?['document_number'], number);
    final documents = await LocalDocumentRepository(
      database: db,
    ).listByKind('shop', kind: 'estimate');
    expect(documents, hasLength(1));
    expect(documents.single['job_id'], isNull);
    expect(documents.single['document_number'], number);
    expect(
      (await db
          .customSelect("SELECT id FROM local_jobs WHERE business_id='shop'")
          .get()),
      isEmpty,
    );
  });
  for (final invalidServerPositions in [false, true]) {
    test(
      invalidServerPositions
          ? 'invalid server line positions leave offline grouped estimate in review without retry'
          : 'offline grouped estimate retains membership after real outbox line-ID remap',
      () async {
        SharedPreferences.setMockInitialValues({});
        final mode = BriskersConnectionModeController.instance;
        await mode.setMode(BriskersConnectionMode.offline);
        final db = BriskersLocalDatabase(NativeDatabase.memory());
        addTearDown(() async {
          await db.close();
          LocalDocumentDetailCache.sqliteWritesEnabled = false;
          await mode.setMode(BriskersConnectionMode.auto);
        });
        await LocalDocumentDetailCache.initialize(db);
        final cache = LocalDocumentDetailCache(database: db);
        final api = _StandaloneApi()
          ..invalidServerPositions = invalidServerPositions;
        final drafts = OfflineDocumentDraftService(
          database: db, cache: cache, api: api,
        );
        final localId = await drafts.createStandaloneEstimate(
          'shop', customerId: 'customer-id', customerName: 'Test Customer',
        );
        await drafts.addLine('shop', localId,
          name: 'Labor', lineKind: 'labor', quantity: 4.4,
          unitPrice: 50, taxRate: 0,
        );
        await drafts.saveMemo('shop', localId, 'Price subject to inspection');
        final before = (await cache.load('shop', localId))!;
        final localLineId = (before['lines'] as List).single['id'] as String;
        final groups = LocalRepairGroups(database: db, cache: cache);
        await groups.add('shop', localId, name: 'Brake repair', description: '');
        final groupId = (await groups.groups('shop', localId, before)).first.id;
        await groups.move('shop', localId, {localLineId}, groupId);

        await mode.setMode(BriskersConnectionMode.auto);
        await drafts.flush('shop'); // Simulate a lost first server detail response.
        await drafts.flush('shop'); // Reconcile the same idempotent operation.
        expect(api.operationIds, hasLength(2));
        expect(api.operationIds.first, api.operationIds.last);
        final outbox = await db.customSelect(
          "SELECT state FROM sync_outbox WHERE business_id='shop'",
        ).get();
        if (invalidServerPositions) {
          expect(outbox, hasLength(1));
          expect(outbox.single.read<String>('state'), 'conflict');
          final retained = (await cache.load('shop', localId))!;
          expect(retained['sync_state'], 'conflict');
          expect(retained['_server_document_id'], isNull);
          expect((await groups.groups('shop', localId, retained))
              .first.lines.single['id'], localLineId);
          expect(retained['total_amount'], before['total_amount']);
          await drafts.flush('shop');
          expect(api.operationIds, hasLength(2)); // No automatic retry storm.
        } else {
          expect(outbox, isEmpty);
          final serverId = api.operationIds.first;
          final serverDetail = (await cache.load('shop', serverId))!;
          final sections = await groups.groups('shop', serverId, serverDetail);
          expect(sections.first.id, groupId);
          expect(sections.first.lines.single['id'], 'server-line');
          expect(sections.last.lines, isEmpty);
          expect(serverDetail['total_amount'], before['total_amount']);
          expect((await cache.load('shop', localId))?['_server_document_id'], serverId);
        }
      },
    );
  }

  test(
    'legacy or sent numbers survive blank refreshes and generated numbers stay unique',
    () async {
      SharedPreferences.setMockInitialValues({});
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final docs = LocalDocumentRepository(database: db);
      final estimate = {
        'id': '00000000-0000-4000-8000-000000000010',
        'kind': 'estimate',
        'status': 'sent',
        'document_number': 'E-0236',
      };
      await docs.upsertFromServer('shop', [estimate]);
      await docs.replaceFromServer('shop', [
        {...estimate, 'document_number': null},
      ], kind: 'estimate');
      expect(
        (await docs.listByKind(
          'shop',
          kind: 'estimate',
        )).single['document_number'],
        'E-0236',
      );
      final drafts = OfflineDocumentDraftService(database: db);
      final first = await drafts.createStandaloneEstimate(
        'shop',
        customerId: 'customer',
        customerName: 'Fixture',
      );
      final second = await drafts.createStandaloneEstimate(
        'shop',
        customerId: 'customer',
        customerName: 'Fixture',
      );
      expect(await LocalEstimateNumber.stored(db, 'shop', first), 'E-237');
      expect(await LocalEstimateNumber.stored(db, 'shop', second), 'E-238');
    },
  );

  test(
    'repair preserves both historical estimates and reserves consecutive numbers on this device',
    () async {
      SharedPreferences.setMockInitialValues({});
      final mode = BriskersConnectionModeController.instance;
      await mode.setMode(BriskersConnectionMode.offline);
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      addTearDown(() async {
        await mode.setMode(BriskersConnectionMode.auto);
        LocalDocumentDetailCache.sqliteWritesEnabled = false;
        await db.close();
      });
      final cache = LocalDocumentDetailCache(database: db);
      await LocalDocumentDetailCache.initialize(db);
      final original = [
        {
          'id': 'jennifer-legacy',
          'kind': 'estimate',
          'document_number': null,
          'status': 'draft',
          'document_date': '2026-11-16',
          'customer_name': 'Jennifer McCrossen',
          'vehicle': '2023 Porsche Cayenne',
          'total_amount': 1879.03,
          'memo': 'Customer estimate',
          'lines': [
            {'id': 'labor-line', 'name': 'Labor', 'unit_price': 1879.03},
          ],
          'attachments': [
            {'id': 'photo-1', 'filename': 'photo.jpg'},
          ],
        },
        {
          'id': 'october-legacy',
          'kind': 'estimate',
          'document_number': 'E-EST-1962E96CA13640F',
          'status': 'draft',
          'document_date': '2026-10-10',
          'total_amount': 137.19,
        },
        {
          'id': 'issued-legacy',
          'kind': 'estimate',
          'document_number': 'EST-OLD-ISSUED',
          'status': 'issued',
          'document_date': '2026-10-01',
          'total_amount': 148.42,
        },
        {
          'id': 'valid',
          'kind': 'estimate',
          'document_number': 'E-1997',
          'status': 'issued',
        },
      ];
      for (final estimate in original) {
        final id = estimate['id'] as String;
        await db.customStatement(
          "INSERT INTO local_documents(id,business_id,kind,document_number,status,document_date,total) "
          "VALUES(?,'shop','estimate',?,?,?,?)",
          [
            id,
            estimate['document_number'],
            estimate['status'],
            estimate['document_date'],
            estimate['total_amount'] ?? 0,
          ],
        );
        // Seed snapshots written by the old APK, before opening the new cache.
        await db.customStatement(
          'INSERT INTO local_document_details VALUES(?,?)',
          [LocalDocumentDetailCache.key('shop', id), jsonEncode(estimate)],
        );
      }
      await LocalDocumentDetailCache.initialize(db);
      final jennifer = await cache.load('shop', 'jennifer-legacy');
      expect(jennifer, {...original[0], 'document_number': 'E-1999'});
      expect(await cache.load('shop', 'october-legacy'), {
        ...original[1],
        'document_number': 'E-1998',
      });
      expect(
        (await cache.load('shop', 'issued-legacy'))?['document_number'],
        isNull,
      );
      expect((await cache.load('shop', 'valid'))?['document_number'], 'E-1997');
      expect(
        await LocalEstimateNumber.repair(
          db,
          'shop',
          'issued-legacy',
          confirmed: true,
        ),
        'E-2000',
      );
      final audit = await db
          .customSelect(
            "SELECT original_number,owner_confirmed FROM local_estimate_number_audit_v2 WHERE estimate_id='issued-legacy'",
          )
          .getSingle();
      expect(audit.data, {
        'original_number': 'EST-OLD-ISSUED',
        'owner_confirmed': 1,
      });
      final drafts = OfflineDocumentDraftService(database: db);
      await expectLater(
        db.transaction(() async {
          await drafts.createStandaloneEstimate(
            'shop',
            customerId: 'customer',
            customerName: 'Test',
          );
          throw StateError('Simulate failed save');
        }),
        throwsStateError,
      );
      final first = await drafts.createStandaloneEstimate(
        'shop',
        customerId: 'customer',
        customerName: 'Test',
      );
      expect(await LocalEstimateNumber.stored(db, 'shop', first), 'E-2001');
      await db.customStatement('DELETE FROM local_documents WHERE id=?', [
        first,
      ]);
      final second = await drafts.createStandaloneEstimate(
        'shop',
        customerId: 'customer',
        customerName: 'Test',
      );
      expect(await LocalEstimateNumber.stored(db, 'shop', second), 'E-2002');
    },
  );
}
