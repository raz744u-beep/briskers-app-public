import 'dart:io';

import 'package:briskers_app/widgets/retained_module_stack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _JobsProbe extends StatefulWidget {
  const _JobsProbe({required this.onInit});
  final VoidCallback onInit;

  @override
  State<_JobsProbe> createState() => _JobsProbeState();
}

class _JobsProbeState extends State<_JobsProbe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => const Text('Jobs retained');
}

void main() {
  testWidgets('repeated dock switches do not remount the Jobs module',
      (tester) async {
    var initializations = 0;
    Widget app(int index) => MaterialApp(
          home: RetainedModuleStack(
            index: index,
            itemCount: 8,
            itemBuilder: (_, itemIndex) => itemIndex == 2
                ? _JobsProbe(onInit: () => initializations++)
                : const SizedBox.shrink(),
          ),
        );
    await tester.pumpWidget(app(2));
    expect(initializations, 1);
    for (var i = 0; i < 8; i++) {
      await tester.pumpWidget(app(1));
      await tester.pumpWidget(app(2));
    }
    expect(initializations, 1,
        reason: 'Recreating Jobs discards existing cards and spins again.');
    expect(find.text('Jobs retained'), findsOneWidget);
  });

  test('Job Detail keeps the selected row read-only until verified', () {
    final jobs = File('lib/screens/jobs_screen.dart').readAsStringSync();
    final detail =
        File('lib/screens/jobs/job_detail_screen.dart').readAsStringSync();
    expect(jobs, contains('initialJobSummary: Map<String, dynamic>.from(job)'));
    expect(detail, contains('final Map<String, dynamic>? initialJobSummary;'));
    expect(detail, contains("title: Text('Opening saved job details…')"));
    expect(detail, contains('JobQuarantineViewGuard('));
    expect(detail, contains('LocalJobRetirement.isJobBlocked('));
    expect(detail, contains('LocalJobQuarantine.isJobBlocked('));
  });

  test('New Job customer picker queries a bounded local page', () {
    final picker = File('lib/screens/jobs/job_customer_picker_screen.dart')
        .readAsStringSync();
    final repo = File('lib/services/local_customer_repository.dart')
        .readAsStringSync();
    expect(picker, contains('limit: 100'));
    expect(picker, contains('search: query.isEmpty ? null : query'));
    expect(picker, contains('epoch != _searchEpoch'));
    expect(picker, contains('Clear customer search'));
    expect(repo, contains('int? limit,'));
    expect(repo, contains('final limitSql'));
    expect(repo, contains('Variable<int>(limit)'));
  });

  test('Customer search clears immediately and compact job numbers work', () {
    final customers =
        File('lib/screens/customers/customers_screen.dart').readAsStringSync();
    final jobs =
        File('lib/services/local_job_repository.dart').readAsStringSync();
    expect(customers, contains('Clear customer search'));
    expect(customers, contains('++_searchRequest;'));
    expect(jobs, contains("RegExp(r'^j[ -]?[0-9]+\$')"));
    expect(jobs, contains("Variable<String>('j-\$digits')"));
    expect(jobs, contains("Variable<String>('MB-\$query')"));
  });

  test('Invoices retain offline vehicle-finding warning independently of notes',
      () {
    final invoice = File('lib/screens/jobs/job_document_screen.dart')
        .readAsStringSync();
    expect(invoice, contains('_refreshInvoiceFindingsBanner(localOnly: true)'));
    expect(invoice, contains('_localFindingRecords.loadLocalFindings('));
    expect(invoice, contains('visibility.filterFindings(local)'));
    expect(invoice, contains('if (openFindings != null) _openFindings = openFindings;'));
    expect(invoice, contains('Failed transport cannot silently remove'));
    expect(invoice, contains('projectInvoiceNotes('));
  });

  test('Expenses avoids forced totals on resume and offers calendar presets',
      () {
    final expenses = File('lib/screens/expenses_screen.dart')
        .readAsStringSync();
    final lifecycle = expenses.indexOf('void didChangeAppLifecycleState(');
    final dispose = expenses.indexOf('void dispose()', lifecycle);
    expect(lifecycle, greaterThanOrEqualTo(0));
    expect(dispose, greaterThan(lifecycle));
    final resume = expenses.substring(lifecycle, dispose);
    expect(resume, contains('_load(showLoading: false)'));
    expect(resume, isNot(contains('forceTotals: true')));
    for (final preset in <String>['thisMonth', 'lastMonth', '3m', 'ytd']) {
      expect(expenses, contains("case '\$preset':"));
    }
    expect(expenses, contains('_monthsAgoClamped('));
    expect(expenses, contains('DateTime(today.year, today.month, 0)'));
    expect(expenses, contains('VerifiedExpenseTotalsCache().save('));
  });

  test('Findings photo input keeps 1920 limit and quality 100', () {
    final source = File(
      'lib/screens/customers/customer_vehicle_findings_section.dart',
    ).readAsStringSync();
    expect(RegExp('imageQuality: 100').allMatches(source).length, 4);
    expect(source, isNot(contains('imageQuality: 88')));
    expect(RegExp('maxWidth: 1920').allMatches(source).length, 4);
    expect(RegExp('maxHeight: 1920').allMatches(source).length, 4);
    expect(source, contains('InteractiveViewer('));
  });
}
