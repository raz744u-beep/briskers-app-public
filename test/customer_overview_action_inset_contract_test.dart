import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('customer Overview uses one quick-action button, no overlay FAB', () {
    final source = File('lib/screens/customers/customer_detail_screen.dart')
        .readAsStringSync();
    final scaffold = source.indexOf('floatingActionButton:');
    final body = source.indexOf('body: _data == null', scaffold);
    expect(scaffold, greaterThan(0));
    expect(body, greaterThan(scaffold));
    final fab = source.substring(scaffold, body);
    expect(fab, contains('_customerTab == 0'));
    expect(fab, contains('!_canManageQuickActions'));
    expect(fab, contains('FloatingActionButton('));
    final overview = source.indexOf('if (_customerTab == 0 && _canManageQuickActions)');
    expect(overview, greaterThan(body));
    final newAction = source.substring(overview, overview + 600);
    expect(newAction, contains('onPressed: _showQuickActions'));
    expect(newAction, contains("label: const Text('New')"));
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
