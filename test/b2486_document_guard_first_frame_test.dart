import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/screens/jobs/job_quarantine_view_guard.dart';
import 'package:briskers_app/services/local_job_retirement.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('One-document retirement check preserves exact and linked tombstones',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await LocalJobRetirement.ensureSchema(db);
    await db.customStatement(
      "INSERT INTO local_documents(id,business_id,kind,job_id) "
      "VALUES ('invoice-a','shop-a','invoice','job-a'),"
      "('estimate-a','shop-a','estimate','job-a'),"
      "('invoice-b','shop-a','invoice','job-b'),"
      "('invoice-other','shop-b','invoice','job-a')",
    );

    for (final id in ['invoice-a', 'estimate-a', 'invoice-b']) {
      expect(await LocalJobRetirement.isDocumentBlocked(db, 'shop-a', id),
          isFalse);
    }
    await db.transaction(() async {
      await LocalJobRetirement.recordEntity(db,
        businessId: 'shop-a', jobId: 'job-a', entityKind: 'job',
        entityId: 'job-a', operationId: 'op-1', state: 'pending');
      await LocalJobRetirement.recordEntity(db,
        businessId: 'shop-a', jobId: 'job-b', entityKind: 'invoice',
        entityId: 'invoice-b', operationId: 'op-2', state: 'accepted');
      // Exact invoice tombstone must apply even before its index row exists.
      await LocalJobRetirement.recordEntity(db,
        businessId: 'shop-a', jobId: 'job-c', entityKind: 'invoice',
        entityId: 'invoice-not-indexed', operationId: 'op-3',
        state: 'locally_cancelled');
    });

    expect(await LocalJobRetirement.isDocumentBlocked(db, 'shop-a',
        'invoice-a'), isTrue);
    expect(await LocalJobRetirement.isDocumentBlocked(db, 'shop-a',
        'invoice-b'), isTrue);
    expect(await LocalJobRetirement.isDocumentBlocked(db, 'shop-a',
        'invoice-not-indexed'), isTrue);
    // Estimates linked to a retired Job remain separate documents.
    expect(await LocalJobRetirement.isDocumentBlocked(db, 'shop-a',
        'estimate-a'), isFalse);
    expect(await LocalJobRetirement.isDocumentBlocked(db, 'shop-b',
        'invoice-other'), isFalse);
    expect(await LocalJobRetirement.isDocumentBlocked(db, 'shop-a',
        'invoice-no-tombstone'), isFalse);
  });

  testWidgets('Job sync notification never restarts the Document route gate',
      (tester) async {
    final sync = StreamController<String>.broadcast(sync: true);
    addTearDown(sync.close);
    var checks = 0;
    await tester.pumpWidget(MaterialApp(
      home: JobQuarantineViewGuard(
        businessId: 'shop-a',
        jobId: '',
        documentId: 'invoice-a',
        blockedLookup: () async {
          checks++;
          return false;
        },
        quarantineEvents: const Stream.empty(),
        syncEvents: sync.stream,
        onBlocked: () {},
        onRestored: () {},
        child: const Scaffold(body: Text('Invoice Detail Ready')),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Invoice Detail Ready'), findsOneWidget);
    expect(checks, 1);
    sync.add('shop-a');
    sync.add('shop-a');
    await tester.pumpAndSettle();
    expect(find.text('Invoice Detail Ready'), findsOneWidget);
    expect(checks, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
