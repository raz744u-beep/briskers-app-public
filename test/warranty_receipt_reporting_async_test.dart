import 'dart:convert';

import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/warranty_receipt_reporting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _warranty = <String, dynamic>{
  'extended_warranty': true,
  'approved_amount': 515,
  'terminal_amount': 515,
  'processor_fee': 15,
  'net_applied': 500,
  'surcharge_rate': 0.03,
};
const _card = <String, dynamic>{
  'id': 'synthetic-card',
  'amount': 515,
  'payment_method_name': 'Credit Card',
  'state': 'posted',
};
const _cash = <String, dynamic>{
  'id': 'synthetic-cash',
  'amount': 1545,
  'payment_method_name': 'Cash',
  'state': 'posted',
};
const _invoice = <String, dynamic>{
  'id': 'synthetic-invoice',
  'row_version': 12,
  'total_amount': 2060,
  'paid_amount': 2060,
  'pending_payment': 0,
  'payments': [_cash, _card],
};

Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

Map<String, dynamic> _transaction(Map<String, dynamic> payment) => {
  ...payment,
  'kind': 'customer_payment',
  'direction': 'income',
  'signed_amount': payment['amount'],
};

class _Cache extends LocalDocumentDetailCache {
  _Cache(this.rows, {this.fail = false});
  final List<Map<String, dynamic>> rows;
  final bool fail;
  int calls = 0;
  int targetedCalls = 0;

  @override
  Future<List<Map<String, dynamic>>> loadAll(String businessId) async {
    calls++;
    if (fail) throw StateError('Synthetic cache unavailable');
    return rows.map(_copy).toList();
  }

  @override
  Future<Map<String, dynamic>?> load(
    String businessId,
    String documentId,
  ) async {
    targetedCalls++;
    if (fail) throw StateError('Synthetic cache unavailable');
    for (final row in rows) {
      if (row['id']?.toString() == documentId) return _copy(row);
    }
    return null;
  }
}

class _Api extends BriskersApi {
  _Api({this.details = const [_invoice, _invoice], this.failWarranty = false});
  final List<Map<String, dynamic>> details;
  final bool failWarranty;
  int detailReads = 0;
  int warrantyReads = 0;

  @override
  Future<Map<String, dynamic>> documentDetail(
    String businessId,
    String documentId,
  ) async {
    final index = detailReads++;
    return _copy(details[index < details.length ? index : details.length - 1]);
  }

  @override
  Future<Map<String, dynamic>> documentWarrantyDetail(
    String businessId,
    String documentId,
  ) async {
    warrantyReads++;
    if (failWarranty) throw StateError('Synthetic permission/read failure');
    return _copy(_warranty);
  }
}

WarrantyReceiptReporting _service(
  _Api api,
  _Cache cache, {
  String? user = 'user-a',
}) =>
    WarrantyReceiptReporting(api: api, cache: cache, currentUserId: () => user);

void _expectGross(Map<String, dynamic> row) {
  expect(row['amount'], 515);
  expect(row['signed_amount'], 515);
  expect(row['reporting_status'], 'unverified');
  expect(row.containsKey('reporting_amount'), isFalse);
  expect(row.containsKey('reporting_processor_fee'), isFalse);
  expect(WarrantyReceiptReporting.amount(row), 515);
}

Future<void> _saveReport({
  String user = 'user-a',
  String business = 'shop-a',
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    'briskers_warranty_reporting_${user}_${business}_synthetic-invoice',
    jsonEncode({..._invoice, 'offline_warranty_detail': _warranty}),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await BriskersConnectionModeController.instance.setMode(
      BriskersConnectionMode.auto,
    );
  });
  tearDown(() async {
    await BriskersConnectionModeController.instance.setMode(
      BriskersConnectionMode.auto,
    );
  });

  test(
    'consistent reads share one invoice fetch and preserve the gross ledger',
    () async {
      final api = _Api();
      final cache = _Cache([_invoice]);
      final rows = [_transaction(_cash), _transaction(_card)];
      final result = await _service(api, cache).enrich('shop-a', rows);
      expect(result.map(WarrantyReceiptReporting.amount), [1545, 500]);
      expect(result[1]['amount'], 515);
      expect(result[1]['signed_amount'], 515);
      expect(rows[1].containsKey('reporting_amount'), isFalse);
      expect(cache.rows.single, _invoice);
      expect(api.detailReads, 2);
      expect(api.warrantyReads, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.containsKey(
          'briskers_warranty_reporting_user-a_shop-a_synthetic-invoice',
        ),
        isTrue,
      );
    },
  );

  test(
    'changed document version or payment set never produces a verified net',
    () async {
      for (final after in [
        {..._invoice, 'row_version': 13},
        {
          ..._invoice,
          'payments': [
            _cash,
            _card,
            {..._card, 'id': 'second-card'},
          ],
        },
        {..._invoice, 'id': 'wrong-invoice'},
      ]) {
        final api = _Api(details: [_invoice, after]);
        final result = await _service(
          api,
          _Cache([_invoice]),
        ).enrich('shop-a', [_transaction(_card)]);
        _expectGross(result.single);
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.containsKey(
            'briskers_warranty_reporting_user-a_shop-a_synthetic-invoice',
          ),
          isFalse,
        );
      }
    },
  );

  test(
    'read failure clears stale net fields without hiding the receipt',
    () async {
      await _saveReport();
      final stale = {
        ..._transaction(_card),
        'reporting_amount': 500,
        'reporting_processor_fee': 15,
        'reporting_status': 'verified',
      };
      final result = await _service(
        _Api(failWarranty: true),
        _Cache([_invoice]),
      ).enrich('shop-a', [stale]);
      _expectGross(result.single);
      expect(stale['reporting_amount'], 500);
    },
  );

  test(
    'cache failure and missing authentication retain raw receipts',
    () async {
      final api = _Api();
      final cache = _Cache([_invoice], fail: true);
      _expectGross(
        (await _service(
          api,
          cache,
        ).enrich('shop-a', [_transaction(_card)])).single,
      );
      final noAuthCache = _Cache([_invoice]);
      _expectGross(
        (await _service(
          api,
          noAuthCache,
          user: null,
        ).enrich('shop-a', [_transaction(_card)])).single,
      );
      expect(api.detailReads, 0);
      expect(noAuthCache.calls, 0);
    },
  );

  test(
    'offline reporting requires the same user and business verified context',
    () async {
      await _saveReport();
      final api = _Api();
      final cache = _Cache([
        {..._invoice, 'offline_warranty_detail': _warranty},
      ]);
      final own = await _service(
        api,
        cache,
      ).enrich('shop-a', [_transaction(_card)], refresh: false);
      expect(own.single['reporting_amount'], 500);
      _expectGross(
        (await _service(
          api,
          cache,
          user: 'user-b',
        ).enrich('shop-a', [_transaction(_card)], refresh: false)).single,
      );
      _expectGross(
        (await _service(
          api,
          cache,
        ).enrich('shop-b', [_transaction(_card)], refresh: false)).single,
      );
      expect(api.detailReads, 0);
      expect(api.warrantyReads, 0);
    },
  );

  test(
    'business-only historical cache cannot authorize offline fee reporting',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final detail = {..._invoice, 'offline_warranty_detail': _warranty};
      await prefs.setString(
        'briskers_warranty_reporting_shop-a_synthetic-invoice',
        jsonEncode(detail),
      );
      _expectGross(
        (await _service(
          _Api(),
          _Cache([detail]),
        ).enrich('shop-a', [_transaction(_card)], refresh: false)).single,
      );
    },
  );

  test('newer split receipt or dirty local detail invalidates older offline attribution', () async {
    await _saveReport();
    for (final current in [
      {
        ..._invoice,
        'row_version': 13,
        'payments': [
          _cash,
          _card,
          {..._card, 'id': 'second-card'},
        ],
      },
      {
        ..._invoice,
        'sync_state': 'pending',
        'offline_warranty_detail': _warranty,
      },
      {
        ..._invoice,
        '_payment_reconciliation_required': true,
        'offline_warranty_detail': _warranty,
      },
    ]) {
      _expectGross(
        (await _service(
          _Api(),
          _Cache([current]),
        ).enrich('shop-a', [_transaction(_card)], refresh: false)).single,
      );
    }
  });

  test(
    'offline reporting reads only user-scoped invoice; never scans all cache',
    () async {
      await _saveReport();
      final prefs = await SharedPreferences.getInstance();
      // Existing installations may hold thousands of unrelated invoice
      // snapshots. They must not be scanned for a two-row payment display.
      for (var index = 0; index < 120; index++) {
        await prefs.setString(
          'briskers_document_detail_shop-a_unrelated-$index',
          '{"id":"unrelated-$index","kind":"invoice"}',
        );
      }
      final api = _Api();
      final cache = _Cache([_invoice]);
      final result = await _service(api, cache).enrich(
        'shop-a', [_transaction(_card)], refresh: false,
      );
      expect(result.single['reporting_amount'], 500);
      expect(cache.calls, 0,
          reason: 'Offline may not read every invoice in the database');
      expect(cache.targetedCalls, 1);
      expect(api.detailReads, 0);
      expect(api.warrantyReads, 0);
    },
  );

  test('period totals read only invoice reports matching the income scope',
      () async {
    await _saveReport();
    final prefs = await SharedPreferences.getInstance();
    // Simulate a shop with historical, user-scoped warranty reports.
    // These are genuine previous reporting records but have no payment IDs
    // in the currently selected accounting period.
    for (var i = 0; i < 160; i++) {
      await prefs.setString(
        'briskers_warranty_reporting_user-a_shop-a_old-$i',
        jsonEncode({
          ..._invoice,
          'id': 'old-$i',
          'payments': [
            {'id': 'old-payment-$i', 'amount': 10, 'state': 'posted'},
          ],
          'offline_warranty_detail': _warranty,
        }),
      );
    }
    final cache = _Cache([_invoice]);
    final rows = [_transaction(_card), _transaction(_cash)];
    final verified = await _service(_Api(), cache)
        .enrich('shop-a', rows, refresh: false);
    expect(verified.map(WarrantyReceiptReporting.amount), [500, 1545]);
    expect(cache.calls, 0);
    expect(cache.targetedCalls, 1,
        reason: 'Do not await 160 unrelated historical invoice reads');
  });

  test('expense-only total batches never read warranty document caches',
      () async {
    await _saveReport();
    final cache = _Cache([_invoice]);
    final rows = [
      {'id': 'expense-1', 'direction': 'expense', 'amount': 12},
      {'id': 'expense-2', 'direction': 'expense', 'amount': 17},
    ];
    final result = await _service(_Api(), cache)
        .enrich('shop-a', rows, refresh: false);
    expect(result, hasLength(2));
    expect(cache.calls, 0);
    expect(cache.targetedCalls, 0);
    expect(result.map((r) => r['amount']), [12, 17]);
  });

  test('offline with no user-scoped fee cache does not scan documents',
      () async {
    final cache = _Cache([_invoice], fail: true);
    final rows = [_transaction(_card), _transaction(_cash)];
    final result = await _service(_Api(), cache)
        .enrich('shop-a', rows, refresh: false);
    expect(result, hasLength(2));
    _expectGross(result.first);
    expect(cache.calls, 0);
    expect(cache.targetedCalls, 0);
  });

  test(
    'Force Offline performs no RPC and preserves unrelated receipts',
    () async {
      await _saveReport();
      await BriskersConnectionModeController.instance.setMode(
        BriskersConnectionMode.offline,
      );
      final api = _Api();
      final result = await _service(api, _Cache([_invoice])).enrich('shop-a', [
        _transaction(_card),
        {..._transaction(_card), 'id': 'unlinked'},
      ]);
      expect(result.first['reporting_amount'], 500);
      _expectGross(result.last);
      expect(api.detailReads, 0);
    },
  );
}
