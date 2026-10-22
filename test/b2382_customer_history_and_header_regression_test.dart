import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('customer overview reuses durable local jobs and documents offline', () {
    final source = File('lib/screens/customers/customer_detail_screen.dart')
        .readAsStringSync();
    final start = source.indexOf('Future<Map<String, dynamic>> _loadOfflineSections()');
    final end = source.indexOf('Future<List<Map<String, dynamic>>> _activeCustomerItems()', start);
    final text = source.substring(start, end);
    expect(text, contains('final localItems = await _activeCustomerItems();'));
    expect(text, contains("history['jobs'] = combine("));
    expect(text, contains("history['documents'] = combine("));
    expect(text, contains('found[id] = row'));
    expect(text, contains('visibility.filter('));
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
