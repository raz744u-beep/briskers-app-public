import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:briskers_app/local/local_database_provider.dart';
import 'package:briskers_app/screens/expenses/expense_entry_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/services/local_owner_authorization.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart'
    show BriskersLocalDatabase;
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:briskers_app/services/offline_financial_write_service.dart';

class _Enrollment implements OwnerEnrollmentStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BriskersLocalDatabase db;
  late LocalFinancialCache cache;

  setUp(() {
    db = BriskersLocalDatabase(NativeDatabase.memory());
    cache = LocalFinancialCache(database: db);
  });
  tearDown(() async => db.close());

  test('complete historical expense remains available for editing', () async {
    await cache.saveTransactionDetail('shop', 'old-payment', {
      'id': 'old-payment',
      'amount': 700,
      'date': '2026-10-23',
      'account_id': 'capital-one',
      'category_id': 'payroll',
      'counterparty': 'Chris',
      'attachments': [
        {'id': 'receipt-1'},
      ],
    });
    final record = await cache.loadTransactionForEdit('shop', 'old-payment');
    expect(record?['amount'], 700);
    expect(record?['date'], '2026-10-23');
    expect(record?['attachments'], hasLength(1));
  });

  test('summary-only cache cannot open a blank edit form', () async {
    await cache.saveTransactionDetail('shop', 'old-payment', {
      'id': 'old-payment',
      'amount': 700,
      'date': '2026-10-23',
    });
    expect(await cache.loadTransactionForEdit('shop', 'old-payment'), isNull);
  });

  test('missing historical date cannot silently become today', () async {
    await cache.saveTransactionDetail('shop', 'old-payment', {
      'id': 'old-payment',
      'amount': 700,
      'account_id': 'capital-one',
      'category_id': 'payroll',
    });
    expect(await cache.loadTransactionForEdit('shop', 'old-payment'), isNull);
  });

  test(
    'offline update rejects missing original without creating sync work',
    () async {
      final service = OfflineFinancialWriteService(database: db, cache: cache);
      await expectLater(
        service.updateLocalTransaction(
          'shop',
          'old-payment',
          direction: 'expense',
          accountId: 'business-checking',
          accountName: 'Business Checking',
          categoryId: 'payroll',
          categoryName: 'Payroll',
          amount: 700,
          date: DateTime(2026, 10, 23),
        ),
        throwsStateError,
      );
      expect(await cache.loadTransactionDetail('shop', 'old-payment'), isNull);
      final rows = await db
          .customSelect(
            "SELECT id FROM sync_outbox WHERE business_id = 'shop' AND entity_id = 'old-payment'",
          )
          .get();
      expect(rows, isEmpty);
    },
  );

  test(
    'account-only offline correction preserves expense and receipt identity',
    () async {
      await cache.saveTransactionDetail('shop', 'old-payment', {
        'id': 'old-payment',
        'direction': 'expense',
        'amount': 700,
        'date': '2026-10-23',
        'account_id': 'capital-one',
        'account': 'Capital One',
        'category_id': 'payroll',
        'category': 'Payroll',
        'counterparty': 'Chris',
        'remarks': 'Historical payroll',
        'attachments': [
          {'id': 'receipt-1'},
        ],
        'payroll_payment_id': 'payroll-123',
      });
      await cache.saveOptions('shop', {
        'accounts': [
          {'id': 'business-checking', 'name': 'Business Checking - 9858'},
        ],
      });
      const identity = OwnerSessionIdentity('owner', 'session');
      final authority = LocalOwnerAuthorization(
        store: _Enrollment(),
        currentIdentity: () => identity,
        verifyOwner: (_) => throw StateError('Network must not be used'),
        verifyLocalOwner: (business) async =>
            VerifiedOwnerEnrollment(identity, business),
        authenticateDevice: () =>
            throw StateError('An extra login must not be required'),
      );
      SharedPreferences.setMockInitialValues({});
      final connection = BriskersConnectionModeController.instance;
      await connection.setMode(BriskersConnectionMode.offline);
      addTearDown(() => connection.setMode(BriskersConnectionMode.auto));
      final service = OfflineFinancialWriteService(database: db, cache: cache);
      final grant = await authority.authorizeSession('shop');
      await service.updatePayrollExpenseAccount(
        'shop',
        'old-payment',
        expectedAccountId: 'capital-one',
        accountId: 'business-checking',
        grant: grant,
      );
      await service.flush('shop');
      final updated = (await cache.loadTransactionDetail(
        'shop',
        'old-payment',
      ))!;
      authority.lock();
      await expectLater(
        service.updatePayrollExpenseAccount(
          'shop',
          'old-payment',
          expectedAccountId: 'business-checking',
          accountId: 'capital-one',
          grant: grant,
        ),
        throwsStateError,
      );
      expect(updated['id'], 'old-payment');
      expect(updated['account_id'], 'business-checking');
      expect(updated['amount'], 700);
      expect(updated['date'], '2026-10-23');
      expect(updated['attachments'], hasLength(1));
      expect(updated['payroll_payment_id'], 'payroll-123');
      final queued = await db
          .customSelect(
            "SELECT entity_type, entity_id, payload_json FROM sync_outbox WHERE business_id = 'shop' AND entity_id = 'old-payment'",
          )
          .get();
      expect(queued, hasLength(1));
      expect(queued.single.read<String>('entity_type'), 'financial_update');
      expect(jsonDecode(queued.single.read<String>('payload_json')), {
        'transaction_id': 'old-payment',
        'payroll_account_only': true,
        'expected_account_id': 'capital-one',
        'account_id': 'business-checking',
      });
    },
  );

  test('mismatched transaction identity cannot be edited', () async {
    await expectLater(
      cache.saveTransactionDetail('shop', 'old-payment', {
        'id': 'another-payment',
        'amount': 700,
        'date': '2026-10-23',
        'account_id': 'capital-one',
        'category_id': 'payroll',
      }),
      throwsArgumentError,
    );
    expect(await cache.loadTransactionForEdit('shop', 'old-payment'), isNull);
  });
  testWidgets(
    'an unavailable original shows an explanation instead of an edit form',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      debugUseLocalDatabase(db);
      addTearDown(() => debugUseLocalDatabase(null));
      final connection = BriskersConnectionModeController.instance;
      await connection.setMode(BriskersConnectionMode.offline);
      addTearDown(() => connection.setMode(BriskersConnectionMode.auto));

      await tester.runAsync(
        () => cache.saveOptions('shop', {
          'accounts': [
            {'id': 'checking', 'name': 'Checking'},
          ],
          'categories': [
            {'id': 'payroll', 'name': 'Payroll'},
          ],
        }),
      );
      for (final copy in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            home: ExpenseEntryScreen(
              key: ValueKey(copy),
              businessId: 'shop',
              editTransactionId: copy ? null : 'unavailable',
              copyTransactionId: copy ? 'unavailable' : null,
            ),
          ),
        );
        final message = find.text(
          'The original expense details are unavailable on this device.',
        );
        for (var n = 0; n < 25 && message.evaluate().isEmpty; n++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(message, findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(FilledButton), findsNothing);
      }
    },
  );
}
