import 'dart:async';

import 'package:briskers_app/core/payroll_payment_contract.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/screens/settings/payroll_drafts_screen.dart';
import 'package:briskers_app/services/local_payroll_draft_store.dart';
import 'package:briskers_app/services/local_payroll_method_store.dart';
import 'package:briskers_app/services/payroll_owner_session.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PayrollPaymentDraft fixture() => PayrollPaymentDraft(
  businessId: 'shop',
  employeeId: 'employee',
  operationId: 'op',
  methodId: 'old-unknown-method',
  methodLabelSnapshot: 'Historical Check',
  amountCents: 50000,
  paymentDate: DateTime(2026, 10, 23),
  payrollWeekKey: '2026-10-19',
  sourceAccountId: 'bank',
  reference: '123',
);

class DelayedDrafts extends LocalPayrollDraftStore {
  DelayedDrafts(BriskersLocalDatabase db) : super(database: db);
  final response = Completer<List<PayrollPaymentDraft>>();
  @override
  Future<List<PayrollPaymentDraft>> load({
    required bool isOwner,
    required String businessId,
    required String ownerUserId,
  }) => response.future;
}

void main() {
  test('proof must match every payment term, not only the method', () {
    final d = fixture();
    bool matches({
      String? shop,
      String? employee,
      String? operation,
      String? method,
      int? amount,
      DateTime? date,
      String? week,
      String? account,
      String? reference,
    }) => d.proofMatchesTerms(
      businessId: shop ?? d.businessId,
      employeeId: employee ?? d.employeeId,
      operationId: operation ?? d.operationId,
      methodId: method ?? d.methodId,
      amountCents: amount ?? d.amountCents,
      paymentDate: date ?? d.paymentDate,
      payrollWeekKey: week ?? d.payrollWeekKey,
      sourceAccountId: account ?? d.sourceAccountId,
      reference: reference ?? d.reference,
    );
    expect(matches(), true);
    for (final result in [
      matches(shop: 'other'),
      matches(employee: 'other'),
      matches(operation: 'other'),
      matches(method: 'other'),
      matches(amount: 50001),
      matches(date: DateTime(2026, 10, 24)),
      matches(week: 'other'),
      matches(account: 'other'),
      matches(reference: '124'),
    ]) {
      expect(result, false);
    }
  });

  test('A to B to A does not reactivate revoked route', () async {
    var actor = 'owner-a';
    final changes = StreamController<String?>.broadcast(sync: true);
    final session = PayrollOwnerSession(
      businessId: 'shop',
      isOwner: true,
      currentUserId: () => actor,
      userChanges: changes.stream,
    );
    expect(session.allows(businessId: 'shop', isOwner: true), true);
    actor = 'owner-b';
    changes.add(actor);
    actor = 'owner-a';
    changes.add(actor);
    expect(session.allows(businessId: 'shop', isOwner: true), false);
    session.dispose();
    await changes.close();
  });

  testWidgets(
    'late load cannot display previous Owner drafts after auth switch',
    (tester) async {
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      final drafts = DelayedDrafts(db);
      var actor = 'owner-a';
      final changes = StreamController<String?>.broadcast(sync: true);
      final session = PayrollOwnerSession(
        businessId: 'shop',
        isOwner: true,
        currentUserId: () => actor,
        userChanges: changes.stream,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PayrollDraftsScreen(
            businessId: 'shop',
            isOwner: true,
            employees: const [
              {'id': 'employee', 'name': 'Private Employee'},
            ],
            ownerSession: session,
            draftStore: drafts,
            methodStore: LocalPayrollMethodStore(database: db),
          ),
        ),
      );
      actor = 'owner-b';
      changes.add(actor);
      await tester.pump();
      drafts.response.complete([fixture()]);
      await tester.pumpAndSettle();
      expect(find.text('Private Employee'), findsNothing);
      expect(find.text('Owner sign-in required.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      await changes.close();
      await db.close();
    },
  );

  testWidgets(
    'auth switch dismisses confirmation without discarding old Owner draft',
    (tester) async {
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      final drafts = LocalPayrollDraftStore(database: db);
      await drafts.save(
        isOwner: true,
        ownerUserId: 'owner-a',
        draft: fixture(),
      );
      var actor = 'owner-a';
      final changes = StreamController<String?>.broadcast(sync: true);
      final session = PayrollOwnerSession(
        businessId: 'shop',
        isOwner: true,
        currentUserId: () => actor,
        userChanges: changes.stream,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PayrollDraftsScreen(
            businessId: 'shop',
            isOwner: true,
            employees: const [
              {'id': 'employee', 'name': 'Private Employee'},
            ],
            ownerSession: session,
            draftStore: drafts,
            methodStore: LocalPayrollMethodStore(database: db),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Discard unpaid draft'));
      await tester.pumpAndSettle();
      expect(find.text('Discard unpaid draft?'), findsOneWidget);
      actor = 'owner-b';
      changes.add(actor);
      await tester.pumpAndSettle();
      expect(find.text('Discard unpaid draft?'), findsNothing);
      expect(find.text('Private Employee'), findsNothing);
      expect(
        (await drafts.load(
          isOwner: true,
          businessId: 'shop',
          ownerUserId: 'owner-a',
        )),
        hasLength(1),
      );
      expect(
        await drafts.load(
          isOwner: true,
          businessId: 'shop',
          ownerUserId: 'owner-b',
        ),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      await changes.close();
      await db.close();
    },
  );

  testWidgets('unknown method does not synthesize Cash or crash dropdown', (
    tester,
  ) async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final drafts = LocalPayrollDraftStore(database: db);
    await drafts.save(isOwner: true, ownerUserId: 'owner', draft: fixture());
    final session = PayrollOwnerSession(
      businessId: 'shop',
      isOwner: true,
      currentUserId: () => 'owner',
      userChanges: const Stream.empty(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PayrollDraftsScreen(
          businessId: 'shop',
          isOwner: true,
          employees: const [
            {'id': 'employee', 'name': 'Private Employee'},
          ],
          ownerSession: session,
          draftStore: drafts,
          methodStore: LocalPayrollMethodStore(database: db),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit unpaid draft'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.text(
        'Choose a method. Unavailable or older draft choices are never inferred.',
      ),
      findsOneWidget,
    );
    expect(
      (await drafts.load(
        isOwner: true,
        businessId: 'shop',
        ownerUserId: 'owner',
      )).single.sourceAccountId,
      'bank',
    );
    await tester.pumpWidget(const SizedBox());
    session.dispose();
    await db.close();
  });
}
