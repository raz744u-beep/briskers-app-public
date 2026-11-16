import 'package:briskers_app/core/briskers_i18n.dart';
import 'package:briskers_app/services/job_profitability_summary.dart';
import 'package:briskers_app/widgets/job_profitability_summary_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await BriskersLanguageController.instance.setLanguage('en');
  });

  for (final language in ['en', 'es']) {
    testWidgets('narrow 200% profitability remains readable in $language', (
      tester,
    ) async {
      await BriskersLanguageController.instance.setLanguage(language);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final summary = JobProfitabilitySummary.fromRpc({
        'revenue': 1000,
        'sales_tax': 80,
        'direct_cost': 800,
        'mechanic_cost': 400,
        'total_cost': 1200,
      })!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: JobProfitabilitySummaryView(
                    summary: summary,
                    formatMoney: (value) => '\$${value.toStringAsFixed(2)}',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(tr('profitabilityTaxExcluded')), findsOneWidget);
      expect(find.text(tr('profitabilityBasisNote')), findsOneWidget);
      expect(find.text(tr('profitabilityLaborCost')), findsOneWidget);
      await tester.ensureVisible(
        find.text(tr('profitabilityNetBeforeOverhead')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final loss = tester.widget<Text>(find.text(r'$-200.00'));
      expect(loss.style?.color, Colors.red.shade700);
      expect(find.text('Gross profit'), findsNothing);
      if (language == 'es') {
        expect(find.text('Job financial summary'), findsNothing);
        expect(tr('profitabilityIncomplete'), contains('incompletos'));
      }
    });
  }

  testWidgets(
    'zero revenue displays unavailable margin instead of false zero',
    (tester) async {
      await BriskersLanguageController.instance.setLanguage('en');
      final summary = JobProfitabilitySummary.fromRpc({
        'revenue': 0,
        'sales_tax': 0,
        'direct_cost': 0,
        'mechanic_cost': 0,
      })!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: JobProfitabilitySummaryView(
                summary: summary,
                formatMoney: (value) => '\$${value.toStringAsFixed(2)}',
              ),
            ),
          ),
        ),
      );
      expect(find.text(tr('profitabilityMarginUnavailable')), findsOneWidget);
      expect(find.text('Margin: 0.0%'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('phone profitability uses four compact summary cards', (
    tester,
  ) async {
    await BriskersLanguageController.instance.setLanguage('en');
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final summary = JobProfitabilitySummary.fromRpc({
      'revenue': 1000,
      'sales_tax': 80,
      'direct_cost': 300,
      'mechanic_cost': 200,
    })!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: JobProfitabilitySummaryView(
                summary: summary,
                formatMoney: (value) => '\$${value.toStringAsFixed(2)}',
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Revenue'), findsOneWidget);
    expect(find.text('Costs'), findsOneWidget);
    expect(find.text('Profit'), findsOneWidget);
    expect(find.text('Margin'), findsOneWidget);
    final revenue = tester.getTopLeft(find.text('Revenue'));
    final costs = tester.getTopLeft(find.text('Costs'));
    final profit = tester.getTopLeft(find.text('Profit'));
    expect(costs.dy, revenue.dy);
    expect(costs.dx, greaterThan(revenue.dx));
    expect(profit.dy, greaterThan(revenue.dy));
    expect(find.text('50.0%'), findsOneWidget);
    expect(find.text(tr('profitabilityTaxExcluded')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
