import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('cleanup invalidation preserves a newer pending detail snapshot', () async {
    SharedPreferences.setMockInitialValues({});
    const cache = LocalDocumentDetailCache();
    final original = {'id': 'd', 'row_version': 1, 'sync_state': 'synced'};
    await cache.save('shop', 'd', original);
    final captured = await cache.load('shop', 'd');
    await cache.save('shop', 'd', {...original, 'memo': 'Unsent edit', 'sync_state': 'pending'});
    expect(await cache.removeIfUnchanged('shop', 'd', captured), isFalse);
    expect((await cache.load('shop', 'd'))?['memo'], 'Unsent edit');
  });
  test('cleanup invalidation removes only matching scoped snapshot', () async {
    SharedPreferences.setMockInitialValues({});
    const cache = LocalDocumentDetailCache();
    final original = {'id': 'd', 'row_version': 1};
    await cache.save('shop', 'd', original);
    await cache.save('other', 'd', original);
    expect(await cache.removeIfUnchanged('shop', 'd', original), isTrue);
    expect(await cache.load('shop', 'd'), isNull);
    expect(await cache.load('other', 'd'), isNotNull);
  });
  test('cache-only pending state is never invalidated even with a matching snapshot', () async {
    SharedPreferences.setMockInitialValues({});
    const cache = LocalDocumentDetailCache();
    final pending = {'id': 'd', 'memo': 'Not queued yet', 'sync_state': 'pending'};
    await cache.save('shop', 'd', pending);
    expect(await cache.removeIfUnchanged('shop', 'd', pending), isFalse);
    expect(await cache.load('shop', 'd'), pending);
  });
  test('concurrent newer write survives regardless of invalidation queue order', () async {
    SharedPreferences.setMockInitialValues({});
    const cache = LocalDocumentDetailCache();
    const anotherInstance = LocalDocumentDetailCache();
    final old = {'id': 'd', 'row_version': 1};
    final edit = {'id': 'd', 'memo': 'New edit', 'sync_state': 'pending'};
    await cache.save('shop', 'd', old);
    await Future.wait<dynamic>([
      cache.removeIfUnchanged('shop', 'd', old),
      anotherInstance.save('shop', 'd', edit),
    ]);
    expect(await cache.load('shop', 'd'), edit);
    await cache.save('shop', 'd', old);
    await Future.wait<dynamic>([
      anotherInstance.save('shop', 'd', edit),
      cache.removeIfUnchanged('shop', 'd', old),
    ]);
    expect(await cache.load('shop', 'd'), edit);
  });

}
