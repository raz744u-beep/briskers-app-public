import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/local/briskers_local_database.dart' show BriskersLocalDatabase;
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:briskers_app/services/offline_receipt_metadata_sync_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api extends BriskersApi {
  int reads = 0;
  @override
  Future<Map<String, dynamic>> transactionDetail(
    String businessId, String transactionId,
  ) async {
    expect(businessId, 'shop-A');
    reads++;
    return {
      'id': transactionId,
      'amount': 15.00,
      'attachments': [{'bucket':'briskers-private','key':'receipt-$transactionId.jpg'}],
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BriskersLocalDatabase db;
  late LocalFinancialCache cache;
  late _Api api;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await BriskersConnectionModeController.instance
        .setMode(BriskersConnectionMode.auto);
    db = BriskersLocalDatabase(NativeDatabase.memory());
    cache = LocalFinancialCache(database: db);
    api = _Api();
    await cache.saveTransactions('shop-A', [
      {'id': 'record-A', 'receipt_count': 1, 'sync_state': 'synced'},
      {'id': 'record-B', 'receipt_count': 1, 'sync_state': 'pending'},
      {'id': 'record-C', 'receipt_count': 1, 'sync_state': 'synced'},
    ]);
    await cache.saveTransactions('shop-B', [
      {'id': 'other-shop', 'receipt_count': 1, 'sync_state': 'synced'},
    ]);
    // A previously edited locally saved detail must never be overwritten.
    await cache.saveTransactionDetail('shop-A', 'record-C',
        {'id': 'record-C', 'amount': 999, 'sync_state': 'pending'});
  });

  tearDown(() async {
    await db.close();
    await BriskersConnectionModeController.instance
        .setMode(BriskersConnectionMode.auto);
  });

  test('Idle receipt metadata uses only safe scoped missing details',
      () async {
    final sync = OfflineReceiptMetadataSyncService(
      api: api, cache: cache);
    expect(await sync.hydrateBatch('shop-A', batchSize: 12), 1);
    expect(api.reads, 1);
    expect((await cache.loadTransactionDetail(
        'shop-A', 'record-A'))?['attachments'], isNotEmpty);
    expect((await cache.loadTransactionDetail(
        'shop-A', 'record-C'))?['amount'], 999);
    expect(await cache.loadTransactionDetail('shop-A', 'record-B'), isNull);
    expect(await cache.loadTransactionDetail('shop-B', 'other-shop'), isNull);
    // Already cached details are not fetched or overwritten on retry.
    expect(await sync.hydrateBatch('shop-A', batchSize: 12), 0);
    expect(api.reads, 1);
  });

  test('Force Offline cannot issue background receipt requests', () async {
    await BriskersConnectionModeController.instance
        .setMode(BriskersConnectionMode.offline);
    final sync = OfflineReceiptMetadataSyncService(api: api, cache: cache);
    expect(await sync.hydrateBatch('shop-A'), 0);
    expect(api.reads, 0);
  });
}
