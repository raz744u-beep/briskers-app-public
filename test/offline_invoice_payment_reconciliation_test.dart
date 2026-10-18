import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/offline_invoice_payment_ledger.dart';

Map<String, dynamic> _receipt(String operationId, {int cents = 50000}) => {
  'operation_id': operationId,
  'invoice_id': 'invoice-test',
  'amount_cents': cents,
  'method_id': 'configured-method',
  'method_name': 'Zelle',
  'received_at': '2026-10-12T01:02:03.000Z',
};

Map<String, dynamic> _detail({
  num paid = 0,
  num pending = 0,
  List<Map<String, dynamic>> payments = const [],
}) => {
  'id': 'invoice-test',
  'kind': 'invoice',
  'total_amount': 500,
  'paid_amount': paid,
  'pending_payment': pending,
  'payments': payments,
};

Future<String> _record(
  OfflineInvoicePaymentLedger ledger, {
  String business = 'shop-test',
  String invoice = 'invoice-test',
  num amount = 500,
  int remaining = 50000,
  Iterable<String>? expected,
}) => ledger.recordReceivedPayment(
  business,
  invoice,
  amount: amount,
  remainingBeforePaymentCents: remaining,
  methodId: 'configured-method',
  methodName: ' Zelle ',
  expectedQueuedOperationIds: expected,
);

class _UnavailableIdempotentApi extends BriskersApi {
  final operations = <String>[];
  var legacyCalls = 0;

  @override
  Future<String> addPendingInvoicePaymentOnce(
    String businessId,
    String invoiceId, {
    required num amount,
    required String methodId,
    required String operationId,
  }) async {
    operations.add(operationId);
    throw StateError('Idempotent endpoint unavailable');
  }

  @override
  Future<String> addPendingInvoicePaymentOnceV2(
    String businessId,
    String invoiceId, {
    required num amount,
    required String methodId,
    required String operationId,
    required String paymentDate,
    List<dynamic> localEditHistory = const [],
  }) async {
    operations.add(operationId);
    expect(DateTime.tryParse(paymentDate), isNotNull);
    throw StateError('Date-aware idempotent endpoint unavailable');
  }

  @override
  Future<String> addPendingInvoicePayment(
    String businessId,
    String invoiceId, {
    required num amount,
    required String methodId,
  }) async {
    legacyCalls++;
    throw StateError('Non-idempotent endpoint must never be used');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Invoice payment projection', () {
    test('overlays exact cents without mutating the authoritative detail', () {
      final server = _detail(
        paid: 100,
        pending: 150,
        payments: [{'id': 'server-payment', 'amount': 150, 'state': 'pending'}],
      );
      final receipt = _receipt('operation-1', cents: 10000);
      final projected = OfflineInvoicePaymentLedger.projectPendingPayments(
        server, [receipt],
      );
      expect(projected['pending_payment'], 250);
      expect(projected['paid_amount'], 100);
      expect(projected['_local_pending_payment'], isTrue);
      expect(projected['_local_pending_payment_amount'], 100);
      expect(projected['_local_queued_payment_operation_ids'], ['operation-1']);
      final payments = projected['payments'] as List;
      expect(payments, hasLength(2));
      expect(payments.last, containsPair('pending_sync', true));
      expect(payments.last, containsPair('state', 'pending'));
      expect(payments.last, containsPair('entered_at', receipt['received_at']));
      expect(payments.last, containsPair('payment_method_id', 'configured-method'));
      expect(payments.last, containsPair('payment_method_name', 'Zelle'));
      expect(server['pending_payment'], 150);
      expect(server['payments'], hasLength(1));
      expect(server.containsKey('_local_pending_payment'), isFalse);
      (payments.first as Map)['amount'] = 999;
      expect((server['payments'] as List).first['amount'], 150);
      expect(receipt.containsKey('pending_sync'), isFalse);
    });

    test('repeated projections and duplicate queue rows add each UUID once', () {
      final receipt = _receipt('operation-1', cents: 30);
      final first = OfflineInvoicePaymentLedger.projectPendingPayments(
        _detail(pending: 0.2), [receipt, receipt],
      );
      final second = OfflineInvoicePaymentLedger.projectPendingPayments(
        first, [receipt],
      );
      expect(first['pending_payment'], 0.5);
      expect(second, first);
      expect(second['payments'], hasLength(1));
      final retired = OfflineInvoicePaymentLedger.projectPendingPayments(
        second, const [],
      );
      expect(retired['pending_payment'], 0.2);
      expect(retired['payments'], isEmpty);
      expect(retired['_local_pending_payment'], isFalse);
      expect(retired['_local_pending_payment_amount'], 0);
    });

    for (final identity in ['operation_id', 'client_operation_id', 'server_payment_id']) {
      test('deduplicates an acknowledged $identity in fresh server detail', () {
        final receipt = _receipt('operation-1');
        final payment = <String, dynamic>{
          'id': 'server-payment', 'amount': 500, 'state': 'pending',
        };
        if (identity == 'server_payment_id') {
          receipt[identity] = 'server-payment';
        } else {
          payment[identity] = 'operation-1';
        }
        final projected = OfflineInvoicePaymentLedger.projectPendingPayments(
          _detail(pending: 500, payments: [payment]), [receipt],
        );
        expect(projected['pending_payment'], 500);
        expect(projected['payments'], hasLength(1));
        expect(projected['_local_pending_payment'], isFalse);
        // Retained, already-visible queue rows still guard a payment dialog.
        expect(projected['_local_queued_payment_operation_ids'], ['operation-1']);
        final finalized = OfflineInvoicePaymentLedger.projectPendingPayments(
          _detail(paid: 500, payments: [{...payment, 'state': 'finalized'}]),
          [receipt],
        );
        expect(finalized['paid_amount'], 500);
        expect(finalized['pending_payment'], 0);
        expect(finalized['payments'], hasLength(1));
      });
    }

    test('does not acknowledge by amount or let a local receipt acknowledge itself', () {
      final receipt = _receipt('operation-1', cents: 10000);
      final projected = OfflineInvoicePaymentLedger.projectPendingPayments(
        _detail(pending: 100, payments: [{'id': 'unrelated', 'amount': 100}]),
        [receipt],
      );
      expect(projected['pending_payment'], 200);
      expect(projected['payments'], hasLength(2));
      expect(OfflineInvoicePaymentLedger.serverAcknowledgesPayment(
        projected, 'operation-1', operationId: 'operation-1',
      ), isFalse);
      expect(OfflineInvoicePaymentLedger.serverAcknowledgesPayment(
        projected, 'unrelated',
      ), isTrue);
    });

    for (final hasServerId in [false, true]) {
      test('unmatched attempted receipt requires reconciliation without double counting: $hasServerId', () {
        final receipt = {
          ..._receipt('operation-1'),
          'replay_attempted': true,
          if (hasServerId) 'server_payment_id': 'old-pending-payment',
        };
        final server = _detail(paid: 500, payments: [{
          'id': 'unrelated-posted-payment', 'amount': 500, 'state': 'finalized',
        }]);
        final projected = OfflineInvoicePaymentLedger.projectPendingPayments(server, [receipt]);
        expect(projected['paid_amount'], 500);
        expect(projected['pending_payment'], 0);
        expect(projected['_local_pending_payment_amount'], 500);
        expect(projected['_payment_reconciliation_required'], isTrue);
        final payments = projected['payments'] as List;
        expect(payments, hasLength(2));
        expect(payments.last, containsPair('amount', 500));
        expect(payments.last, containsPair('pending_sync', true));
        expect(payments.last, containsPair('reconciliation_required', true));
        expect(payments.last, containsPair('_local_projected_payment_amount', 0));
        expect(OfflineInvoicePaymentLedger.projectPendingPayments(projected, [receipt]), projected);
        expect(OfflineInvoicePaymentLedger.serverAcknowledgesPayment(
          server, 'old-pending-payment', operationId: 'operation-1'), isFalse);
        expect(server['payments'], hasLength(1));
      });
    }

    test('amounts that round to zero cannot create a durable zero receipt', () {
      expect(() => OfflineInvoicePaymentLedger.cents(0.001), throwsArgumentError);
      expect(() => OfflineInvoicePaymentLedger.cents(double.nan), throwsArgumentError);
    });
  });

  group('Durable payment capture and replay', () {
    late BriskersLocalDatabase db;
    late OfflineInvoicePaymentLedger ledger;

    setUp(() {
      db = BriskersLocalDatabase(NativeDatabase.memory());
      ledger = OfflineInvoicePaymentLedger(database: db);
    });
    tearDown(() async => db.close());

    test('local capture validates balance and stores the configured method and UUID', () async {
      final operationId = await _record(ledger, amount: 125, expected: const []);
      expect(operationId, matches(RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      )));
      final pending = await ledger.pendingForInvoice('shop-test', 'invoice-test');
      expect(pending, hasLength(1));
      expect(pending.single['operation_id'], operationId);
      expect(pending.single['amount_cents'], 12500);
      expect(pending.single['method_id'], 'configured-method');
      expect(pending.single['method_name'], 'Zelle');
      expect(DateTime.tryParse(pending.single['received_at'].toString()), isNotNull);
      await expectLater(_record(ledger, amount: 376, remaining: 37500), throwsStateError);
      expect(await ledger.pendingForInvoice('shop-test', 'invoice-test'), pending);
      expect(await ledger.pendingForInvoice('another-shop', 'invoice-test'), isEmpty);
    });

    test('transaction rejects a stale concurrent capture without adding a second receipt', () async {
      final attempts = await Future.wait([
        _record(ledger, amount: 400, expected: const []).then<Object>(
          (operation) => operation, onError: (Object error) => error,
        ),
        _record(OfflineInvoicePaymentLedger(database: db), amount: 400, expected: const [])
            .then<Object>((operation) => operation, onError: (Object error) => error),
      ]);
      expect(attempts.whereType<String>(), hasLength(1));
      expect(attempts.whereType<StateError>(), hasLength(1));
      final pending = await ledger.pendingForInvoice('shop-test', 'invoice-test');
      expect(pending, hasLength(1));
      // A freshly displayed remaining balance and queue snapshot permit a
      // second partial receipt, instead of rejecting all multiple payments.
      await _record(ledger, amount: 100, remaining: 10000,
        expected: [pending.single['operation_id'].toString()]);
      expect(await ledger.pendingForInvoice('shop-test', 'invoice-test'), hasLength(2));
    });

    test('a failed outbox insert rolls back and never reports successful capture', () async {
      await db.customStatement('''
        CREATE TEMP TRIGGER fail_payment_capture BEFORE INSERT ON sync_outbox
        WHEN NEW.entity_type = 'invoice_payment_received'
        BEGIN
          SELECT RAISE(ABORT, 'Simulated payment storage failure');
        END
      ''');
      var reportedSuccess = false;
      await expectLater(
        _record(ledger, expected: const []).then((_) => reportedSuccess = true),
        throwsA(predicate<Object>((error) =>
          error.toString().contains('Simulated payment storage failure'))),
      );
      expect(reportedSuccess, isFalse);
      expect(await ledger.pendingForInvoice('shop-test', 'invoice-test'), isEmpty);
      // A failed transaction must not poison future capture after recovery.
      await db.customStatement('DROP TRIGGER fail_payment_capture');
      await _record(ledger, expected: const []);
      expect(await ledger.pendingForInvoice('shop-test', 'invoice-test'), hasLength(1));
    });

    test('capture rejects a stale dialog after its queued payment has reconciled', () async {
      final operation = await _record(ledger, amount: 100);
      await ledger.flush('shop-test',
        submitPayment: (b, i, a, m, op) async => 'server-payment',
        fetchInvoice: (b, i) async => _detail(pending: 100,
          payments: [{'id': 'server-payment', 'amount': 100}]),
        cacheInvoice: (b, i, d) async {});
      await expectLater(
        _record(ledger, amount: 400, remaining: 40000, expected: [operation]),
        throwsStateError,
      );
      expect(await ledger.pendingForInvoice('shop-test', 'invoice-test'), isEmpty);
    });

    test('local invoice waits for remapping and retains its payment identity', () async {
      final operationId = await _record(ledger, invoice: 'local-invoice-test');
      var submissions = 0;
      Future<String> submit(String b, String i, num a, String m, String op) async {
        submissions++;
        expect(i, 'server-invoice');
        expect(op, operationId);
        return 'server-payment';
      }
      await ledger.flush('shop-test', submitPayment: submit,
        fetchInvoice: (b, i) async => _detail(), cacheInvoice: (b, i, d) async {});
      expect(submissions, 0);
      await ledger.remapInvoice('shop-test', 'local-invoice-test', 'server-invoice');
      await ledger.remapInvoice('shop-test', 'local-invoice-test', 'server-invoice');
      expect(await ledger.pendingForInvoice('shop-test', 'local-invoice-test'), isEmpty);
      final remapped = await ledger.pendingForInvoice('shop-test', 'server-invoice');
      expect(remapped, hasLength(1));
      expect(remapped.single['operation_id'], operationId);
      expect(remapped.single['invoice_id'], 'server-invoice');
      await ledger.flush('shop-test', submitPayment: submit,
        fetchInvoice: (b, i) async => _detail(pending: 500,
          payments: [{'id': 'server-payment', 'amount': 500}]),
        cacheInvoice: (b, i, d) async {});
      expect(submissions, 1);
      expect(await ledger.pendingForInvoice('shop-test', 'server-invoice'), isEmpty);
    });

    test('persists server ID before refresh and retries the same UUID after refresh failure', () async {
      final operationId = await _record(ledger);
      final operations = <String>[];
      Future<String> submit(String b, String i, num a, String m, String op) async {
        operations.add(op);
        return 'server-payment';
      }
      await ledger.flush('shop-test', submitPayment: submit,
        fetchInvoice: (b, i) async {
          final queued = await ledger.pendingForInvoice(b, i);
          expect(queued.single['server_payment_id'], 'server-payment');
          throw StateError('Refresh disconnected');
        }, cacheInvoice: (b, i, d) async => fail('Failed detail must not be cached'));
      final retained = await ledger.pendingForInvoice('shop-test', 'invoice-test');
      expect(retained.single['operation_id'], operationId);
      expect(retained.single['server_payment_id'], 'server-payment');
      final freshDetail = _detail(pending: 500,
        payments: [{'id': 'server-payment', 'amount': 500}]);
      final projected = OfflineInvoicePaymentLedger.projectPendingPayments(freshDetail, retained);
      expect(projected['pending_payment'], 500);
      expect(projected['payments'], hasLength(1));
      var cached = false;
      await ledger.flush('shop-test', submitPayment: submit,
        fetchInvoice: (b, i) async => freshDetail,
        cacheInvoice: (b, i, d) async {
          expect(await ledger.pendingForInvoice(b, i), hasLength(1));
          cached = true;
        });
      expect(operations, [operationId, operationId]);
      expect(cached, isTrue);
      expect(await ledger.pendingForInvoice('shop-test', 'invoice-test'), isEmpty);
    });

    test('retains a receipt until matching server detail is saved successfully', () async {
      final operationId = await _record(ledger);
      final operations = <String>[];
      Future<String> submit(String b, String i, num a, String m, String op) async {
        operations.add(op);
        return 'server-payment';
      }
      await ledger.flush('shop-test', submitPayment: submit,
        fetchInvoice: (b, i) async => _detail(pending: 500,
          payments: [{'id': 'unrelated-same-amount', 'amount': 500}]),
        cacheInvoice: (b, i, d) async => fail('Unreconciled detail must not be cached'));
      expect(await ledger.pendingForInvoice('shop-test', 'invoice-test'), hasLength(1));
      final reconciled = _detail(pending: 500,
        payments: [{'id': 'server-payment', 'amount': 500}]);
      await ledger.flush('shop-test', submitPayment: submit,
        fetchInvoice: (b, i) async => reconciled,
        cacheInvoice: (b, i, d) async => throw StateError('Disk failure'));
      final pending = await ledger.pendingForInvoice('shop-test', 'invoice-test');
      expect(pending, hasLength(1));
      expect(pending.single['server_payment_id'], 'server-payment');
      expect(OfflineInvoicePaymentLedger.projectPendingPayments(reconciled, pending)
        ['pending_payment'], 500);
      await ledger.flush('shop-test', submitPayment: submit,
        fetchInvoice: (b, i) async => reconciled, cacheInvoice: (b, i, d) async {});
      expect(operations, [operationId, operationId, operationId]);
      expect(await ledger.pendingForInvoice('shop-test', 'invoice-test'), isEmpty);
    });

    for (final includesWarranty in [false, true]) {
      test('default payment refresh preserves separately cached warranty unless replaced: $includesWarranty', () async {
        SharedPreferences.setMockInitialValues({});
        final cache = LocalDocumentDetailCache(database: db);
        final oldWarranty = <String, dynamic>{
          'company_name': 'Sandbox warranty', 'approved_amount': 500,
        };
        await cache.save('shop-test', 'invoice-test', {
          ..._detail(), 'offline_warranty_detail': oldWarranty,
        });
        await _record(ledger);
        final authoritative = _detail(pending: 500,
          payments: [{'id': 'server-payment', 'amount': 500}]);
        if (includesWarranty) {
          authoritative['offline_warranty_detail'] = <String, dynamic>{};
        }
        await ledger.flush('shop-test',
          submitPayment: (b, i, a, m, op) async => 'server-payment',
          fetchInvoice: (b, i) async => authoritative);
        final saved = await cache.load('shop-test', 'invoice-test');
        expect(saved?['pending_payment'], 500);
        expect(saved?['offline_warranty_detail'],
          includesWarranty ? isEmpty : oldWarranty);
        expect(authoritative.containsKey('offline_warranty_detail'), includesWarranty);
        expect(await ledger.pendingForInvoice('shop-test', 'invoice-test'), isEmpty);
      });
    }

    test('lost submission response keeps UUID and never duplicates server acceptance', () async {
      final operationId = await _record(ledger);
      final accepted = <String, String>{};
      var submissions = 0;
      Future<String> submit(String b, String i, num a, String m, String op) async {
        submissions++;
        final id = accepted.putIfAbsent(op, () => 'server-payment');
        if (submissions == 1) throw StateError('Response lost after acceptance');
        return id;
      }
      Future<Map<String, dynamic>> fetch(String b, String i) async =>
        _detail(pending: 500, payments: [{
          'id': 'server-payment', 'amount': 500, 'client_operation_id': operationId,
        }]);
      await ledger.flush('shop-test', submitPayment: submit,
        fetchInvoice: fetch, cacheInvoice: (b, i, d) async {});
      final queued = await ledger.pendingForInvoice('shop-test', 'invoice-test');
      expect(queued, hasLength(1));
      expect(queued.single['server_payment_id'], isNull);
      final projected = OfflineInvoicePaymentLedger.projectPendingPayments(
        await fetch('shop-test', 'invoice-test'), queued);
      expect(projected['pending_payment'], 500);
      expect(projected['payments'], hasLength(1));
      await ledger.flush('shop-test', submitPayment: submit,
        fetchInvoice: fetch, cacheInvoice: (b, i, d) async {});
      expect(submissions, 2);
      expect(accepted.keys, [operationId]);
      expect(await ledger.pendingForInvoice('shop-test', 'invoice-test'), isEmpty);
    });

    for (final responseLost in [false, true]) {
      test('a finalized replacement with unrelated ID cannot retire the receipt: $responseLost', () async {
        final operation = await _record(ledger);
        final operations = <String>[];
        Future<String> submit(String b, String i, num a, String m, String op) async {
          operations.add(op);
          final savedBeforeSubmit = await ledger.pendingForInvoice(b, i);
          expect(savedBeforeSubmit.single['replay_attempted'], isTrue);
          if (responseLost && operations.length == 1) {
            throw StateError('Accepted payment response lost');
          }
          // The idempotent endpoint retains its original pending payment ID,
          // even after finalization deleted that row and created a posted ID.
          return 'old-pending-payment';
        }
        final authoritative = _detail(paid: 500, payments: [{
          'id': 'replacement-posted-payment', 'amount': 500, 'state': 'finalized',
        }]);
        for (var attempt = 0; attempt < 2; attempt++) {
          await ledger.flush('shop-test', submitPayment: submit,
            fetchInvoice: (b, i) async => authoritative,
            cacheInvoice: (b, i, d) async => fail('Unknown identity cannot retire a receipt'));
          final pending = await ledger.pendingForInvoice('shop-test', 'invoice-test');
          expect(pending, hasLength(1));
          expect(pending.single['operation_id'], operation);
          expect(pending.single['replay_attempted'], isTrue);
          if (responseLost && attempt == 0) {
            expect(pending.single['server_payment_id'], isNull);
          } else {
            expect(pending.single['server_payment_id'], 'old-pending-payment');
          }
          final projected = OfflineInvoicePaymentLedger.projectPendingPayments(authoritative, pending);
          expect(projected['paid_amount'], 500);
          expect(projected['pending_payment'], 0);
          expect(projected['_payment_reconciliation_required'], isTrue);
          expect(projected['_local_pending_payment_amount'], 500);
        }
        expect(operations, [operation, operation]);
      });
    }

    test('unresolved invoice skips its later receipts but does not starve unrelated invoices', () async {
      final first = await _record(ledger, invoice: 'ambiguous-invoice', amount: 100);
      final unrelated = await _record(ledger, invoice: 'unrelated-invoice', amount: 200);
      final later = await _record(ledger, invoice: 'ambiguous-invoice', amount: 100,
        remaining: 40000, expected: [first]);
      final submissions = <String>[];
      final cachedInvoices = <String>[];
      await ledger.flush('shop-test',
        submitPayment: (b, i, a, m, op) async {
          submissions.add(op);
          return i == 'ambiguous-invoice' ? 'old-pending-id' : 'unrelated-payment';
        },
        fetchInvoice: (b, i) async => i == 'ambiguous-invoice'
          ? _detail(paid: 100, payments: [{
              'id': 'replacement-posted-id', 'amount': 100, 'state': 'finalized',
            }])
          : _detail(pending: 200, payments: [{
              'id': 'unrelated-payment', 'amount': 200, 'state': 'pending',
            }]),
        cacheInvoice: (b, i, d) async => cachedInvoices.add(i));
      expect(submissions, [first, unrelated]);
      expect(cachedInvoices, ['unrelated-invoice']);
      expect(await ledger.pendingForInvoice('shop-test', 'unrelated-invoice'), isEmpty);
      final retained = await ledger.pendingForInvoice('shop-test', 'ambiguous-invoice');
      expect(retained, hasLength(2));
      expect(retained.first['operation_id'], first);
      expect(retained.first['server_payment_id'], 'old-pending-id');
      expect(retained.last['operation_id'], later);
      expect(retained.last['replay_attempted'], isNull);
      expect(retained.last['server_payment_id'], isNull);
    });

    test('simultaneous flushes across ledger instances share one submission', () async {
      await _record(ledger);
      final started = Completer<void>();
      final release = Completer<void>();
      var submissions = 0;
      Future<String> submit(String b, String i, num a, String m, String op) async {
        submissions++;
        started.complete();
        await release.future;
        return 'server-payment';
      }
      Future<Map<String, dynamic>> fetch(String b, String i) async =>
        _detail(pending: 500, payments: [{'id': 'server-payment', 'amount': 500}]);
      final first = ledger.flush('shop-test', submitPayment: submit,
        fetchInvoice: fetch, cacheInvoice: (b, i, d) async {});
      await started.future;
      final second = OfflineInvoicePaymentLedger(database: db).flush('shop-test',
        submitPayment: submit, fetchInvoice: fetch, cacheInvoice: (b, i, d) async {});
      release.complete();
      await Future.wait([first, second]);
      expect(submissions, 1);
      expect(await ledger.pendingForInvoice('shop-test', 'invoice-test'), isEmpty);
    });

    test('missing idempotent API fails closed without invoking legacy payment RPC', () async {
      final api = _UnavailableIdempotentApi();
      final isolated = OfflineInvoicePaymentLedger(database: db, api: api);
      final operation = await _record(isolated);
      await isolated.flush('shop-test');
      await isolated.flush('shop-test');
      expect(api.operations, [operation, operation]);
      expect(api.legacyCalls, 0);
      expect(await isolated.pendingForInvoice('shop-test', 'invoice-test'), hasLength(1));
      final row = await db.customSelect('SELECT attempt_count,last_error FROM sync_outbox')
          .getSingle();
      expect(row.read<int>('attempt_count'), 2);
      expect(row.read<String>('last_error'), contains('Idempotent endpoint unavailable'));
    });
  });

  test('receipt and server acceptance survive closing and reopening the database', () async {
    final folder = await Directory.systemTemp.createTemp('briskers-payment-restart-');
    final file = File('${folder.path}/payments.sqlite');
    var db = BriskersLocalDatabase(NativeDatabase(file));
    try {
      var ledger = OfflineInvoicePaymentLedger(database: db);
      final operation = await _record(ledger);
      await db.close();
      db = BriskersLocalDatabase(NativeDatabase(file));
      ledger = OfflineInvoicePaymentLedger(database: db);
      final reopened = await ledger.pendingForInvoice('shop-test', 'invoice-test');
      expect(reopened.single['operation_id'], operation);
      expect(reopened.single['amount_cents'], 50000);
      expect(OfflineInvoicePaymentLedger.projectPendingPayments(_detail(), reopened)
        ['pending_payment'], 500);
      await ledger.flush('shop-test',
        submitPayment: (b, i, a, m, op) async => 'server-payment',
        fetchInvoice: (b, i) async => throw StateError('Restart before refresh'),
        cacheInvoice: (b, i, d) async {});
      await db.close();
      db = BriskersLocalDatabase(NativeDatabase(file));
      ledger = OfflineInvoicePaymentLedger(database: db);
      final retained = await ledger.pendingForInvoice('shop-test', 'invoice-test');
      expect(retained.single['operation_id'], operation);
      expect(retained.single['server_payment_id'], 'server-payment');
      final authoritative = _detail(pending: 500,
        payments: [{'id': 'server-payment', 'amount': 500}]);
      final projected = OfflineInvoicePaymentLedger.projectPendingPayments(authoritative, retained);
      expect(projected['pending_payment'], 500);
      expect(projected['payments'], hasLength(1));
      await ledger.flush('shop-test',
        submitPayment: (b, i, a, m, op) async {
          expect(op, operation);
          return 'server-payment';
        }, fetchInvoice: (b, i) async => authoritative, cacheInvoice: (b, i, d) async {});
      expect(await ledger.pendingForInvoice('shop-test', 'invoice-test'), isEmpty);
    } finally {
      await db.close();
      await folder.delete(recursive: true);
    }
  });
}

