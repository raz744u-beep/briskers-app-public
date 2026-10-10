import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DOC-QUICK customer-created invoices offer the regular Add Item choices',
      () async {
    final customer = await File('lib/screens/customers/customer_detail_screen.dart')
        .readAsString();
    final invoice = await File('lib/screens/jobs/job_document_screen.dart')
        .readAsString();
    expect(customer, contains("initialAction: 'add_item'"));
    expect(invoice, contains("case 'add_item':\n        await _openAddItemChoices();"));
    expect(invoice, contains("title: Text(tr('addFromItemList'))"));
    expect(invoice, contains("title: Text(tr('addCustomLine'))"));
  });
}
