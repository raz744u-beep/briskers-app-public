import 'dart:async';
import 'dart:io';
import 'package:briskers_app/core/payroll_payment_contract.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/screens/settings/payroll_drafts_screen.dart';
import 'package:briskers_app/screens/settings/payroll_receipts_screen.dart';
import 'package:briskers_app/services/local_payroll_draft_store.dart';
import 'package:briskers_app/services/local_payroll_method_store.dart';
import 'package:briskers_app/services/payroll_owner_session.dart';
import 'package:briskers_app/services/local_payroll_outbox.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'payroll_authoritative_sync_test.dart' as fixture;

class PostingCatalogGateway extends fixture.CatalogGateway
    implements PayrollPostingGateway, PayrollPostingActivation {
  @override
  bool get canQueueOffline => true;
  bool lost = false;
  int posts = 0;
  @override
  Future<String> registerMethod(PayrollPaymentMethod method) async =>
      fixture.pid(10);
  @override
  Future<void> prepare(Map<String, dynamic> payload) async {
    expect(payload['method_id'], fixture.pid(10));
  }

  @override
  Future<void> uploadAndVerifyProof(Map<String, dynamic> payload) async {}
  @override
  Future<PayrollPostingReceipt> post(Map<String, dynamic> payload) async {
    posts++;
    state['receipts'] = [
      {...payload, 'transaction_id': fixture.pid(80), 'status': 'posted'},
    ];
    if (!lost) {
      lost = true;
      throw const SocketException('Lost reply');
    }
    return PayrollPostingReceipt(
      businessId: fixture.pid(1),
      operationId: payload['operation_id'] as String,
      transactionId: fixture.pid(80),
      amountCents: payload['amount_cents'] as int,
    );
  }
}

void main() {
  testWidgets(
    'confirmed saved payment freezes on lost response and receipt retry removes NOT PAID',
    (tester) async {
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      final sync = fixture.service(db), gateway = PostingCatalogGateway();
      gateway.state['receipts'] = <dynamic>[];
      final session = PayrollOwnerSession(
        businessId: fixture.pid(1),
        isOwner: true,
        currentUserId: () => 'owner',
        userChanges: const Stream.empty(),
      );
      final queue = LocalPayrollOutbox(
        database: db,
        businessId: fixture.pid(1),
        ownerUserId: 'owner',
        isContextCurrent: () => true,
        verifyLocalProof: (_) async => true,
      );
      final drafts = LocalPayrollDraftStore(database: db);
      await drafts.save(
        isOwner: true,
        ownerUserId: 'owner',
        draft: PayrollPaymentDraft(
          businessId: fixture.pid(1),
          employeeId: fixture.pid(6),
          operationId: fixture.pid(70),
          methodId: fixture.pid(20),
          methodLabelSnapshot: 'Old Cash',
          amountCents: 12345,
          sourceAccountId: fixture.pid(7),
          paymentDate: DateTime(2026, 10, 23),
          payrollWeekKey: '2026-10-19',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PayrollDraftsScreen(
            businessId: fixture.pid(1),
            isOwner: true,
            ownerSession: session,
            employees: [
              {'id': fixture.pid(6), 'name': 'Synthetic Mechanic'},
            ],
            draftStore: drafts,
            methodStore: LocalPayrollMethodStore(database: db),
            loadSourceAccounts: () async => [
              {'id': fixture.pid(7), 'name': 'Synthetic bank'},
            ],
            authoritativeSync: sync,
            authoritativeGateway: gateway,
            outbox: queue,
            postingGateway: gateway,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Confirm payroll payment'));
      await tester.tap(find.byTooltip('Confirm payroll payment'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('USD 123.45 via Renamed Cash'),
        findsOneWidget,
      );
      await tester.tap(find.text('Confirm and queue'));
      await tester.pumpAndSettle();
      expect((await queue.statuses()).single['state'], 'queued');
      expect(find.byTooltip('Edit unpaid draft'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: PayrollReceiptsScreen(
            businessId: fixture.pid(1),
            isOwner: true,
            ownerSession: session,
            synchronizer: sync,
            gateway: gateway,
            outbox: queue,
            postingGateway: gateway,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect((await queue.statuses()).single['state'], 'posted');
      expect(gateway.posts, 2);
      expect(find.textContaining('Posted • 2026-10-23'), findsOneWidget);
      gateway.state['revision'] = 2;
      gateway.state['receipts'] = <dynamic>[];
      await tester.tap(find.byTooltip('Sync payroll'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Posted • 2026-10-23'), findsNothing);
      expect(
        find.text('No confirmed payroll receipts cached.'),
        findsOneWidget,
      );
      expect(gateway.posts, 2); // A removed receipt never re-posts its expense.

      await tester.pumpWidget(const SizedBox());
      session.dispose();
      await db.close();
    },
  );
  testWidgets(
    'receipt label never falls back to renamed method or source account',
    (tester) async {
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      final sync = fixture.service(db);
      final gateway = fixture.CatalogGateway()
        ..state = fixture.snapshot(historical: null);
      final session = PayrollOwnerSession(
        businessId: fixture.pid(1),
        isOwner: true,
        currentUserId: () => 'owner',
        userChanges: const Stream.empty(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PayrollReceiptsScreen(
            outbox: LocalPayrollOutbox(
              database: db,
              businessId: session.businessId,
              ownerUserId: session.ownerUserId!,
              isContextCurrent: () =>
                  session.allows(businessId: session.businessId, isOwner: true),
              verifyLocalProof: (_) async => false,
            ),
            businessId: fixture.pid(1),
            isOwner: true,
            ownerSession: session,
            synchronizer: sync,
            gateway: gateway,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Method: Not recorded'), findsOneWidget);
      expect(find.text('Renamed Cash'), findsOneWidget);
      expect(find.textContaining('Posted • 2026-10-23'), findsOneWidget);
      expect(gateway.applications, 0);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      await db.close();
    },
  );
  testWidgets(
    'pending settings do not create a paid receipt while gateway is closed',
    (tester) async {
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      final sync = fixture.service(db);
      final gateway = fixture.CatalogGateway();
      gateway.state['receipts'] = <dynamic>[];
      await sync.synchronize(gateway);
      await sync.queueMutation({
        'operation_id': fixture.pid(70),
        'action': 'default',
        'employee_id': fixture.pid(6),
        'method_id': fixture.pid(10),
      });
      gateway.available = false;
      final session = PayrollOwnerSession(
        businessId: fixture.pid(1),
        isOwner: true,
        currentUserId: () => 'owner',
        userChanges: const Stream.empty(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PayrollReceiptsScreen(
            outbox: LocalPayrollOutbox(
              database: db,
              businessId: session.businessId,
              ownerUserId: session.ownerUserId!,
              isContextCurrent: () =>
                  session.allows(businessId: session.businessId, isOwner: true),
              verifyLocalProof: (_) async => false,
            ),
            businessId: fixture.pid(1),
            isOwner: true,
            ownerSession: session,
            synchronizer: sync,
            gateway: gateway,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('NOT PAID'), findsOneWidget);
      expect(find.textContaining('1 pending settings changes'), findsOneWidget);
      expect(
        find.text('No confirmed payroll receipts cached.'),
        findsOneWidget,
      );
      expect(gateway.applications, 0);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      await db.close();
    },
  );
  testWidgets(
    'auth switch clears cached receipts and permanently revokes screen',
    (tester) async {
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      var actor = 'owner';
      final changes = StreamController<String?>.broadcast();
      final session = PayrollOwnerSession(
        businessId: fixture.pid(1),
        isOwner: true,
        currentUserId: () => actor,
        userChanges: changes.stream,
      );
      final sync = fixture.service(
        db,
        context: () =>
            session.allows(businessId: fixture.pid(1), isOwner: true),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PayrollReceiptsScreen(
            outbox: LocalPayrollOutbox(
              database: db,
              businessId: session.businessId,
              ownerUserId: session.ownerUserId!,
              isContextCurrent: () =>
                  session.allows(businessId: session.businessId, isOwner: true),
              verifyLocalProof: (_) async => false,
            ),
            businessId: fixture.pid(1),
            isOwner: true,
            ownerSession: session,
            synchronizer: sync,
            gateway: fixture.CatalogGateway(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Historical Check'), findsOneWidget);
      actor = 'other';
      changes.add(actor);
      await tester.pumpAndSettle();
      expect(find.textContaining('Historical Check'), findsNothing);
      expect(find.text('Owner sign-in required.'), findsOneWidget);
      actor = 'owner';
      changes.add(actor);
      await tester.pumpAndSettle();
      expect(find.textContaining('Historical Check'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      await changes.close();
      await db.close();
    },
  );
  testWidgets(
    'draft choices use confirmed defaults and stable registration keys',
    (tester) async {
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      final sync = fixture.service(db), gateway = fixture.CatalogGateway();
      final session = PayrollOwnerSession(
        businessId: fixture.pid(1),
        isOwner: true,
        currentUserId: () => 'owner',
        userChanges: const Stream.empty(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PayrollDraftsScreen(
            outbox: LocalPayrollOutbox(
              database: db,
              businessId: session.businessId,
              ownerUserId: session.ownerUserId!,
              isContextCurrent: () =>
                  session.allows(businessId: session.businessId, isOwner: true),
              verifyLocalProof: (_) async => false,
            ),
            businessId: fixture.pid(1),
            isOwner: true,
            employees: [
              {'id': fixture.pid(6), 'name': 'Synthetic Mechanic'},
            ],
            ownerSession: session,
            draftStore: LocalPayrollDraftStore(database: db),
            methodStore: LocalPayrollMethodStore(database: db),
            loadSourceAccounts: () async => [],
            authoritativeSync: sync,
            authoritativeGateway: gateway,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('New payroll draft'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('employee-null')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Synthetic Mechanic').last);
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('method-${fixture.pid(20)}')), findsOneWidget);
      expect(fixture.pid(20), isNot(fixture.pid(10)));
      expect(gateway.applications, 0);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      await db.close();
    },
  );
}
