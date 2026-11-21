import 'package:briskers_app/screens/jobs/owner_job_delete_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const snapshot = <String, dynamic>{
    'job_number': 'TEST-J-1',
    'invoices': [
      {'id': 'synthetic-invoice-1', 'number': 'TEST-I-1', 'status': 'draft'},
      {'id': 'synthetic-invoice-2', 'number': 'TEST-I-2', 'status': 'draft'},
    ],
    'estimates_preserved': [],
  };

  Future<void> open(
    WidgetTester tester, {
    bool eligible = true,
    bool offline = false,
    required void Function(bool) result,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result(
                await showOwnerJobDeleteConfirmation(
                  context,
                  snapshot: snapshot,
                  canRetire: eligible,
                  blockedReasons: eligible
                      ? const []
                      : const ['Finalized payment exists'],
                  offline: offline,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'one confirmation lists exact linked invoices and preserves numbers',
    (tester) async {
      bool? approved;
      await open(tester, result: (value) => approved = value);
      expect(find.text('2 linked invoice(s) to remove'), findsOneWidget);
      expect(find.textContaining('TEST-I-1'), findsOneWidget);
      expect(find.textContaining('TEST-I-2'), findsOneWidget);
      expect(
        find.textContaining('Document numbers will not be reused.'),
        findsOneWidget,
      );
      expect(find.text('Reclaim numbers'), findsNothing);
      await tester.tap(find.text('Delete Job'));
      await tester.pumpAndSettle();
      expect(approved, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Confirm delete'), findsNothing);
    },
  );

  testWidgets('cancel and back dismiss without consent', (tester) async {
    bool? approved;
    await open(tester, result: (value) => approved = value);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(approved, isFalse);
    approved = null;
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(approved, isFalse);
  });

  testWidgets('protected history has no destructive action', (tester) async {
    bool? approved;
    await open(tester, eligible: false, result: (value) => approved = value);
    expect(find.text('Finalized payment exists'), findsOneWidget);
    expect(find.text('Delete Job'), findsNothing);
    expect(find.text('Queue deletion'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(approved, isFalse);
  });

  testWidgets('offline confirmation describes pending revalidation honestly', (
    tester,
  ) async {
    bool? approved;
    await open(tester, offline: true, result: (value) => approved = value);
    expect(find.textContaining('last verified preview'), findsOneWidget);
    expect(find.text('Delete Job'), findsNothing);
    await tester.tap(find.text('Queue deletion'));
    await tester.pumpAndSettle();
    expect(approved, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
