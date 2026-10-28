import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/screens/jobs/job_quarantine_view_guard.dart';
import 'package:briskers_app/services/local_job_retirement.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Job retirement schema cannot deadlock across transaction contexts',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    final transactionEntered = Completer<void>();
    final continueTransaction = Completer<void>();

    final heldTransaction = db.transaction(() async {
      await db.customSelect('SELECT 1').get();
      transactionEntered.complete();
      await continueTransaction.future;
      await LocalJobRetirement.ensureSchema(db);
    });
    await transactionEntered.future;

    // A separate Job Detail access check is queued behind the open
    // transaction. In the b2484 implementation, its shared schema Future
    // was then awaited *inside* the held transaction, deadlocking both.
    final guardCheck =
        LocalJobRetirement.isJobBlocked(db, 'synthetic-shop', 'job-1');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    continueTransaction.complete();

    await heldTransaction.timeout(const Duration(seconds: 5));
    expect(await guardCheck.timeout(const Duration(seconds: 5)), isFalse);
    final sentinel = await db.customSelect(
      "SELECT 1 FROM sqlite_master WHERE type='trigger' "
      "AND name='retirement_accepted_no_change'",
    ).get();
    expect(sentinel, hasLength(1));
  });

  testWidgets('Job access gate renders after concurrent local write',
      (tester) async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    final transactionEntered = Completer<void>();
    final continueTransaction = Completer<void>();

    final heldTransaction = db.transaction(() async {
      await db.customSelect('SELECT 1').get();
      transactionEntered.complete();
      await continueTransaction.future;
      await LocalJobRetirement.ensureSchema(db);
    });
    await transactionEntered.future;

    await tester.pumpWidget(MaterialApp(
      home: JobQuarantineViewGuard(
        businessId: 'synthetic-shop',
        jobId: 'job-2',
        blockedLookup: () =>
            LocalJobRetirement.isJobBlocked(db, 'synthetic-shop', 'job-2'),
        quarantineEvents: const Stream.empty(),
        syncEvents: const Stream.empty(),
        onBlocked: () {},
        onRestored: () {},
        child: const Scaffold(body: Text('Authorized Job Detail')),
      ),
    ));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Authorized Job Detail'), findsNothing);

    await Future<void>.delayed(const Duration(milliseconds: 10));
    continueTransaction.complete();
    await heldTransaction.timeout(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Authorized Job Detail'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
