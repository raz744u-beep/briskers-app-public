import 'dart:convert';
import 'dart:io';

import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/offline_document_draft_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EstimateHeaderApi extends BriskersApi {
  String? publicNumber;
  String? claimNumber;
  String? authorizationNumber;
  num? vehicleMileage;
  bool dropClaimAcknowledgment = false;
  int revision = 2;
  int creates = 0;
  int claimUpdates = 0;
  int mileageUpdates = 0;

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
    'lines': [
      {
        'id': 'remote-line-1',
        'name': 'Inspection',
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
    final saved = (await cache.load('shop', id))!;
    expect(saved['odometer_in'], 12345);
    expect(saved['claim_number'], 'CLAIM-003');
    expect(saved['authorization_number'], 'AUTH-004');
    expect(saved['_server_document_id'], isNull);
    expect(api.claimUpdates, 1);
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
}
