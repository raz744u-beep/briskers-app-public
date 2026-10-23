import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/services/owner_job_profitability_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const cache = OwnerJobProfitabilityCache();
  const verified = <String, dynamic>{
    'revenue': 400.0,
    'sales_tax': 40.0,
    'direct_cost': 110.0,
    'mechanic_cost': 90.0,
    'total_cost': 200.0,
  };

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('loads only same owner, business and job', () async {
    await cache.save('shop-a', 'owner-a', 'job-a', verified);
    expect((await cache.load('shop-a', 'owner-a', 'job-a'))?.data['revenue'], 400.0);
    expect(await cache.load('shop-b', 'owner-a', 'job-a'), isNull);
    expect(await cache.load('shop-a', 'owner-b', 'job-a'), isNull);
    expect(await cache.load('shop-a', 'owner-a', 'job-b'), isNull);
  });

  test('never saves incomplete expense or labor costs', () async {
    await cache.save('shop', 'owner', 'job', {
      'revenue': 900.0, 'sales_tax': 90.0,
      'direct_cost': 150.0,
    });
    expect(await cache.load('shop', 'owner', 'job'), isNull);
  });

  test('retains verified pre-tax totals across offline/relaunch', () async {
    final then = DateTime(2026, 10, 22, 12, 30);
    await cache.save('shop', 'owner', 'job', verified, verifiedAt: then);
    final entry = await cache.load('shop', 'owner', 'job');
    expect(entry, isNotNull);
    expect(entry!.data['total_cost'], 200.0);
    expect(entry.at.year, 2026);
    expect(entry.at.month, 10);
    expect(entry.data.containsKey('verified_at'), false);
    expect(entry.data.containsKey('expenses'), false);
  });

  test('invalid future verification does not produce a usable snapshot', () async {
    await cache.save('shop', 'owner', 'job', verified,
        verifiedAt: DateTime.now().add(const Duration(days: 7)));
    expect(await cache.load('shop', 'owner', 'job'), isNull);
  });

  test('anonymous actors never share cached profitability', () async {
    await cache.save('shop', '', 'job', verified);
    expect(await cache.load('shop', '', 'job'), isNull);
  });

  test('malformed stored value fails closed', () async {
    await cache.save('shop', 'owner', 'job', verified);
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getKeys().single;
    await prefs.setString(key, 'invalid-json');
    expect(await cache.load('shop', 'owner', 'job'), isNull);
  });
}
