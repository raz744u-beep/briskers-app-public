import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/screens/jobs/invoice_deletion_choice.dart';

void main() {
  testWidgets('legacy eligible plan cannot bypass the whole-Job safety gate', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showInvoiceDeletionChoice(
                  context,
                  invoiceNumber: 'TEST-INV-002',
                  jobPlan: {
                    'job_number': 'TEST-JOB-001',
                    'can_delete': true,
                    'invoices': [
                      {'number': 'TEST-INV-001'},
                      {'number': 'TEST-INV-002'},
                    ],
                    'estimates_preserved': [
                      {'number': 'TEST-EST-001'},
                    ],
                  },
                );
              },
              child: const Text('Open choice'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open choice'));
    await tester.pumpAndSettle();
    expect(find.text('Delete invoice only'), findsOneWidget);
    expect(find.text('Delete invoice and Job'), findsNothing);
    expect(find.textContaining('The Job will be kept.'), findsOneWidget);
    await tester.tap(find.text('Delete invoice only'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm delete'), findsOneWidget);
    expect(result, isNull);
    await tester.tap(find.text('Confirm delete'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('paid sibling blocks whole-Job option but keeps invoice-only', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showInvoiceDeletionChoice(
                  context,
                  invoiceNumber: 'TEST-INV-002',
                  jobPlan: {
                    'job_number': 'TEST-JOB-001',
                    'can_delete': false,
                    'reason': 'A linked invoice has payment activity',
                    'invoices': [],
                  },
                );
              },
              child: const Text('Open choice'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open choice'));
    await tester.pumpAndSettle();
    expect(find.text('Delete invoice and Job'), findsNothing);
    expect(find.textContaining('payment activity'), findsOneWidget);
    await tester.tap(find.text('Delete invoice only'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm delete'), findsOneWidget);
    expect(result, isNull);
    await tester.tap(find.text('Confirm delete'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}
