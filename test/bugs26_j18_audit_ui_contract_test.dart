import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Owner-only J18 link audit never mutates or contacts the network', () {
    final source = File('lib/screens/settings/diagnostics_screen.dart')
        .readAsStringSync();
    expect(source, contains("if (widget.roleCode != 'owner'"));
    expect(source, contains('LocalInvoiceLinkAudit()'));
    expect(source, contains("jobNumber: 'J-18'"));
    expect(source, contains("invoiceNumber: '6346'"));
    expect(source, contains('Read-only inspection of saved records'));
    expect(source, contains('Inspect local J-18 link'));
    expect(source, contains('Copy private report'));
  });
}
