import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/local_item_categories_cache.dart';

class _FakeApi extends BriskersApi {
  _FakeApi({this.rows = const [], this.fail = false});
  final List<Map<String, dynamic>> rows;
  final bool fail;
  int calls = 0;

  @override
  Future<List<Map<String, dynamic>>> itemCategories(
    String businessId, {
    bool includeInactive = true,
  }) async {
    calls++;
    if (fail) throw StateError('Connection aborted');
    return rows;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('saved item categories are strictly shop-scoped', () async {
    const cache = LocalItemCategoriesCache();
    await cache.save('shop-one', [
      {'name': 'Electrical', 'active': true},
    ]);
    await cache.save('shop-two', [
      {'name': 'Engine', 'active': false},
    ]);
    expect((await cache.load('shop-one')).single['name'], 'Electrical');
    expect((await cache.load('shop-two')).single['name'], 'Engine');
    expect(await cache.load('shop-three'), isEmpty);
  });

  test('Force Offline never attempts an RPC and retains inactive category', () async {
    final api = _FakeApi(fail: true);
    final cache = LocalItemCategoriesCache(api: api);
    await cache.save('shop', [
      {'name': 'Electrical', 'active': false},
    ]);
    final choices = await cache.forInvoiceEditor(
      'shop',
      forceOffline: true,
      localCatalogItems: [
        {'category': 'Engine'},
        {'category': 'engine'},
        {'category': 'Electrical'},
      ],
    );
    expect(api.calls, 0);
    expect(choices.map((row) => row['name']).toList(),
        ['Electrical', 'Engine']);
    expect(choices.first['active'], false);
  });

  test('Auto fetches choices and persists them for future offline editors', () async {
    final api = _FakeApi(rows: [
      {'name': 'Brakes', 'active': true, 'sort_order': 10},
      {'name': 'Suspension', 'active': false, 'sort_order': 20},
    ]);
    final cache = LocalItemCategoriesCache(api: api);
    final auto = await cache.forInvoiceEditor(
      'shop',
      forceOffline: false,
      localCatalogItems: [{'category': 'Engine'}],
    );
    expect(api.calls, 1);
    expect(auto.map((row) => row['name']).toList(),
        ['Brakes', 'Suspension', 'Engine']);
    expect(auto[1]['active'], false);

    final offline = await cache.forInvoiceEditor(
      'shop',
      forceOffline: true,
      localCatalogItems: const [],
    );
    expect(offline.map((row) => row['name']).toList(),
        ['Brakes', 'Suspension']);
    expect(api.calls, 1);
  });

  test('Auto network failure falls back to cached and local categories', () async {
    final api = _FakeApi(fail: true);
    final cache = LocalItemCategoriesCache(api: api);
    await cache.save('shop', [
      {'name': 'Parts', 'active': true},
    ]);
    final result = await cache.forInvoiceEditor(
      'shop',
      forceOffline: false,
      localCatalogItems: [{'category': 'Labor'}],
    );
    expect(api.calls, 1);
    expect(result.map((row) => row['name']).toList(), ['Parts', 'Labor']);
  });

  test('duplicate and empty local category labels are ignored', () {
    final result = LocalItemCategoriesCache.merge(
      [
        {'name': 'Body', 'active': false},
      ],
      LocalItemCategoriesCache.fromCatalogItems([
        {'category': 'body'},
        {'category': '  '},
        {'category': 'Engine'},
        {'category': 'ENGINE'},
        {'category': null},
      ]),
    );
    expect(result.map((row) => row['name']).toList(), ['Body', 'Engine']);
    expect(result.first['active'], false);
  });
}
