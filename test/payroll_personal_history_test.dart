import 'dart:async';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/payroll_personal_history.dart';
import 'package:briskers_app/screens/settings/payroll_access_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'payroll_authoritative_sync_test.dart' as fixture;

class RoleGateway implements PayrollRoleGateway {
  String actor = 'mechanic';
  bool manage = false;
  @override
  Future<Map<String, dynamic>> fetchAccess(String shop) async => {
    'enabled': true,
    'business_id': shop,
    'actor_id': actor,
    'can_manage': manage,
  };
  @override
  Future<Map<String, dynamic>> fetchOwnHistory(String shop) async => {
    'business_id': shop,
    'actor_id': actor,
    'receipts': [
      {
        'transaction_id': fixture.pid(30),
        'amount_cents': 12345,
        'payment_date': '2026-10-23',
        'status': 'posted',
        'method_label': null,
        'currency_code': 'USD',
        'source_account_id': 'MUST NOT CACHE',
        'proof_url': 'MUST NOT CACHE',
        'company_total': 99999,
      },
    ],
  };
}

void main() {
  test(
    'own history caches only safe projection and rejects another actor',
    () async {
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      final gateway = RoleGateway();
      var current = true;
      final history = PayrollPersonalHistory(
        database: db,
        businessId: fixture.pid(1),
        actorId: 'mechanic',
        isCurrent: () => current,
      );
      try {
        await history.refresh(gateway);
        final rows = await history.read();
        expect(
          rows.single.keys,
          unorderedEquals([
            'transaction_id',
            'amount_cents',
            'payment_date',
            'status',
            'method_label',
            'currency_code',
          ]),
        );
        gateway.actor = 'other';
        await expectLater(history.refresh(gateway), throwsStateError);
        expect((await history.read()).single['amount_cents'], 12345);
        final other = PayrollPersonalHistory(
          database: db,
          businessId: fixture.pid(1),
          actorId: 'other',
          isCurrent: () => true,
        );
        expect(await other.read(), isEmpty);
        current = false;
        await expectLater(history.read(), throwsStateError);
      } finally {
        await db.close();
      }
    },
  );
  testWidgets(
    'mechanic cannot open management and auth switch clears own history',
    (tester) async {
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      final changes = StreamController<String?>.broadcast();
      var actor = 'mechanic';
      final history = PayrollPersonalHistory(
        database: db,
        businessId: fixture.pid(1),
        actorId: actor,
        isCurrent: () => actor == 'mechanic',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PayrollAccessScreen(
            businessId: fixture.pid(1),
            gateway: RoleGateway(),
            history: history,
            currentUserId: () => actor,
            userChanges: changes.stream,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('USD 123.45'), findsOneWidget);
      expect(find.text('Manage payroll'), findsNothing);
      expect(find.textContaining('Not recorded'), findsOneWidget);
      actor = 'other';
      changes.add(actor);
      await tester.pumpAndSettle();
      expect(find.text('USD 123.45'), findsNothing);
      actor = 'mechanic';
      changes.add(actor);
      await tester.pumpAndSettle();
      expect(find.text('USD 123.45'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await changes.close();
      await db.close();
    },
  );
  testWidgets('only server-confirmed office grant displays management action', (
    tester,
  ) async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final gateway = RoleGateway()
      ..actor = 'office'
      ..manage = true;
    final history = PayrollPersonalHistory(
      database: db,
      businessId: fixture.pid(1),
      actorId: 'office',
      isCurrent: () => true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PayrollAccessScreen(
          businessId: fixture.pid(1),
          gateway: gateway,
          history: history,
          currentUserId: () => 'office',
          userChanges: const Stream.empty(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Manage payroll'), findsOneWidget);
    gateway.manage = false;
    await tester.tap(find.text('Manage payroll'));
    await tester.pumpAndSettle();
    expect(find.text('Manage payroll'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await db.close();
  });
}
