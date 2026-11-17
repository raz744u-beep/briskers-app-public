import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('customer tabs share one fixed New button with scrolling clearance', () {
    final source = File('lib/screens/customers/customer_detail_screen.dart')
        .readAsStringSync();
    final scaffold = source.indexOf('floatingActionButton:');
    final body = source.indexOf('body: _data == null', scaffold);
    expect(scaffold, greaterThan(0));
    expect(body, greaterThan(scaffold));
    final fab = source.substring(scaffold, body);
    expect(fab, isNot(contains('_customerTab')));
    expect(fab, contains('!_canManageQuickActions'));
    expect(fab, contains('FloatingActionButton.extended('));
    expect(fab, contains('onPressed: _showQuickActions'));
    expect(fab, contains("label: const Text('New')"));
    expect(source, contains('EdgeInsets.fromLTRB(16,16,16,100)'));
    expect(source, isNot(contains('New Message')));
  });

  test('tax editor releases numeric keyboard focus when dismissed', () {
    final code = File('lib/screens/jobs/job_document_screen.dart')
        .readAsStringSync();
    final a = code.indexOf('Future<void> _editInvoiceTax(');
    final b = code.indexOf('String _taxLabel(', a);
    expect(a, greaterThan(0));
    expect(b, greaterThan(a));
    final modal = code.substring(a, b);
    expect(modal, contains('FocusScope.of(dialogContext).unfocus();'));
    expect(
      'FocusScope.of(dialogContext).unfocus();'
          .allMatches(modal).length,
      2,
    );
  });
}
