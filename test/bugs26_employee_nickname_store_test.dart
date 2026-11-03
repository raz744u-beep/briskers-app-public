import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/services/employee_nickname_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('nickname is separate from the legal name and survives store recreation', () async {
    final store = EmployeeNicknameStore();
    await store.save('shop-a', 'mechanic-one', 'Kam');
    expect(await EmployeeNicknameStore().get('shop-a', 'mechanic-one'), 'Kam');
    final employees = await store.decorate('shop-a', [
      {'id': 'mechanic-one', 'name': 'Kamerron Example', 'position_name': 'Mechanic'},
    ]);
    expect(employees.single['nickname'], 'Kam');
    expect(employees.single['name'], 'Kamerron Example');
    expect(EmployeeNicknameStore.displayName(employees.single), 'Kam');
  });

  test('shop and employee IDs cannot leak nicknames to another shop', () async {
    final store = EmployeeNicknameStore();
    await store.save('shop-a', 'mechanic-one', 'Chris');
    expect(await store.get('shop-b', 'mechanic-one'), isNull);
    expect(await store.get('shop-a', 'mechanic-two'), isNull);
  });

  test('clearing alias leaves full name unchanged', () async {
    final store = EmployeeNicknameStore();
    await store.save('shop-a', 'mechanic-one', 'Chris');
    await store.save('shop-a', 'mechanic-one', ' ');
    final employees = await store.decorate('shop-a', [
      {'id': 'mechanic-one', 'name': 'Christopher Example'},
    ]);
    expect(employees.single.containsKey('nickname'), false);
    expect(EmployeeNicknameStore.displayName(employees.single), 'Christopher Example');
  });

  test('rejects missing employee IDs and names that exceed 32 characters', () async {
    final store = EmployeeNicknameStore();
    await expectLater(store.save('shop-a', '', 'Kam'), throwsArgumentError);
    await expectLater(store.save('shop-a', 'one', 'x' * 33), throwsArgumentError);
  });
}
