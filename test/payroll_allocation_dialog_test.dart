import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/screens/settings/payroll_allocation_dialog.dart';
import 'package:briskers_app/core/payroll_payment_contract.dart';
import 'local_payroll_outbox_test.dart' as fixture;

void main() {
  testWidgets(
    'partial allocation is explicit and cannot exceed cached earned balance',
    (tester) async {
      List<PayrollLaborAllocation>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<List<PayrollLaborAllocation>>(
                  context: context,
                  builder: (_) => const PayrollAllocationDialog(
                    labor: [
                      {
                        'labor_id': fixture.operation,
                        'earned_on': '2026-10-23',
                        'paid_hours': 2,
                        'available_cents': 12500,
                      },
                    ],
                    selected: [],
                  ),
                );
              },
              child: const Text('Allocate'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Allocate'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '126');
      await tester.tap(find.text('Apply allocations'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter an amount up to the available balance.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextFormField), '60.25');
      await tester.tap(find.text('Apply allocations'));
      await tester.pumpAndSettle();
      expect(result!.single.amountCents, 6025);
      expect(result!.single.laborId, fixture.operation);
    },
  );
}
