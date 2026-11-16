import 'package:briskers_app/widgets/financial_summary_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cases = [
    (FinancialSummaryTone.subtotal, 'Subtotal', Color(0xFFE6EDF5)),
    (FinancialSummaryTone.total, 'Total', Color(0xFFE1EDFC)),
    (FinancialSummaryTone.balanceDue, 'Balance Due', Color(0xFFFBE5E5)),
    (FinancialSummaryTone.balanceSettled, 'Balance Due', Color(0xFFE2F6E4)),
  ];

  for (final (tone, label, expectedBackground) in cases) {
    testWidgets('$label keeps a compact colored treatment without changing money',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        home: Scaffold(
          body: FinancialSummaryRow(
            label: label,
            value: r'$2,113.24',
            tone: tone,
          ),
        ),
      ));

      expect(find.text(label), findsOneWidget);
      expect(find.text(r'$2,113.24'), findsOneWidget);
      final row = find.byType(FinancialSummaryRow);
      expect(tester.getSize(row).height, lessThan(58));
      final container = tester.widget<Container>(
        find.descendant(of: row, matching: find.byType(Container)).first,
      );
      expect((container.decoration! as BoxDecoration).color,
          expectedBackground);
    });
  }

  testWidgets('dark mode has a dark readable subtotal band', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: const Scaffold(
        body: FinancialSummaryRow(
          label: 'Subtotal',
          value: r'$1,925.50',
          tone: FinancialSummaryTone.subtotal,
        ),
      ),
    ));
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(FinancialSummaryRow),
        matching: find.byType(Container),
      ).first,
    );
    expect((container.decoration! as BoxDecoration).color,
        const Color(0xFF27374A));
    expect(find.text(r'$1,925.50'), findsOneWidget);
  });
}
