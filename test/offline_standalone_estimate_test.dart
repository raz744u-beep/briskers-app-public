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

class _StandaloneApi extends BriskersApi {
  final List<String> operationIds = [];
  var detailAttempts = 0;
  @override
  Future<String> syncOfflineStandaloneEstimate(
    String businessId, {
    required String customerId,
    String? vehicleId,
    required String operationId,
    required String documentDate,
    required List<Map<String, dynamic>> lines,
    String? memo,
  }) async {
    operationIds.add(operationId);
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
      'document_number': LocalEstimateNumber.forDocument(
        businessId,
        documentId,
      ),
      'job_id': null,
      'status': 'draft',
      'customer_id': 'customer-id',
      'customer_name': 'Test Customer',
      'document_date': '2026-10-10',
      'row_version': 2,
      'net_amount': 220,
      'tax_amount': 0,
      'total_amount': 220,
      'origin': 'native',
      'legacy_read_only': false,
      'lines': [
        {
          'id': 'server-line',
          'name': 'Labor',
          'quantity': 4.4,
          'unit_price': 50,
          'line_kind': 'labor',
        },
      ],
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
    final number = LocalEstimateNumber.forDocument('shop', localId);
    expect((await cache.load('shop', localId))?['document_number'], number);
    expect(
      DocumentPdfService.fileName((await cache.load('shop', localId))!),
      'Briskers-Estimate-$number.pdf',
    );
    expect((await cache.load('shop', localId))?['job_id'], isNull);
    final templates = await EmailDraftTemplates.load('shop');
    expect(
      templates.render(templates.subject, estimate: true, number: number),
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
      expect(
        LocalEstimateNumber.forDocument('shop', first),
        isNot(LocalEstimateNumber.forDocument('shop', second)),
      );
    },
  );
}
