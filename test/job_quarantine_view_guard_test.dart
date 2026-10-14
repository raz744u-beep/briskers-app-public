import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/screens/jobs/job_quarantine_view_guard.dart';

void main() {
  testWidgets('revocation hides detail and dismisses its open modal', (tester) async {
    final events = StreamController<({String businessId, Set<String> jobIds})>.broadcast(sync: true);
    final sync = StreamController<String>.broadcast(sync: true);
    var blocked = false;
    var invalidations = 0;
    var restorations = 0;
    await tester.pumpWidget(MaterialApp(home: JobQuarantineViewGuard(
      businessId: 'business', jobId: 'job',
      blockedLookup: () async => blocked,
      quarantineEvents: events.stream, syncEvents: sync.stream,
      onBlocked: () => invalidations++, onRestored: () => restorations++,
      child: Scaffold(body: Builder(builder: (context) => Column(children: [
        const Text('Private job notes'),
        TextButton(onPressed: () => showDialog<void>(context: context,
          builder: (_) => const AlertDialog(content: Text('Private finding photo')),
        ), child: const Text('Open finding')),
      ]))),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open finding'));
    await tester.pumpAndSettle();
    expect(find.text('Private finding photo'), findsOneWidget);
    events.add((businessId: 'other', jobIds: {'job'}));
    await tester.pump();
    expect(invalidations, 0);
    blocked = true;
    events.add((businessId: 'business', jobIds: {'job'}));
    await tester.pumpAndSettle();
    expect(find.text('Private finding photo'), findsNothing);
    expect(find.text('Private job notes'), findsNothing);
    expect(invalidations, 1);
    sync.add('business');
    await tester.pumpAndSettle();
    expect(restorations, 0);
    blocked = false; // Only a verified fresh JobSync bundle clears durable state.
    sync.add('business');
    await tester.pumpAndSettle();
    expect(restorations, 1);
    await tester.pumpWidget(const SizedBox());
    await events.close();
    await sync.close();
  });

  testWidgets('stale initial lookup cannot reveal content after revocation', (tester) async {
    final events = StreamController<({String businessId, Set<String> jobIds})>.broadcast(sync: true);
    final sync = StreamController<String>.broadcast(sync: true);
    final lookup = Completer<bool>();
    await tester.pumpWidget(MaterialApp(home: JobQuarantineViewGuard(
      businessId: 'business', jobId: 'job',
      blockedLookup: () => lookup.future,
      quarantineEvents: events.stream, syncEvents: sync.stream,
      onBlocked: () {}, onRestored: () {},
      child: const Text('Sensitive cached detail'),
    )));
    expect(find.text('Sensitive cached detail'), findsNothing);
    events.add((businessId: 'business', jobIds: {'job'}));
    lookup.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('Sensitive cached detail'), findsNothing);
    expect(find.textContaining('Saved local work is preserved'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await events.close();
    await sync.close();
  });

  testWidgets('durable block on reopened route never paints cached content', (tester) async {
    var invalidated = false;
    await tester.pumpWidget(MaterialApp(home: JobQuarantineViewGuard(
      businessId: 'business', jobId: 'job',
      blockedLookup: () async => true,
      quarantineEvents: const Stream.empty(), syncEvents: const Stream.empty(),
      onBlocked: () => invalidated = true, onRestored: () {},
      child: const Text('Old cached detail'),
    )));
    expect(find.text('Old cached detail'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('Old cached detail'), findsNothing);
    expect(invalidated, isTrue);
  });
}
