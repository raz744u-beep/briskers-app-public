import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/employee_roster_cache.dart';

class _FakeEmployeesApi extends BriskersApi {
  List<Map<String,dynamic>> assignable = [
    {'id':'chris', 'name':'Chris', 'position_name':'Mechanic'},
    {'id':'kam', 'name':'Kamerron', 'position_name':'Mechanic'},
  ];
  List<Map<String,dynamic>> full = [
    {'id':'chris', 'name':'Chris', 'position':'Mechanic',
     'hourly_rate':40, 'ssn_last4':'1234', 'phone':'secret-phone', 'active':true},
    {'id':'old', 'name':'Former Employee', 'position':'Mechanic',
     'hourly_rate':50, 'ssn_last4':'9999', 'active':false},
  ];
  bool failAssignable = false;
  bool failSettings = false;

  @override
  Future<List<Map<String,dynamic>>> assignableEmployees(String businessId) async {
    if (failAssignable) throw StateError('offline');
    return assignable;
  }
  @override
  Future<List<Map<String,dynamic>>> employeesSettings(String businessId) async {
    if (failSettings) throw StateError('offline');
    return full;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('only safe fields are stored, never compensation/SSN/contact data', () async {
    SharedPreferences.setMockInitialValues({});
    final api = _FakeEmployeesApi();
    final cache = EmployeeRosterCache(
      api: api, actorId: () => 'owner', forceOffline: () => false);
    await cache.refreshSettings('shop');
    final settings = await cache.cachedSettings('shop');
    final assignable = await cache.cachedAssignable('shop');
    expect(settings!.rows.length, 2);
    expect(assignable!.rows.map((r) => r['id']), ['chris']);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getKeys()
        .where((k) => k.contains('briskers_safe_employee_roster'))
        .map((k) => prefs.getString(k) ?? '').join(' ');
    expect(raw, isNot(contains('ssn')));
    expect(raw, isNot(contains('1234')));
    expect(raw, isNot(contains('hourly_rate')));
    expect(raw, isNot(contains('secret-phone')));
    expect(raw, isNot(contains('9999')));
  });

  test('different user or shop cannot read saved roster', () async {
    SharedPreferences.setMockInitialValues({});
    final api = _FakeEmployeesApi();
    final owner = EmployeeRosterCache(
      api:api, actorId:()=> 'owner',forceOffline:()=>false);
    await owner.refreshAssignable('shopA');
    expect((await owner.cachedAssignable('shopA'))!.rows.length, 2);
    final secretary = EmployeeRosterCache(
      api:api,actorId:()=> 'secretary',forceOffline:()=>true);
    expect(await secretary.cachedAssignable('shopA'), isNull);
    expect(await owner.cachedAssignable('shopB'), isNull);
    expect(await EmployeeRosterCache(
      api:api,actorId:()=>null,forceOffline:()=>true).cachedAssignable('shopA'),
      isNull);
  });

  test('server refresh replaces old roster and network failure retains last snapshot', () async {
    SharedPreferences.setMockInitialValues({});
    final api = _FakeEmployeesApi();
    final cache = EmployeeRosterCache(
      api:api,actorId:()=> 'owner',forceOffline:()=>false);
    await cache.refreshAssignable('shop');
    api.assignable = [
      {'id':'new', 'name':'New Mechanic', 'position_name':'Mechanic'},
    ];
    final rows = await cache.refreshAssignable('shop');
    expect(rows.map((r)=>r['id']),['new']);
    api.failAssignable = true;
    await expectLater(cache.refreshAssignable('shop'),throwsStateError);
    expect((await cache.cachedAssignable('shop'))!.rows.single['id'],'new');
    await cache.invalidate('shop');
    expect(await cache.cachedAssignable('shop'),isNull);
    expect(await cache.cachedSettings('shop'),isNull);
  });

  test('true server empty is distinguishable from unbootstrapped offline cache', () async {
    SharedPreferences.setMockInitialValues({});
    final api=_FakeEmployeesApi()..assignable=[];
    final cache=EmployeeRosterCache(
      api:api,actorId:()=> 'owner',forceOffline:()=>false);
    expect(await cache.cachedAssignable('shop'),isNull);
    await cache.refreshAssignable('shop');
    expect((await cache.cachedAssignable('shop'))!.rows,isEmpty);
  });

  test('force offline does not request fresh server employee records', () async {
    SharedPreferences.setMockInitialValues({});
    final api=_FakeEmployeesApi();
    final cache=EmployeeRosterCache(
      api:api,actorId:()=> 'owner',forceOffline:()=>true);
    await expectLater(cache.refreshSettings('shop'),throwsStateError);
    await expectLater(cache.refreshAssignable('shop'),throwsStateError);
    expect(await cache.cachedAssignable('shop'),isNull);
  });
  test('local actor roster remains available after switching Force Offline', () async {
    SharedPreferences.setMockInitialValues({});
    final api = _FakeEmployeesApi();
    final online = EmployeeRosterCache(
      api: api, actorId: () => 'same-local-user',
      forceOffline: () => false,
    );
    await online.refreshSettings('shop');
    final offline = EmployeeRosterCache(
      api: api, actorId: () => 'same-local-user',
      forceOffline: () => true,
    );
    final saved = await offline.cachedSettings('shop');
    expect(saved, isNotNull);
    expect(saved!.rows.map((r) => r['name']),
        containsAll(['Chris', 'Former Employee']));
    expect(saved.rows.first.keys.toSet(),
        {'id', 'name', 'position_name', 'active'});
    await expectLater(offline.refreshSettings('shop'), throwsStateError);
    expect((await offline.cachedAssignable('shop'))!.rows,
        hasLength(1));
  });

  test('a session accessor exception yields a cache miss, never an uncaught read error', () async {
    SharedPreferences.setMockInitialValues({});
    final brokenSession = EmployeeRosterCache(
      api: _FakeEmployeesApi(),
      actorId: () => throw StateError('Session temporarily unavailable'),
      forceOffline: () => true,
    );
    expect(await brokenSession.cachedSettings('shop'), isNull);
    expect(await brokenSession.cachedAssignable('shop'), isNull);
  });

}
