import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/screens/jobs/invoice_deletion_choice.dart';

void main() {
  testWidgets('eligible unpaid Job offers invoice only or whole-Job deletion',
      (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () async {
          result = await showInvoiceDeletionChoice(context,
            invoiceNumber:'6334',
            jobPlan: {
              'job_number':'J-10',
              'can_delete':true,
              'invoices':[{'number':'6333'},{'number':'6334'}],
              'estimates_preserved':[{'number':'E-25'}],
            },
          );
        },
        child: const Text('Open choice'),
      ),
    ))));
    await tester.tap(find.text('Open choice'));
    await tester.pumpAndSettle();
    expect(find.text('Delete invoice only'),findsOneWidget);
    expect(find.text('Delete invoice and Job'),findsOneWidget);
    expect(find.textContaining('2 unpaid invoices'),findsOneWidget);
    await tester.tap(find.text('Delete invoice and Job'));
    await tester.pumpAndSettle();
    expect(result,isTrue);
  });

  testWidgets('paid sibling blocks whole-Job option but keeps invoice-only',
      (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () async {
          result = await showInvoiceDeletionChoice(context,
            invoiceNumber:'6334',
            jobPlan: {
              'job_number':'J-10',
              'can_delete':false,
              'reason':'A linked invoice has payment activity',
              'invoices':[],
            },
          );
        },
        child: const Text('Open choice'),
      ),
    ))));
    await tester.tap(find.text('Open choice'));
    await tester.pumpAndSettle();
    expect(find.text('Delete invoice and Job'),findsNothing);
    expect(find.textContaining('payment activity'),findsOneWidget);
    await tester.tap(find.text('Delete invoice only'));
    await tester.pumpAndSettle();
    expect(result,isFalse);
  });
}
