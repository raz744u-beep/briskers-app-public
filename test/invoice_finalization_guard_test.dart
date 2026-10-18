import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/core/briskers_i18n.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/invoice_finalization_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BriskersLocalDatabase db;
  late InvoiceFinalizationGuard guard;
  var offline = false;
  var calls = 0;

  Future<void> receipt({
    String invoice = 'invoice',
    String shop = 'shop',
    String state = 'pending',
    String? payload,
  }) => db.customStatement(
    'INSERT INTO sync_outbox(business_id,entity_type,entity_id,operation,payload_json,state) VALUES(?,?,?,?,?,?)',
    [
      shop,
      'invoice_payment_received',
      invoice,
      'record_received_payment',
      payload ?? '{}',
      state,
    ],
  );
  Future<int> attempt({
    Iterable<String> ids = const ['invoice'],
    bool owner = true,
    String shop = 'shop',
  }) => guard.run(
    businessId: shop,
    invoiceIds: ids,
    isOwner: owner,
    action: () async {
      calls++;
      return 42;
    },
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await BriskersLanguageController.instance.setLanguage('en');
    db = BriskersLocalDatabase(NativeDatabase.memory());
    offline = false;
    calls = 0;
    guard = InvoiceFinalizationGuard(database: db, forceOffline: () => offline);
  });
  tearDown(() => db.close());

  test('clean owner invoice invokes action and returns its result', () async {
    expect(await attempt(), 42);
    expect(calls, 1);
  });

  test(
    'non-owner, missing IDs, local IDs and Force Offline never invoke RPC',
    () async {
      await expectLater(attempt(owner: false), throwsStateError);
      await expectLater(attempt(ids: []), throwsStateError);
      await expectLater(attempt(ids: ['']), throwsStateError);
      await expectLater(attempt(ids: ['local-invoice-123']), throwsStateError);
      await expectLater(
        attempt(ids: ['invoice', 'local-other']),
        throwsStateError,
      );
      await expectLater(attempt(ids: [' invoice ']), throwsStateError);
      await expectLater(attempt(shop: ''), throwsStateError);
      offline = true;
      await expectLater(attempt(), throwsStateError);
      expect(calls, 0);
    },
  );

  for (final state in ['pending', 'inflight', 'failed', 'done', 'unexpected']) {
    test(
      'retained $state receipt blocks action without decoding or retiring it',
      () async {
        await receipt(state: state, payload: 'malformed payload');
        await expectLater(attempt(), throwsStateError);
        expect(calls, 0);
        final retained = await db
            .customSelect('SELECT state,payload_json FROM sync_outbox')
            .getSingle();
        expect(retained.read<String>('state'), state);
        expect(retained.read<String>('payload_json'), 'malformed payload');
      },
    );
  }

  for (final state in ['pending', 'inflight', 'failed', 'done']) {
    test('retained $state server-payment correction blocks finalization', () async {
      await db.customStatement(
        'INSERT INTO sync_outbox('
        'business_id,entity_type,entity_id,operation,payload_json,state) '
        "VALUES(?,'invoice_pending_payment_edit',?,'edit_pending_payment',?,?)",
        ['shop', 'invoice', 'not-decodable', state],
      );
      await expectLater(attempt(), throwsStateError);
      expect(calls, 0);
      final queued = await db.customSelect(
        'SELECT payload_json,state FROM sync_outbox'
      ).getSingle();
      expect(queued.read<String>('payload_json'), 'not-decodable');
      expect(queued.read<String>('state'), state);
    });
  }

  test(
    'server acknowledged receipt still blocks until durable queue retirement',
    () async {
      await receipt(
        payload: jsonEncode({
          'operation_id': 'op',
          'server_payment_id': 'server-payment',
          'amount_cents': 10000,
          'replay_attempted': true,
        }),
      );
      await expectLater(attempt(), throwsStateError);
      expect(calls, 0);
      expect(
        (await db
                .customSelect('SELECT COUNT(*) AS n FROM sync_outbox')
                .getSingle())
            .read<int>('n'),
        1,
      );
    },
  );

  test('whole-selection preflight rejects a later blocked invoice before any action', () async {
    await receipt(invoice: 'second');
    await expectLater(attempt(ids: ['first', 'second']), throwsStateError);
    expect(calls, 0);
  });

  test(
    'only selected invoices in the matching shop block finalization',
    () async {
      await receipt(invoice: 'another');
      await receipt(shop: 'another-shop');
      await db.customStatement(
        "INSERT INTO sync_outbox(business_id,entity_type,entity_id,operation,payload_json,state) VALUES('shop','unrelated','invoice','update','{}','pending')",
      );
      expect(await attempt(), 42);
      expect(calls, 1);
    },
  );

  test(
    'receipt arriving while confirmation is open prevents the final RPC',
    () async {
      final confirmation = Completer<void>();
      Future<int> confirmedAction() async {
        await confirmation.future;
        return attempt();
      }

      final result = confirmedAction();
      final blocked = expectLater(result, throwsStateError);
      await receipt(payload: jsonEncode({'server_payment_id': 'acknowledged'}));
      confirmation.complete();
      await blocked;
      expect(calls, 0);
    },
  );

  test(
    'Force Offline selected while confirmation is open prevents the final RPC',
    () async {
      final confirmation = Completer<void>();
      Future<int> confirmedAction() async {
        await confirmation.future;
        return attempt();
      }

      final result = confirmedAction();
      final blocked = expectLater(result, throwsStateError);
      offline = true;
      confirmation.complete();
      await blocked;
      expect(calls, 0);
    },
  );

  test('Force Offline changing during awaited scan prevents action', () async {
    var modeReads = 0;
    guard = InvoiceFinalizationGuard(
      database: db,
      forceOffline: () => ++modeReads >= 2,
    );
    await expectLater(attempt(), throwsStateError);
    expect(calls, 0);
  });

  test(
    'mode is rechecked after preflight returns immediately before action',
    () async {
      var modeReads = 0;
      guard = InvoiceFinalizationGuard(
        database: db,
        forceOffline: () => ++modeReads >= 3,
      );
      await expectLater(attempt(), throwsStateError);
      expect(calls, 0);
    },
  );

  test(
    'a receipt arriving after selection preflight is caught by per-RPC check',
    () async {
      await guard.check(
        businessId: 'shop',
        invoiceIds: ['invoice'],
        isOwner: true,
      );
      await receipt();
      await expectLater(attempt(), throwsStateError);
      expect(calls, 0);
    },
  );

  test('database read failure fails closed without invoking action', () async {
    await db.customStatement('DROP TABLE sync_outbox');
    await expectLater(attempt(), throwsA(anything));
    expect(calls, 0);
  });

  test('blocked finalization has Spanish guidance', () async {
    await BriskersLanguageController.instance.setLanguage('es');
    await receipt();
    await expectLater(
      attempt(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('conciliación'),
        ),
      ),
    );
    expect(calls, 0);
    await BriskersLanguageController.instance.setLanguage('en');
  });
}
