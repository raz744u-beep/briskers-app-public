import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/payroll_expense_link_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BriskersLocalDatabase db;
  late PayrollExpenseLinkStore links;

  setUp(() {
    db = BriskersLocalDatabase(NativeDatabase.memory());
    links = PayrollExpenseLinkStore(db);
  });

  tearDown(() async => db.close());

  test('link survives local-to-server transaction ID remap', () async {
    await links.link('shop', 'payment-1', 'local-transaction-1');
    expect(
      await links.transactionId('shop', 'payment-1'),
      'local-transaction-1',
    );
    await links.remap('shop', 'local-transaction-1', 'server-transaction-1');
    expect(
      await links.transactionId('shop', 'payment-1'),
      'server-transaction-1',
    );
    await links.link('shop', 'payment-1', 'server-transaction-1');
    expect(
      await links.transactionId('shop', 'payment-1'),
      'server-transaction-1',
    );
  });

  test(
    'different transaction for same payroll operation fails closed',
    () async {
      await links.link('shop', 'payment-1', 'expense-1');
      await expectLater(
        links.link('shop', 'payment-1', 'expense-2'),
        throwsStateError,
      );
      expect(await links.transactionId('shop', 'payment-1'), 'expense-1');
    },
  );

  test('same expense cannot be linked to a second payroll operation', () async {
    await links.link('shop', 'payment-1', 'expense-1');
    await expectLater(
      links.link('shop', 'payment-2', 'expense-1'),
      throwsStateError,
    );
    expect(await links.transactionId('shop', 'payment-2'), isNull);
  });

  test('business scopes are isolated', () async {
    await links.link('shop-1', 'payment-1', 'expense-1');
    expect(await links.transactionId('shop-2', 'payment-1'), isNull);
    await links.link('shop-2', 'payment-1', 'expense-1');
    expect(await links.transactionId('shop-2', 'payment-1'), 'expense-1');
  });
}
