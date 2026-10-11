import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/services/local_payment_methods_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('payment methods are cached per shop with stable IDs', () async {
    const cache = LocalPaymentMethodsCache();
    await cache.save('shop-a', [
      {'id': 'cash-id', 'name': 'Cash'},
      {'id': 'check-id', 'name': 'Check'},
    ]);
    expect((await cache.load('shop-a')).map((m) => m['id']).toList(),
        ['cash-id', 'check-id']);
    expect(await cache.load('shop-b'), isEmpty);
  });

  test('invalid cache contents cannot crash offline method chooser', () async {
    SharedPreferences.setMockInitialValues({
      'briskers_payment_methods_shop-a': '{invalid',
    });
    const cache = LocalPaymentMethodsCache();
    expect(await cache.load('shop-a'), isEmpty);
  });
}
