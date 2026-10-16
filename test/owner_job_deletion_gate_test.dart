import 'dart:io';

import 'package:briskers_app/screens/jobs/owner_job_deletion_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'legacy cleanup stays disabled while new workflow uses safe service',
    () {
      expect(OwnerJobDeletionGate.enabled, isFalse);
      final screen = File('lib/screens/jobs/job_detail_screen.dart')
          .readAsStringSync();
      final start = screen.indexOf('Future<void> _deleteUnusedJob()');
      final end = screen.indexOf('\n  Future<', start + 10);
      final deletion = screen.substring(start, end);
      expect(deletion, contains('if (!_owner || _busy) return;'));
      expect(deletion, contains('_jobRetirement.preview('));
      expect(deletion, contains('showOwnerJobDeleteV3Confirmation('));
      expect(deletion, contains('_jobRetirement.queueConfirmed('));
      expect(deletion, contains('supabase.auth.currentUser?.id != actorId'));
      expect(deletion, isNot(contains('_api.jobDeletionPlan(')));
      expect(deletion, isNot(contains('_api.deleteJobWithUnpaidInvoices(')));
      expect(screen, isNot(contains('_api.deleteJobWithUnpaidInvoices(')));
    },
  );

  testWidgets('blocked action explains preserved data without confirm-delete', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showOwnerJobDeletionUnavailable(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Job deletion unavailable'), findsOneWidget);
    expect(find.textContaining('Nothing has been deleted.'), findsOneWidget);
    expect(find.text('Confirm delete'), findsNothing);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
