import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/employee_nickname_store.dart';

void main() {
  test('nickname survives store recreation in the same SQLite database',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final store = EmployeeNicknameStore(database: db);
      await store.save('shop-a', 'mechanic-one', 'Kam');
      expect(
        await EmployeeNicknameStore(database: db).get(
          'shop-a', 'mechanic-one',
        ),
        'Kam',
      );
      final employees = await store.decorate('shop-a', [
        {'id': 'mechanic-one', 'name': 'Kamerron Example', 'position_name': 'Mechanic'},
      ]);
      expect(employees.single['nickname'], 'Kam');
      expect(employees.single['name'], 'Kamerron Example');
      expect(EmployeeNicknameStore.displayName(employees.single), 'Kam');
    } finally {
      await db.close();
    }
  });

  test('business and employee identity stay isolated', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final store = EmployeeNicknameStore(database: db);
      await store.save('shop-a', 'mechanic-one', 'Chris');
      expect(await store.get('shop-b', 'mechanic-one'), isNull);
      expect(await store.get('shop-a', 'mechanic-two'), isNull);
    } finally {
      await db.close();
    }
  });

  test('clearing nickname preserves the employee legal name', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final store = EmployeeNicknameStore(database: db);
      await store.save('shop-a', 'mechanic-one', 'Chris');
      await store.save('shop-a', 'mechanic-one', '  ');
      final employees = await store.decorate('shop-a', [
        {'id': 'mechanic-one', 'name': 'Christopher Example'},
      ]);
      expect(employees.single.containsKey('nickname'), false);
      expect(EmployeeNicknameStore.displayName(employees.single),
          'Christopher Example');
    } finally {
      await db.close();
    }
  });

  test('rejects missing IDs and overlong nicknames', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final store = EmployeeNicknameStore(database: db);
      await expectLater(store.save('shop-a', '', 'Kam'), throwsArgumentError);
      await expectLater(store.save('shop-a', 'one', 'x' * 33),
          throwsArgumentError);
    } finally {
      await db.close();
    }
  });

  test('nickname survives closing and reopening its backing SQLite file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'briskers-nickname-reopen-',
    );
    final file = File('${directory.path}/shop.sqlite');
    try {
      final first = BriskersLocalDatabase(NativeDatabase(file));
      await EmployeeNicknameStore(database: first)
          .save('shop-a', 'employee-one', 'Kam');
      await first.close();

      final reopened = BriskersLocalDatabase(NativeDatabase(file));
      try {
        expect(
          await EmployeeNicknameStore(database: reopened)
              .get('shop-a', 'employee-one'),
          'Kam',
        );
      } finally {
        await reopened.close();
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('two employee aliases remain independent through local restart', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      final store = EmployeeNicknameStore(database: db);
      await store.save('shop-a', 'one', 'Chris');
      await store.save('shop-a', 'two', 'Kam');
      final saved = await EmployeeNicknameStore(database: db).all('shop-a');
      expect(saved, {'one': 'Chris', 'two': 'Kam'});
    } finally {
      await db.close();
    }
  });
}
