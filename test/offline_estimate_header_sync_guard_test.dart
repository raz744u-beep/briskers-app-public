import 'dart:io';

import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_repair_groups.dart';
import 'package:briskers_app/services/offline_document_draft_service.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EstimateHeaderApi extends BriskersApi {
  String? publicNumber;
  String? claimNumber;
  String? authorizationNumber;
  num? vehicleMileage;
  bool dropClaimAcknowledgment = false;
  bool changeQuoteDuringClaimConfirmation = false;
  int revision = 2;
  int creates = 0;
  int claimUpdates = 0;
  int mileageUpdates = 0;
  String? submittedDate;
  String remoteLineName = 'Inspection';
  String? remoteMemo;

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
    creates++;
    submittedDate = documentDate;
    this.publicNumber = publicNumber;
    expect(lines, hasLength(1));
    return operationId;
  }

  @override
  Future<Map<String, dynamic>> documentDetail(
    String businessId,
    String documentId,
  ) async => {
    'id': documentId,
    'kind': 'estimate',
    'document_number': publicNumber,
    'job_id': null,
    'status': 'draft',
    'origin': 'native',
    'customer_id': 'customer-id',
    'customer_name': 'Fixture',
    'document_date': '2026-11-20',
    'claim_number': claimNumber,
    'authorization_number': authorizationNumber,
    'odometer_in': vehicleMileage,
    'row_version': revision,
    'net_amount': 100,
    'tax_amount': 0,
    'total_amount': 100,
    'memo': remoteMemo,
    'lines': [
      {
        'id': 'remote-line-1',
        'name': remoteLineName,
        'line_kind': 'part',
        'quantity': 1,
        'unit_price': 100,
        'tax_rate': 0,
      }
    ],
  };

  @override
  Future<void> updateDocumentClaimInfo(
    String businessId,
    String documentId, {
    required int expectedVersion,
    String? claimNumber,
    String? authorizationNumber,
  }) async {
    expect(expectedVersion, revision);
    claimUpdates++;
    this.claimNumber = claimNumber;
    this.authorizationNumber = authorizationNumber;
    revision++;
    if (changeQuoteDuringClaimConfirmation) {
      // Simulate a separate device updating the quote during RPC confirmation.
      remoteLineName = 'Other device updated this repair';
      revision++;
    }
    if (dropClaimAcknowledgment) throw StateError('Simulated lost RPC acknowledgment');
  }

  @override
  Future<void> updateDocumentMileage(
    String businessId,
    String documentId, {
    num? odometer,
  }) async {
    mileageUpdates++;
    throw StateError('Shared vehicle mileage must never be modified by estimate sync');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late BriskersLocalDatabase db;
  late LocalDocumentDetailCache cache;
  late _EstimateHeaderApi api;
  late OfflineDocumentDraftService drafts;
  final mode = BriskersConnectionModeController.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('estimate-sync-guard-');
    await mode.setMode(BriskersConnectionMode.offline);
    db = BriskersLocalDatabase(NativeDatabase(File('${directory.path}/shop.sqlite')));
    await LocalDocumentDetailCache.initialize(db);
    cache = LocalDocumentDetailCache(database: db);
    api = _EstimateHeaderApi();
    drafts = OfflineDocumentDraftService(database: db, cache: cache, api: api);
  });

  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
    LocalDocumentDetailCache.sqliteWritesEnabled = false;
    await mode.setMode(BriskersConnectionMode.auto);
  });

  Future<String> create() async => drafts.createStandaloneEstimate(
    'shop',
    customerId: 'customer-id',
    customerName: 'Fixture',
    initialLines: [
      {'name': 'Inspection', 'line_kind': 'part', 'quantity': 1,
        'unit_price': 100, 'tax_rate': 0},
    ],
  );

  Future<Map<String, dynamic>> queue(String id) async {
    final row = await db.customSelect(
      "SELECT state,attempt_count,last_error,payload_json FROM sync_outbox "
      "WHERE business_id='shop' AND entity_id=?",
      variables: [Variable<String>(id)],
    ).getSingle();
    return row.data;
  }

  test('guarded Claim and Authorization persist before estimate outbox retires', () async {
    final id = await create();
    await drafts.updatePendingEstimateDetails(
      'shop', id, documentDate: DateTime(2026, 11, 20),
      customerId: 'customer-id', customerName: 'Fixture',
      claimNumber: 'CLAIM-001', authorizationNumber: 'AUTH-002',
    );
    await mode.setMode(BriskersConnectionMode.auto);
    await drafts.flush('shop');
    expect(api.claimUpdates, 1);
    expect(api.claimNumber, 'CLAIM-001');
    expect(api.authorizationNumber, 'AUTH-002');
    expect(api.mileageUpdates, 0);
    expect(
      await db.customSelect(
        "SELECT id FROM sync_outbox WHERE business_id='shop' AND entity_id=?",
        variables: [Variable<String>(id)],
      ).get(),
      isEmpty,
    );
    final synced = (await cache.load('shop', id))!;
    expect(synced['claim_number'], 'CLAIM-001');
    expect(synced['authorization_number'], 'AUTH-002');
    expect(synced['_server_document_id'], isNotNull);
    expect((synced['lines'] as List), hasLength(1));
  });

  test('stale server date cannot erase a queued estimate header on replay', () async {
    final id = await create();
    // Simulate a previously committed idempotent create whose authoritative
    // date still predates the header edit saved on this phone.
    await drafts.updatePendingEstimateDetails(
      'shop', id, documentDate: DateTime(2026, 11, 21),
      customerId: 'customer-id', customerName: 'Fixture',
      claimNumber: 'CLAIM-DATE',
    );
    await mode.setMode(BriskersConnectionMode.auto);
    await drafts.flush('shop');
    expect(api.submittedDate, '2026-11-21');
    expect((await queue(id))['state'], 'conflict');
    expect((await queue(id))['last_error']?.toString(), contains('date differs'));
    expect(api.claimUpdates, 0);
    expect(api.claimNumber, isNull);
    final saved = (await cache.load('shop', id))!;
    expect(saved['document_date'], '2026-11-21');
    expect(saved['claim_number'], 'CLAIM-DATE');
    expect(saved['sync_state'], 'conflict');
    expect(saved['_server_document_id'], isNull);
    await drafts.flush('shop');
    expect(api.creates, 1);
  });

  test('idempotent create cannot replace locally saved estimate lines with stale server items', () async {
    final id = await create();
    final store = LocalRepairGroups(database: db, cache: cache);
    final saved = (await cache.load('shop', id))!;
    final lineId = (saved['lines'] as List).single['id'] as String;
    await store.add('shop', id, name: 'Inspection work', description: '');
    final group = (await store.groups('shop', id, saved)).first;
    await store.move('shop', id, {lineId}, group.id);
    api.remoteLineName = 'Different server repair';
    await drafts.updatePendingEstimateDetails(
      'shop', id, documentDate: DateTime(2026, 11, 20),
      customerId: 'customer-id', customerName: 'Fixture',
      claimNumber: 'KEEP-LOCAL',
    );
    await mode.setMode(BriskersConnectionMode.auto);
    await drafts.flush('shop');
    final pending = await queue(id);
    expect(pending['state'], 'conflict');
    expect(pending['last_error']?.toString(), contains('items or notes'));
    final local = (await cache.load('shop', id))!;
    expect((local['lines'] as List).single['name'], 'Inspection');
    expect(local['claim_number'], 'KEEP-LOCAL');
    expect(local['_server_document_id'], isNull);
    expect(local['sync_state'], 'conflict');
    expect((await store.groups('shop', id, local)).first.lines.single['id'], lineId);
    expect(api.claimUpdates, 0);
    await drafts.flush('shop');
    expect(api.creates, 1);
  });

  test('idempotent create cannot silently replace an offline estimate memo', () async {
    final id = await drafts.createStandaloneEstimate(
      'shop',
      customerId: 'customer-id',
      customerName: 'Fixture',
      initialLines: [
        {'name': 'Inspection', 'line_kind': 'part', 'quantity': 1,
          'unit_price': 100, 'tax_rate': 0},
      ],
      initialMemo: 'Owner saved note',
    );
    await mode.setMode(BriskersConnectionMode.auto);
    await drafts.flush('shop');
    expect((await queue(id))['state'], 'conflict');
    final local = (await cache.load('shop', id))!;
    expect(local['memo'], 'Owner saved note');
    expect(local['_server_document_id'], isNull);
    expect(api.creates, 1);
  });

  test('concurrent remote quote edit during claim confirmation preserves local estimate', () async {
    final id = await create();
    api.changeQuoteDuringClaimConfirmation = true;
    await drafts.updatePendingEstimateDetails(
      'shop', id, documentDate: DateTime(2026, 11, 20),
      customerId: 'customer-id', customerName: 'Fixture',
      claimNumber: 'CLAIM-CONCURRENT',
    );
    await mode.setMode(BriskersConnectionMode.auto);
    await drafts.flush('shop');

    // The claim RPC committed, but the final server quote changed before the
    // confirming read. Its independent edit must not replace our local lines.
    expect(api.claimUpdates, 1);
    expect(api.claimNumber, 'CLAIM-CONCURRENT');
    expect(api.remoteLineName, 'Other device updated this repair');
    final pending = await queue(id);
    expect(pending['state'], 'conflict');
    expect(pending['last_error']?.toString(), contains('changed during warranty confirmation'));
    final local = (await cache.load('shop', id))!;
    expect((local['lines'] as List).single['name'], 'Inspection');
    expect(local['claim_number'], 'CLAIM-CONCURRENT');
    expect(local['sync_state'], 'conflict');
    expect(local['_server_document_id'], isNull);
    await drafts.flush('shop');
    expect(api.creates, 1);
    expect(api.claimUpdates, 1);
  });

  test('same revision-guarded receipt survives a lost claim RPC acknowledgment', () async {
    final id = await create();
    api.dropClaimAcknowledgment = true;
    await drafts.updatePendingEstimateDetails(
      'shop', id, documentDate: DateTime(2026, 11, 20),
      customerId: 'customer-id', customerName: 'Fixture',
      claimNumber: 'CLAIM-LOST', authorizationNumber: 'AUTH-LOST',
    );
    await mode.setMode(BriskersConnectionMode.auto);
    await drafts.flush('shop');
    expect(api.claimUpdates, 1);
    expect(api.claimNumber, 'CLAIM-LOST');
    expect(
      await db.customSelect(
        "SELECT id FROM sync_outbox WHERE business_id='shop' AND entity_id=?",
        variables: [Variable<String>(id)],
      ).get(),
      isEmpty,
    );
  });

  test('edited Mileage In never silently becomes shared vehicle odometer', () async {
    final id = await create();
    // Even a coincidentally equal current vehicle value is not a durable
    // estimate-specific snapshot. A later vehicle update can invalidate it.
    api.vehicleMileage = 12345;
    await drafts.updatePendingEstimateDetails(
      'shop', id, documentDate: DateTime(2026, 11, 20),
      customerId: 'customer-id', customerName: 'Fixture',
      mileage: '12345', claimNumber: 'CLAIM-003',
      authorizationNumber: 'AUTH-004',
    );
    await mode.setMode(BriskersConnectionMode.auto);
    await drafts.flush('shop');
    final pending = await queue(id);
    expect(pending['state'], 'conflict');
    expect(pending['last_error']?.toString(), contains('Mileage In'));
    // The document screen reads the local detail, not sync_outbox. The
    // conflict must survive reload and be visible without a second edit.
    final saved = (await cache.load('shop', id))!;
    expect(saved['sync_state'], 'conflict');
    expect(saved['_offline_estimate_sync_error']?.toString(),
        contains('Mileage In'));
    final savedLocalRow = await db.customSelect(
      "SELECT sync_state FROM local_documents WHERE business_id='shop' AND id=?",
      variables: [Variable<String>(id)],
    ).getSingle();
    expect(savedLocalRow.read<String>('sync_state'), 'conflict');
    expect(saved['odometer_in'], 12345);
    expect(saved['claim_number'], 'CLAIM-003');
    expect(saved['authorization_number'], 'AUTH-004');
    expect(saved['_server_document_id'], isNull);
    // The remote estimate may be created idempotently, but no part of a
    // mixed warranty/mileage header is applied until mileage can be stored.
    expect(api.claimUpdates, 0);
    expect(api.claimNumber, isNull);
    expect(api.authorizationNumber, isNull);
    expect(api.mileageUpdates, 0);
    expect(api.vehicleMileage, 12345);
    await drafts.flush('shop');
    expect(api.creates, 1);
    expect(api.mileageUpdates, 0);
  });

  test('newer nonempty remote claim is not overwritten by stale local header', () async {
    final id = await create();
    api.claimNumber = 'SERVER-CLAIM';
    await drafts.updatePendingEstimateDetails(
      'shop', id, documentDate: DateTime(2026, 11, 20),
      customerId: 'customer-id', customerName: 'Fixture',
      claimNumber: 'OFFLINE-CLAIM', authorizationNumber: 'AUTH',
    );
    await mode.setMode(BriskersConnectionMode.auto);
    await drafts.flush('shop');
    expect((await queue(id))['state'], 'conflict');
    expect(api.claimUpdates, 0);
    expect(api.claimNumber, 'SERVER-CLAIM');
    expect((await cache.load('shop', id))!['claim_number'], 'OFFLINE-CLAIM');
  });

  test('explicitly cleared mileage remains preserved for Owner review', () async {
    final id = await create();
    await drafts.updatePendingEstimateDetails(
      'shop', id, documentDate: DateTime(2026, 11, 20),
      customerId: 'customer-id', customerName: 'Fixture', mileage: '',
    );
    await mode.setMode(BriskersConnectionMode.auto);
    await drafts.flush('shop');
    expect((await queue(id))['state'], 'conflict');
    expect(api.mileageUpdates, 0);
    expect((await cache.load('shop', id))!['odometer_in'], isNull);
  });

  test('Owner can save conflicted estimate header locally without retry or remote writes', () async {
    final id = await create();
    await drafts.updatePendingEstimateDetails(
      'shop', id, documentDate: DateTime(2026, 11, 20),
      customerId: 'customer-id', customerName: 'Fixture',
      mileage: '12345', claimNumber: 'BEFORE',
    );
    await mode.setMode(BriskersConnectionMode.auto);
    await drafts.flush('shop');
    final before = await queue(id);
    expect(before['state'], 'conflict');
    expect(before['attempt_count'], 1);
    final originalPayload = before['payload_json'];

    // The regular editor is not an Owner conflict-resolution authorization.
    await expectLater(
      drafts.updatePendingEstimateDetails(
        'shop', id, documentDate: DateTime(2026, 11, 21),
        customerId: 'customer-id', customerName: 'Fixture',
        claimNumber: 'NOT-AUTHORIZED',
      ),
      throwsStateError,
    );
    await mode.setMode(BriskersConnectionMode.offline);
    await drafts.updatePendingEstimateDetails(
      'shop', id, documentDate: DateTime(2026, 11, 21),
      customerId: 'customer-id', customerName: 'Fixture',
      claimNumber: 'REVIEW-ONLY', authorizationNumber: 'AUTH-REVIEW',
      allowConflictedLocalReview: true,
    );
    final after = await queue(id);
    expect(after['state'], 'conflict');
    expect(after['attempt_count'], before['attempt_count']);
    expect(after['payload_json'], originalPayload);
    expect(after['last_error'], before['last_error']);
    final local = (await cache.load('shop', id))!;
    expect(local['document_date'], '2026-11-21');
    expect(local['claim_number'], 'REVIEW-ONLY');
    expect(local['authorization_number'], 'AUTH-REVIEW');
    expect(local['odometer_in'], 12345);
    expect(local['_offline_estimate_mileage_was_edited'], true);
    expect(local['sync_state'], 'conflict');
    expect(api.claimUpdates, 0);
    expect(api.mileageUpdates, 0);
    await mode.setMode(BriskersConnectionMode.auto);
    await drafts.flush('shop');
    expect(api.creates, 1);
    expect((await queue(id))['state'], 'conflict');
    expect((await cache.load('shop', id))!['claim_number'], 'REVIEW-ONLY');
  });

  test('attempted pending estimates remain locked even with Owner review flag', () async {
    final id = await create();
    await db.customStatement(
      "UPDATE sync_outbox SET attempt_count=1,last_attempt_at=123456 "
      "WHERE business_id='shop' AND entity_id=?",
      [id],
    );
    await expectLater(
      drafts.updatePendingEstimateDetails(
        'shop', id, documentDate: DateTime(2026, 11, 21),
        customerId: 'customer-id', customerName: 'Fixture',
        claimNumber: 'UNSAFE', allowConflictedLocalReview: true,
      ),
      throwsStateError,
    );
    final local = (await cache.load('shop', id))!;
    expect(local['claim_number'], isNull);
    expect((await queue(id))['state'], 'pending');
    expect((await queue(id))['attempt_count'], 1);
  });
}
