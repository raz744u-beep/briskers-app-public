import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String source(String file) => File(file).readAsStringSync();

  test('Jobs sort includes six approved options in priority order', () {
    final screen = source('lib/screens/jobs_screen.dart');
    final labels = [
      'Newest first', 'Recently updated', 'By job status',
      'Appointment date', 'Customer A–Z', 'Oldest first',
    ];
    var previous = -1;
    for (final label in labels) {
      final current = screen.indexOf("Text('$label')");
      expect(current, greaterThan(previous), reason: label);
      previous = current;
    }
    final repository = source('lib/services/local_job_repository.dart');
    expect(repository, contains('final sortSql = switch (sort)'));
    expect(repository, contains('LIMIT ? OFFSET ?'));
    expect(repository.indexOf('ORDER BY'), lessThan(repository.indexOf('LIMIT ? OFFSET ?')));
  });

  test('Secretary invoice entry retains linked-expense permissions', () {
    final shell = source('lib/screens/shell_screen.dart');
    expect(shell, contains("'owner', 'manager', 'office'"));
    expect(shell, contains('canManageExpenses:'));
    final invoice = source('lib/screens/jobs/job_document_screen.dart');
    expect(invoice, contains("tooltip: 'Add linked expense'"));
  });

  test('Invoice palette separates paid, closed, partial and pending', () {
    final styles = source('lib/core/invoice_status_style.dart');
    expect(styles, contains('Color(0xFF4856A6)'));
    expect(styles, contains('Color(0xFFDA6D13)'));
    final list = source('lib/screens/documents_screen.dart');
    for (final hex in ['0xFFFFF8DA','0xFFFFE8CD','0xFFE8F5ED','0xFFE9ECFA']) {
      expect(list, contains(hex));
    }
  });

  test('Photo picker presents camera before gallery', () {
    for (final path in [
      'lib/screens/expenses/expense_entry_screen.dart',
      'lib/screens/expenses/expense_detail_screen.dart',
      'lib/screens/jobs/job_detail_screen.dart',
    ]) {
      final file = source(path);
      final camera = file.indexOf("title: const Text('Take photo')");
      final gallery = file.indexOf("title: const Text('Choose from gallery')");
      expect(camera, greaterThanOrEqualTo(0), reason: path);
      expect(gallery, greaterThan(camera), reason: path);
    }
  });

  test('Invoice numeric fields select text each tap', () {
    final invoice = source('lib/screens/jobs/job_document_screen.dart');
    expect(invoice, isNot(contains('_quantityCleared')));
    expect(invoice, isNot(contains('_priceCleared')));
    expect(invoice, contains('if (!widget.clearNumericOnFirstTap) return;'));
  });

  test('Paid invoice completion remains separate from financial closing', () {
    final invoice = source('lib/screens/jobs/job_document_screen.dart');
    expect(invoice, contains("title: const Text('Mark Job Completed?')"));
    expect(invoice, contains("child: const Text('Keep In Progress')"));
    expect(invoice, contains("child: const Text('Complete Job')"));
    expect(invoice, contains("await _api.changeJobStatus(widget.businessId, jobId, 'completed')"));
  });

  test('Every role sees About with app version', () {
    final settings = source('lib/screens/settings/settings_screen.dart');
    expect(settings, contains("title: const Text('About Briskers')"));
    expect(settings, contains('info.buildNumber'));
  });
}
