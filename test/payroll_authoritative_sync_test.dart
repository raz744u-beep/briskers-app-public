import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/payroll_authoritative_sync.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

String pid(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
Map<String, dynamic> snapshot({
  int revision = 1,
  String label = 'Renamed Cash',
  String? historical = 'Historical Check',
}) => {
  'business_id': pid(1),
  'revision': revision,
  'methods': [
    {
      'business_id': pid(1),
      'id': pid(10),
      'client_key': pid(20),
      'label': label,
      'kind': 'cash',
      'enabled': true,
      'sort_order': 0,
      'version': revision,
    },
  ],
  'employee_defaults': [
    {'employee_id': pid(6), 'method_id': pid(10)},
  ],
  'receipts': [
    {
      'business_id': pid(1),
      'transaction_id': pid(30),
      'employee_id': pid(6),
      'amount_cents': 12345,
      'payment_date': '2026-10-23',
      'method_id': pid(99),
      'method_label': historical,
      'status': 'posted',
    },
  ],
};

class CatalogGateway implements PayrollAuthoritativeGateway {
  bool available = true, loseResponse = false;
  int applications = 0, fetches = 0;
  Map<String, dynamic> state = snapshot();
  final applied = <String, String>{};
  Completer<Map<String, dynamic>>? delayed;
  @override
  Future<bool> supportsReviewedPayrollV1(String businessId) async => available;
  @override
  Future<Map<String, dynamic>> fetchPayrollState(String businessId) async {
    fetches++;
    return delayed?.future ??
        jsonDecode(jsonEncode(state)) as Map<String, dynamic>;
  }

  @override
  Future<void> applyCatalogMutation(
    String businessId,
    Map<String, dynamic> change,
  ) async {
    final id = change['operation_id'] as String, encoded = jsonEncode(change);
    if (applied.containsKey(id)) {
      if (applied[id] != encoded) throw StateError('changed replay');
      return;
    }
    applied[id] = encoded;
    applications++;
    if (change['action'] == 'edit') {
      (state['methods'] as List).single['label'] = change['label'];
      (state['methods'] as List).single['version']++;
    }
    if (change['action'] == 'default') {
      state['employee_defaults'] = change['method_id'] == null
          ? []
          : [
              {
                'employee_id': change['employee_id'],
                'method_id': change['method_id'],
              },
            ];
    }
    state['revision']++;
    if (loseResponse) {
      loseResponse = false;
      throw const SocketException('Lost response after server commit');
    }
  }
}

PayrollAuthoritativeSync service(
  BriskersLocalDatabase db, {
  String owner = 'owner',
  bool Function()? context,
}) => PayrollAuthoritativeSync(
  database: db,
  businessId: pid(1),
  ownerUserId: owner,
  isContextCurrent: context ?? () => true,
);
void main() {
  test(
    'authoritative IDs/defaults and unknown historical label survive offline restart',
    () async {
      final dir = await Directory.systemTemp.createTemp('payroll-catalog-');
      final file = File('${dir.path}/db');
      var db = BriskersLocalDatabase(NativeDatabase(file));
      var sync = service(db);
      final gateway = CatalogGateway()..state = snapshot(historical: null);
      expect(await sync.synchronize(gateway), true);
      await db.close();
      db = BriskersLocalDatabase(NativeDatabase(file));
      sync = service(db);
      final catalog = await sync.catalog();
      expect((catalog['methods'] as List).single['id'], pid(10));
      expect(
        (catalog['employee_defaults'] as List).single['method_id'],
        pid(10),
      );
      expect((await sync.receipts()).single['method_label'], isNull);
      gateway.available = false;
      expect(await sync.synchronize(gateway), false);
      expect(gateway.fetches, 1);
      expect(await service(db, owner: 'other').receipts(), isEmpty);
      await db.close();
      await dir.delete(recursive: true);
    },
  );
  test(
    'lost configuration response retries one frozen operation after DB restart',
    () async {
      final dir = await Directory.systemTemp.createTemp('payroll-edit-');
      final file = File('${dir.path}/db');
      var db = BriskersLocalDatabase(NativeDatabase(file));
      var sync = service(db);
      final gateway = CatalogGateway();
      await sync.synchronize(gateway);
      final edit = {
        'operation_id': pid(50),
        'action': 'edit',
        'method_id': pid(10),
        'expected_version': 1,
        'label': 'Paper cash',
        'enabled': true,
        'sort_order': 0,
      };
      await sync.queueMutation(edit);
      gateway.loseResponse = true;
      await expectLater(
        sync.synchronize(gateway),
        throwsA(isA<SocketException>()),
      );
      expect(await sync.pendingCount(), 1);
      await db.close();
      db = BriskersLocalDatabase(NativeDatabase(file));
      sync = service(db);
      await sync.synchronize(gateway);
      expect(gateway.applications, 1);
      expect(await sync.pendingCount(), 0);
      expect(
        ((await sync.catalog())['methods'] as List).single['label'],
        'Paper cash',
      );
      expect(
        (await sync.receipts()).single['method_label'],
        'Historical Check',
      );
      await db.close();
      await dir.delete(recursive: true);
    },
  );
  test(
    'invalid cross-shop/duplicate snapshots cannot replace confirmed cache',
    () async {
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      final sync = service(db), gateway = CatalogGateway();
      await sync.synchronize(gateway);
      gateway.state = snapshot(revision: 2);
      (gateway.state['methods'] as List).single['business_id'] = pid(2);
      await expectLater(sync.synchronize(gateway), throwsStateError);
      gateway.state = snapshot(revision: 2);
      (gateway.state['methods'] as List).add(
        (gateway.state['methods'] as List).single,
      );
      await expectLater(sync.synchronize(gateway), throwsStateError);
      expect(((await sync.catalog())['methods'] as List).single['version'], 1);
      await db.close();
    },
  );
  test(
    'late older snapshot cannot overwrite catalog or receipt data',
    () async {
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      final sync = service(db),
          gateway = CatalogGateway()
            ..state = snapshot(
              revision: 3,
              label: 'Latest',
              historical: 'Captured',
            );
      await sync.synchronize(gateway);
      gateway.state = snapshot(
        revision: 2,
        label: 'Stale',
        historical: 'Wrong old label',
      );
      await sync.synchronize(gateway);
      expect(
        ((await sync.catalog())['methods'] as List).single['label'],
        'Latest',
      );
      expect((await sync.receipts()).single['method_label'], 'Captured');
      await db.close();
    },
  );
  test(
    'auth revocation during fetch cannot store or reveal a late response',
    () async {
      var allowed = true;
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      final sync = service(db, context: () => allowed),
          gateway = CatalogGateway()..delayed = Completer();
      final loading = sync.synchronize(gateway);
      await Future<void>.delayed(Duration.zero);
      allowed = false;
      gateway.delayed!.complete(snapshot());
      await expectLater(loading, throwsStateError);
      expect(await service(db, owner: 'new-owner').receipts(), isEmpty);
      await db.close();
    },
  );
  test(
    'defaults require registered IDs and queued operation terms cannot change',
    () async {
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      final sync = service(db), gateway = CatalogGateway();
      await sync.synchronize(gateway);
      await expectLater(
        sync.queueMutation({
          'operation_id': pid(60),
          'action': 'default',
          'employee_id': pid(6),
          'method_id': pid(20),
        }),
        throwsStateError,
      );
      final valid = {
        'operation_id': pid(60),
        'action': 'default',
        'employee_id': pid(6),
        'method_id': pid(10),
      };
      await sync.queueMutation(valid);
      await expectLater(
        sync.queueMutation({...valid, 'method_id': null}),
        throwsStateError,
      );
      await sync.synchronize(gateway);
      expect(gateway.applications, 1);
      await db.close();
    },
  );
}
