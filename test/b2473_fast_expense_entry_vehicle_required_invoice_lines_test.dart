import 'dart:io';

import 'package:briskers_app/screens/jobs/blank_invoice_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Both New Invoice and New Estimate require a real vehicle',
      (tester) async {
    for (final kind in ['invoice', 'estimate']) {
      await tester.pumpWidget(MaterialApp(
        home: BlankInvoiceSetupScreen(
          businessId: 'synthetic-shop',
          kind: kind,
          initialCustomerId: 'customer-synthetic',
          initialCustomerName: 'Test Customer',
          initialVehicles: const [],
        ),
      ));
      await tester.pump();
      final submit = find.byType(FilledButton);
      expect(submit, findsOneWidget);
      expect(tester.widget<FilledButton>(submit).onPressed, isNull,
          reason: 'A customer alone cannot create a document without a car');
      expect(find.textContaining('No saved vehicle'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(MaterialApp(
        home: BlankInvoiceSetupScreen(
          businessId: 'synthetic-shop',
          kind: kind,
          initialCustomerId: 'customer-synthetic',
          initialCustomerName: 'Test Customer',
          initialVehicles: const [
            {'id': 'vehicle-synthetic', 'year': 2018,
             'make': 'BMW', 'model': 'X3'},
          ],
        ),
      ));
      await tester.pump();
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNotNull, reason: 'Selecting customer and vehicle enables creation');
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  test('Add Expense opens form before transaction options hydrate', () {
    final source = File(
        'lib/screens/expenses/expense_entry_screen.dart').readAsStringSync();
    expect(source, contains('_loading = _editing || _copying;'));
    expect(source, contains('if (_optionsLoading) ...['));
    expect(source, contains('Loading saved accounts and categories…'));
    expect(source, contains('_accounts.isEmpty || _categories.isEmpty'));
    expect(source, contains('await _localFinancial.loadOptions('));
  });

  test('Adding an invoice item locally updates saved totals before HTTP', () {
    final source = File(
        'lib/screens/jobs/job_document_screen.dart').readAsStringSync();
    expect(source, contains('Future<void> _runAddLine('));
    expect(source, contains('await _detailCache.load('));
    expect(source, contains('setState(() {\n          _detail = saved;'));
    expect(source, contains('await _offlineDocumentEdit.addLine('));
    expect(source, contains('_startLineBackgroundSync();'));
    expect(source, contains('unawaited(() async {'));
    expect(source, contains('await _offlineDocumentEdit.flush('));
    expect(source.split('await _runAddLine(() async {').length - 1, 2);
    final local = File(
        'lib/services/offline_document_edit_service.dart').readAsStringSync();
    expect(local, contains('await _database.transaction(() async {'));
    expect(local, contains('await _saveDesired(businessId, documentId, detail, lines);'));
  });
}
