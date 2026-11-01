import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:briskers_app/tasks_payroll_smoke_main.dart';

void main() {
  testWidgets('standalone smoke launch, selection, settlement, replay and reset', (tester) async {
    await tester.runAsync(() async {
      Future<void> waitFor(Finder finder) async {
        for (var attempt = 0; attempt < 100; attempt++) {
          await tester.pump();
          if (finder.evaluate().isNotEmpty) return;
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(finder, findsWidgets);
      }

      await tester.pumpWidget(const TasksPayrollTestApp());
      await waitFor(find.text('No eligible local work credits available.'));
      expect(find.text('Briskers Tasks / Payroll TEST'), findsOneWidget);
      await tester.tap(find.text('Create synthetic completed task + stage'));
      await waitFor(find.text('Synthetic work staged — NOT PAID'));
      await waitFor(find.byType(CheckboxListTile));
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      expect(find.text('Selected gross: \$100.00'), findsOneWidget);
      await tester.ensureVisible(find.text('Verify synthetic payment only'));
      await tester.tap(find.text('Verify synthetic payment only'));
      await waitFor(find.text('Synthetic transaction recorded locally — NOT real payroll'));
      await waitFor(find.text('No eligible local work credits available.'));
      await tester.tap(find.text('Verify synthetic payment only'));
      await waitFor(find.text('Same synthetic transaction already recorded'));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(const TasksPayrollTestApp());
      await waitFor(find.text('No eligible local work credits available.'));
      expect(find.text('Synthetic TEST only — no real payments'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
