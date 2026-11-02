import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_job_quarantine.dart';
import 'package:briskers_app/services/offline_document_draft_service.dart';
import 'package:briskers_app/services/offline_document_edit_service.dart';
import 'package:briskers_app/services/offline_estimate_invoice_service.dart';
import 'package:briskers_app/services/offline_financial_write_service.dart';
import 'package:briskers_app/services/offline_invoice_payment_ledger.dart';

const _business = 'quarantine-test-business';
const _job = 'revoked-job';
late LocalDocumentDetailCache _cache;

Map<String, dynamic> _detail(String id) => {
  'id': id,
  'job_id': _job,
  'kind': 'invoice',
  'status': 'issued',
  'row_version': 1,
  'total_amount': 10,
  'lines': <Map<String, dynamic>>[],
};

// A real local quick-invoice draft includes net, tax and service lines.
// Quarantine tests need an internally consistent source snapshot so the
// currency safety preflight can reach the intended late-receipt race.
Map<String, dynamic> _validQuickInvoiceDetail(String id) => {
  ..._detail(id),
  'net_amount': 10,
  'tax_amount': 0,
  'total_amount': 10,
  'lines': <Map<String, dynamic>>[
    {
      'name': 'Synthetic saved service',
      'line_kind': 'item',
      'quantity': 1,
      'unit_price': 10,
      'tax_rate': 0,
    },
  ],
};

class _ReplayApi extends BriskersApi {
  final mutations = <String>[];
  final reads = <String>[];
  Future<void> Function(String stage)? onMutation;
  Future<Map<String, dynamic>> Function(String id)? onRead;
  Future<void> Function()? onWarrantyRead;

  Future<void> _mutate(String stage) async {
    mutations.add(stage);
    await onMutation?.call(stage);
  }

  @override
  Future<Map<String, dynamic>> documentDetail(
    String businessId, String documentId,
  ) async {
    reads.add(documentId);
    if (onRead != null) return onRead!(documentId);
    return _detail(documentId);
  }

  @override
  Future<Map<String, dynamic>> documentWarrantyDetail(
    String businessId, String documentId,
  ) async {
    await onWarrantyRead?.call();
    return {};
  }

  @override
  Future<void> addDocumentLine(
    String businessId, String documentId, {
    required int expectedVersion,
    required String name,
    required num quantity,
    required num unitPrice,
    num taxRate = 0,
    String? description,
    String? itemId,
    String lineKind = 'item',
  }) => _mutate('add-line');

  @override
  Future<String> syncOfflineQuickInvoice(
    String businessId, {
    required String customerId,
    String? vehicleId,
    required String operationId,
    required String documentDate,
    required List<Map<String, dynamic>> lines,
    String? memo,
  }) async {
    await _mutate('create-invoice');
    return 'server-invoice-ack';
  }

  @override
  Future<String> convertEstimate(String businessId, String estimateId) async {
    await _mutate('convert');
    return 'server-invoice-ack';
  }

  @override
  Future<List<Map<String, dynamic>>> warrantyCompanies(
    String businessId, {bool includeInactive = false}
  ) async => [];

  @override
  Future<String> createWarrantyCompany(
    String businessId, {
    required String name,
    String? claimsPhone,
    String? submissionEmail,
  }) async {
    await _mutate('create-warranty-company');
    return 'company-ack';
  }

  @override
  Future<Map<String, dynamic>> updateDocumentWarranty(
    String businessId, String documentId, {
    required int expectedVersion,
    required bool extendedWarranty,
    String? warrantyCompanyId,
    String? claimNumber,
    String? authorizationNumber,
    num? approvedAmount,
    num surchargeRate = 0.03,
  }) async {
    await _mutate('update-warranty');
    return {};
  }

  @override
  Future<Map<String, dynamic>> addEstimateToExistingInvoice(
    String businessId, {
    required String estimateId,
    required String invoiceId,
    required String operationId,
  }) async {
    await _mutate('merge-estimate');
    return {'invoice_id': invoiceId};
  }

  @override
  Future<String> addPendingInvoicePaymentOnce(
    String businessId, String invoiceId, {
    required num amount,
    required String methodId,
    required String operationId,
  }) async {
    await _mutate('payment');
    return 'payment-ack';
  }

  @override
  Future<String> addPendingInvoicePaymentOnceV2(
    String businessId, String invoiceId, {
    required num amount,
    required String methodId,
    required String operationId,
    required String paymentDate,
    List<dynamic> localEditHistory = const [],
  }) async {
    // New local receipts replay through v2 with original business date.
    expect(DateTime.tryParse(paymentDate), isNotNull);
    await _mutate('payment');
    return 'payment-ack';
  }

  @override
  Future<Map<String, dynamic>> syncCreateManualTransaction(
    String businessId, {
    required String operationId,
    required String direction,
    required String accountId,
    required String categoryId,
    required num amount,
    required DateTime date,
    String? jobId,
    String? documentId,
    String? counterpartyId,
    String? counterpartyName,
    String? remarks,
  }) async {
    await _mutate('create-transaction');
    return {'transaction_id': 'transaction-ack'};
  }

  @override
  Future<void> updateManualTransaction(
    String businessId, String transactionId, {
    required String direction,
    required String accountId,
    required String categoryId,
    required num amount,
    required DateTime date,
    String? jobId,
    String? documentId,
    String? counterpartyId,
    String? counterpartyName,
    String? remarks,
  }) => _mutate('update-transaction');

  @override
  Future<Map<String, dynamic>> syncRegisterExpensePhoto(
    String businessId, String transactionId, {
    required String operationId,
    required String filename,
    required String mimeType,
  }) async {
    await _mutate('register-photo');
    return {
      'bucket': 'test-bucket',
      'key': 'test-key',
      'attachment_id': 'attachment-ack',
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
  }) => _mutate('upload-photo');
}

Future<int> _queue(
  BriskersLocalDatabase db,
  String type,
  String id,
  Map<String, dynamic> payload, {
  String operation = 'test-operation',
}) async {
  await db.customStatement('''INSERT INTO sync_outbox(
    business_id,entity_type,entity_id,operation,payload_json,state,attempt_count
  ) VALUES (?,?,?,?,?,'pending',0)''',
    [_business, type, id, operation, jsonEncode(payload)]);
  return (await db.customSelect('SELECT last_insert_rowid() AS id')
      .getSingle()).read<int>('id');
}

Future<void> _seedDocument(BriskersLocalDatabase db, String id) async {
  await db.customStatement('''INSERT INTO local_documents(
    id,business_id,job_id,kind,status,total,sync_state
  ) VALUES (?,?,?,'invoice','issued',10,'pending')''', [id, _business, _job]);
  await _cache.save(_business, id, _detail(id));
}

Future<void> _revokeAndClassify(BriskersLocalDatabase db) async {
  await LocalJobQuarantine.quarantineJobs(db, _business, [_job]);
  await LocalJobQuarantine.classifyJobs(
    db, _business, [_job], cleanupJobIds: <String>{},
  );
  // The broad pause is resolved; the original archived queue ID stays blocked.
  await LocalJobQuarantine.assertReplayAllowed(db, _business);
}

Future<List<dynamic>> _receipts(BriskersLocalDatabase db, int id) async =>
    (await db.customSelect(
      'SELECT response_json FROM local_job_recovery_receipts WHERE outbox_id=?',
      variables: [Variable<int>(id)],
    ).get()).map((row) => jsonDecode(row.read<String>('response_json'))).toList();

Future<Map<String, dynamic>> _archivedPayload(
  BriskersLocalDatabase db, int id,
) async {
  final row = await db.customSelect('''SELECT row_json
    FROM local_job_recovery_rows WHERE table_name='sync_outbox'
    AND original_key=?''', variables: [Variable<String>('$id')]).getSingle();
  final archived = jsonDecode(row.read<String>('row_json')) as Map;
  return Map<String, dynamic>.from(jsonDecode(archived['payload_json'] as String) as Map);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BriskersLocalDatabase db;
  late _ReplayApi api;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = BriskersLocalDatabase(NativeDatabase.memory());
    _cache = LocalDocumentDetailCache(database: db);
    api = _ReplayApi();
  });
  tearDown(() async => db.close());

  for (final type in [
    'document_edit',
    'document_draft_create',
    'invoice_payment_received',
    'estimate_add_to_invoice',
    'financial_create',
    'financial_update',
    'financial_photo',
  ]) {
    test('$type makes no network request during unresolved quarantine', () async {
      final directory = await Directory.systemTemp.createTemp('quarantine-paused-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/receipt.jpg');
      await file.writeAsBytes([1, 2, 3]);
      await _cache.save(_business, 'unrelated-invoice', _detail('unrelated-invoice'));
      final id = await _queue(db, type, 'unrelated-invoice', {
        'amount_cents': 1000,
        'method_id': 'cash',
        'operation_id': 'operation-original',
        'kind': 'invoice', 'customer_id': 'customer-test',
        'document_date': '2026-10-13',
        'estimate_id': 'unrelated-estimate', 'invoice_id': 'unrelated-invoice',
        'local_transaction_id': 'local-transaction-test',
        'transaction_id': 'transaction-test', 'direction': 'expense',
        'account_id': 'account-test', 'category_id': 'category-test',
        'amount': 10, 'date': '2026-10-13',
        'name': 'Saved line', 'quantity': 1, 'unit_price': 10,
        'filename': 'receipt.jpg', 'mime_type': 'image/jpeg',
        'local_file_path': file.path,
      }, operation: 'add_line');
      if (type == 'financial_photo') {
        // A photo carries only its transaction ID. Prove this fixture is
        // unrelated; unknown receipt relationships are correctly archived.
        await db.customStatement('''INSERT INTO local_financial_cache(
          business_id,cache_key,payload_json
        ) VALUES (?,?,?)''', [_business, 'transaction_detail_transaction-test',
          jsonEncode({'id': 'transaction-test', 'job_id': 'unrelated-job'})]);
      }
      await LocalJobQuarantine.quarantineJobs(db, _business, [_job]);
      switch (type) {
        case 'document_edit':
          await OfflineDocumentEditService(api: api, database: db).flush(_business);
          break;
        case 'document_draft_create':
          await OfflineDocumentDraftService(api: api, database: db).flush(_business);
          break;
        case 'invoice_payment_received':
          await OfflineInvoicePaymentLedger(api: api, database: db).flush(_business);
          break;
        case 'estimate_add_to_invoice':
          await OfflineEstimateInvoiceService(api: api, database: db).flush(_business);
          break;
        default:
          await OfflineFinancialWriteService(api: api, database: db).flush(_business);
      }
      expect(api.reads, isEmpty);
      expect(api.mutations, isEmpty);
      final row = await db.customSelect('SELECT state,payload_json FROM sync_outbox WHERE id=?',
        variables: [Variable<int>(id)]).getSingle();
      expect(row.read<String>('state'), 'pending');
      expect(jsonDecode(row.read<String>('payload_json')), isNot(contains('replay_attempted')));
    });
  }

  test('preloaded document edit cannot replay after revocation is classified', () async {
    await _seedDocument(db, 'invoice-1');
    final id = await _queue(db, 'document_edit', 'invoice-1', {
      'name': 'Original line', 'quantity': 1, 'unit_price': 10,
    }, operation: 'add_line');
    api.onRead = (documentId) async {
      await _revokeAndClassify(db);
      return _detail(documentId);
    };
    await OfflineDocumentEditService(api: api, database: db).flush(_business);
    expect(api.reads, ['invoice-1']);
    expect(api.mutations, isEmpty);
    expect((await _archivedPayload(db, id))['name'], 'Original line');
    await expectLater(
      LocalJobQuarantine.assertReplayAllowed(db, _business, outboxId: id),
      throwsA(isA<LocalJobQuarantineException>()),
    );
  });

  test('late payment acknowledgement is archived without refresh or replay', () async {
    await _seedDocument(db, 'invoice-1');
    final ledger = OfflineInvoicePaymentLedger(api: api, database: db);
    final operationId = await ledger.recordReceivedPayment(
      _business, 'invoice-1', amount: 10, remainingBeforePaymentCents: 1000,
      methodId: 'cash', methodName: 'Cash',
    );
    final id = (await db.customSelect('SELECT id FROM sync_outbox').getSingle()).read<int>('id');
    var cacheCalls = 0;
    api.onMutation = (_) => _revokeAndClassify(db);
    await ledger.flush(_business, cacheInvoice: (_, _, _) async { cacheCalls++; });
    expect(api.mutations, ['payment']);
    expect(api.reads, isEmpty);
    expect(cacheCalls, 0);
    expect(await _receipts(db, id), contains('payment-ack'));
    final archived = await _archivedPayload(db, id);
    expect(archived['operation_id'], operationId);
    expect(archived['amount_cents'], 1000);
    expect(archived['replay_attempted'], isTrue);
    await ledger.flush(_business);
    expect(api.mutations, ['payment']);
  });

  test('final document refresh cannot revive cache after its queue row retired', () async {
    await _seedDocument(db, 'invoice-1');
    await _queue(db, 'document_edit', 'invoice-1', {
      'name': 'Original line', 'quantity': 1, 'unit_price': 10,
    }, operation: 'add_line');
    api.onRead = (id) async => {..._detail(id), 'late_server_marker': true};
    api.onWarrantyRead = () => _revokeAndClassify(db);
    await OfflineDocumentEditService(api: api, database: db).flush(_business);
    expect(api.mutations, ['add-line']);
    expect((await _cache.load(_business, 'invoice-1'))?['late_server_marker'], isNull);
    expect(await db.customSelect('SELECT id FROM sync_outbox').get(), isEmpty);
  });

  test('late estimate merge acknowledgement is retained without cache refresh', () async {
    await _seedDocument(db, 'estimate-1');
    await _seedDocument(db, 'invoice-1');
    final id = await _queue(db, 'estimate_add_to_invoice', 'estimate-1', {
      'estimate_id': 'estimate-1', 'invoice_id': 'invoice-1',
      'operation_id': 'original-merge-operation',
    });
    api.onMutation = (_) => _revokeAndClassify(db);
    await OfflineEstimateInvoiceService(api: api, database: db).flush(_business);
    expect(api.mutations, ['merge-estimate']);
    expect(api.reads, isEmpty);
    expect(await _receipts(db, id), contains(containsPair('invoice_id', 'invoice-1')));
    expect((await _archivedPayload(db, id))['operation_id'], 'original-merge-operation');
  });

  test('late manual transaction identity stays in recovery', () async {
    final id = await _queue(db, 'financial_create', 'local-transaction-test', {
      'local_transaction_id': 'local-transaction-test', 'job_id': _job,
      'operation_id': 'original-expense-operation', 'direction': 'expense',
      'account_id': 'account-test', 'category_id': 'category-test',
      'amount': 10, 'date': '2026-10-13',
    });
    api.onMutation = (_) => _revokeAndClassify(db);
    await OfflineFinancialWriteService(api: api, database: db).flush(_business);
    expect(api.mutations, ['create-transaction']);
    expect(await _receipts(db, id), contains(containsPair('transaction_id', 'transaction-ack')));
    expect((await _archivedPayload(db, id))['operation_id'], 'original-expense-operation');
  });

  test('late quick invoice ID never replaces the archived local draft', () async {
    const localId = 'local-invoice-test';
    await _seedDocument(db, localId);
    await _cache.save(_business, localId, _validQuickInvoiceDetail(localId));
    final id = await _queue(db, 'document_draft_create', localId, {
      'kind': 'invoice', 'customer_id': 'customer-test',
      'operation_id': 'original-invoice-operation', 'document_date': '2026-10-13',
    });
    api.onMutation = (_) => _revokeAndClassify(db);
    await OfflineDocumentDraftService(api: api, database: db).flush(_business);
    expect(api.mutations, ['create-invoice']);
    expect(api.reads, isEmpty);
    expect(await _receipts(db, id), contains('server-invoice-ack'));
    expect(await _cache.load(_business, 'server-invoice-ack'), isNull);
    expect((await _cache.load(_business, localId))?['_server_document_id'], isNull);
  });

  test('converted invoice line reconciliation rechecks its original queue ID', () async {
    const localId = 'local-invoice-conversion';
    await _seedDocument(db, localId);
    await _cache.save(_business, localId, {
      ..._detail(localId),
      'lines': [{'name': 'Saved line', 'quantity': 1, 'unit_price': 10}],
    });
    await _queue(db, 'document_draft_create', localId, {
      'kind': 'convert_invoice', 'estimate_id': 'estimate-1',
    });
    api.onRead = (id) async {
      if (id == 'estimate-1') {
        return {..._detail(id), 'converted': true, 'converted_invoice_id': 'invoice-1'};
      }
      await _revokeAndClassify(db);
      return _detail(id);
    };
    await OfflineDocumentDraftService(api: api, database: db).flush(_business);
    expect(api.reads, ['estimate-1', 'invoice-1']);
    expect(api.mutations, isEmpty);
  });

  test('quarantine after warranty company creation stops invoice warranty write', () async {
    const localId = 'local-invoice-warranty';
    await _seedDocument(db, localId);
    await _cache.save(_business, localId, {
      ..._validQuickInvoiceDetail(localId),
      'offline_warranty_detail': {
        'extended_warranty': true, 'warranty_company_name': 'Test warranty',
      },
    });
    final id = await _queue(db, 'document_draft_create', localId, {
      'kind': 'invoice', 'customer_id': 'customer-test',
      'operation_id': 'warranty-operation', 'document_date': '2026-10-13',
    });
    api.onMutation = (stage) async {
      if (stage == 'create-warranty-company') await _revokeAndClassify(db);
    };
    await OfflineDocumentDraftService(api: api, database: db).flush(_business);
    expect(api.mutations, ['create-invoice', 'create-warranty-company']);
    expect(await _receipts(db, id), contains('company-ack'));
    expect(await _cache.load(_business, 'server-invoice-ack'), isNull);
  });

  test('late expense registration preserves original bytes and prevents upload', () async {
    final directory = await Directory.systemTemp.createTemp('quarantine-receipt-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/original.jpg');
    final bytes = [1, 3, 5, 7];
    await file.writeAsBytes(bytes);
    final id = await _queue(db, 'financial_photo', 'transaction-1', {
      'transaction_id': 'transaction-1', 'job_id': _job,
      'operation_id': 'photo-operation', 'filename': 'original.jpg',
      'mime_type': 'image/jpeg', 'local_file_path': file.path,
    });
    api.onMutation = (_) => _revokeAndClassify(db);
    await OfflineFinancialWriteService(api: api, database: db).flush(_business);
    expect(api.mutations, ['register-photo']);
    expect(await file.readAsBytes(), bytes);
    expect((await _archivedPayload(db, id))['local_file_path'], file.path);
    expect(await _receipts(db, id), contains(containsPair('attachment_id', 'attachment-ack')));
  });

  test('payment verification after quarantine cannot apply late local cache acknowledgement', () async {
    await _seedDocument(db, 'invoice-1');
    final ledger = OfflineInvoicePaymentLedger(api: api, database: db);
    await ledger.recordReceivedPayment(
      _business, 'invoice-1', amount: 10, remainingBeforePaymentCents: 1000,
      methodId: 'cash', methodName: 'Cash',
    );
    var cacheCalls = 0;
    api.onRead = (id) async {
      await _revokeAndClassify(db);
      return {..._detail(id), 'pending_payment': 10,
        'payments': [{'id': 'payment-ack', 'amount': 10, 'state': 'pending'}]};
    };
    await ledger.flush(_business, cacheInvoice: (_, _, _) async { cacheCalls++; });
    expect(api.mutations, ['payment']);
    expect(cacheCalls, 0);
    final rows = await db.customSelect('SELECT id FROM sync_outbox').get();
    expect(rows, isEmpty);
  });
}

