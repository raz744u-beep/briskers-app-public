import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Jobs opens a single local-first Service History with visits under jobs', () {
    final source = File('lib/screens/customers/customer_detail_screen.dart').readAsStringSync();
    expect(source, contains('_showCustomerServiceHistory()'));
    expect(source, isNot(contains("link('Visits'")));
    expect(source, isNot(contains('No saved service history yet.')));
  });

  test('customer Job cards reuse the canonical local repository projection', () {
    final source = File('lib/screens/customers/customer_detail_screen.dart').readAsStringSync();
    expect(source, contains('LocalJobRepository().forCustomer('));
    final history = File('lib/screens/customers/customer_service_history_section.dart').readAsStringSync();
    expect(history, contains('LocalJobRepository().forCustomer('));
  });

  test('offline notices do not consume full customer or job header', () {
    final customer = File('lib/screens/customers/customer_detail_screen.dart')
        .readAsStringSync();
    final job = File('lib/screens/jobs/job_detail_screen.dart')
        .readAsStringSync();
    expect(customer, contains('Using saved local records. Edits sync on reconnection.'));
    expect(job, contains('Showing saved job data. Offline edits sync later.'));
    expect(customer, isNot(contains('Showing saved customer and vehicle data •')));
    expect(job, isNot(contains('Showing saved job data • offline-capable work')));
  });

  test('two estimate tabs are centered and compact Jobs filter matches', () {
    final tabs = File('lib/screens/jobs/job_document_screen.dart').readAsStringSync();
    expect(tabs, contains('alignment: isEstimate ? Alignment.center : Alignment.centerLeft'));
    expect(tabs, contains("label: tr('notesTab'),\n              alignment: Alignment.center"));
    final jobs = File('lib/screens/jobs_screen.dart').readAsStringSync();
    expect(jobs, contains('fit: FlexFit.loose'));
    expect(jobs, contains("_text('Open', 'Abiertos')"));
  });
}
